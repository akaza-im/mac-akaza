import Carbon
import Foundation

// スリープ復帰後に Akaza の入力ソースが OS によって無効化（メニューバーで disabled）
// される "サイレント wedge" への対策。
//
// 観測された症状: wake 後に Akaza が AppleEnabledInputSources から外され、選択不能になる。
// プロセスは生存しているため、本プロセス内から TISEnableInputSource で再有効化できる。
//
// 注意:
//   - 再有効化対象は「入力メソッド本体」と「.Japanese モード」に限定する。
//     `.Roman` モードは正常時から無効（ユーザーが使っていない）なので触らない。
//   - 操作前に全 Akaza 系入力ソースの有効状態をログに残す。次回再発時に
//     「どのエントリが無効化されたか」を確定し、因果の裏取りに使う。
enum InputSourceEnabler {
    /// 入力メソッド本体の ID。バンドル ID と一致する。
    private static var inputMethodID: String {
        Bundle.main.bundleIdentifier ?? "com.github.tokuhirom.inputmethod.Japanese.Akaza"
    }

    /// 再有効化対象の入力ソース ID 群（本体 + 主要モード）。`.Roman` は含めない。
    private static var targetIDs: [String] {
        let base = inputMethodID
        return [base, base + ".Japanese"]
    }

    /// 無効化されていれば再有効化する。再有効化を 1 件以上行ったら true。
    /// 冪等: 既に有効な入力ソースには何もしない。
    @discardableResult
    static func enableIfDisabled() -> Bool {
        guard let listRef = TISCreateInputSourceList(nil, true)?.takeRetainedValue() else {
            NSLog("AkazaIME[diag]: TISCreateInputSourceList failed")
            return false
        }
        let count = CFArrayGetCount(listRef)
        let targets = Set(targetIDs)
        var enabledAny = false
        for index in 0..<count {
            let src = unsafeBitCast(CFArrayGetValueAtIndex(listRef, index), to: TISInputSource.self)
            guard let id = stringProperty(src, kTISPropertyInputSourceID), id.contains("Akaza") else { continue }
            let isEnabled = boolProperty(src, kTISPropertyInputSourceIsEnabled) ?? false
            let canEnable = boolProperty(src, kTISPropertyInputSourceIsEnableCapable) ?? false
            // 検証用: 全 Akaza 系ソースの状態を記録する（再発時にどれが落ちたか確定するため）。
            NSLog("AkazaIME[diag]: TIS source id=\(id) enabled=\(isEnabled) enableCapable=\(canEnable)")
            guard targets.contains(id), !isEnabled, canEnable else { continue }
            let status = TISEnableInputSource(src)
            NSLog("AkazaIME[diag]: re-enabled disabled input source id=\(id) status=\(status)")
            if status == noErr { enabledAny = true }
        }
        return enabledAny
    }

    /// wake 直後は OS による無効化のタイミングが読めないため、複数の遅延で再試行する。
    static func scheduleReEnable(delays: [Double] = [0, 2, 10, 30]) {
        for delay in delays {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                _ = enableIfDisabled()
            }
        }
    }

    private static func boolProperty(_ src: TISInputSource, _ key: CFString) -> Bool? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }

    private static func stringProperty(_ src: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(src, key) else { return nil }
        return (Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String)
    }
}
