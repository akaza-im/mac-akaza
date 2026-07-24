import AppKit
import Carbon
import IOKit

/// Secure Event Input の検出。
///
/// どこかのプロセスが Secure Keyboard Entry (`EnableSecureEventInput`) を有効にしている間、
/// macOS はキーイベントを IME に配送しない（パスワード入力保護のための仕様）。
/// このとき activateServer 等の制御メッセージは届き続けるため、
/// 「プロセスは生きているのに handle だけ来ない」サイレント wedge に見える。
///
/// 2026-07-13 の調査で、スリープ復帰後 wedge の実際の原因がこれ
/// （ターミナルアプリのパスワード検出による Secure Input の解放漏れ）と確定した。
/// 詳細は docs/sleep-wake-investigation.md §11。
enum SecureInputDiagnostics {
    /// Secure Event Input が有効かどうか。
    static var isActive: Bool {
        IsSecureEventInputEnabled()
    }

    /// Secure Event Input を保持しているプロセスの PID。
    /// IORegistry ルートの IOConsoleUsers / kCGSSessionSecureInputPID から取得する。
    static func holderPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard
            let users = IORegistryEntryCreateCFProperty(
                root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue() as? [[String: Any]]
        else { return nil }
        for user in users {
            if let pid = user["kCGSSessionSecureInputPID"] as? Int {
                return pid_t(pid)
            }
        }
        return nil
    }

    /// 保持プロセスの生死を含む状態。
    ///
    /// 保持プロセスが終了しても Secure Input が API レベルで解放されず残留することがある
    /// （2026-07-24 実測: wezterm 終了後も IsSecureEventInputEnabled()=true が 5 分以上継続）。
    /// このとき「保持アプリを再起動してください」という案内は成立しないため、状態を区別する。
    enum HolderState: Equatable {
        /// 保持プロセスが生存している
        case alive(pid: pid_t)
        /// 保持プロセスは終了したが Secure Input が解放されていない（残留）
        case dead(pid: pid_t)
        /// 保持プロセスの PID が取得できない
        case unknown
    }

    static func holderState() -> HolderState {
        guard let pid = holderPID() else { return .unknown }
        return isProcessAlive(pid) ? .alive(pid: pid) : .dead(pid: pid)
    }

    /// プロセスの生存確認。kill(pid, 0) はシグナルを送らず存在チェックだけを行う。
    /// EPERM は「存在するが権限なし」なので生存扱い。
    /// NSRunningApplication の nil は「GUI アプリでない」と「死んでいる」を区別できないため使わない。
    static func isProcessAlive(_ pid: pid_t) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// 保持プロセスのアプリ名（GUI アプリでなければ nil）。
    static func holderName() -> String? {
        guard let pid = holderPID() else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// 保持プロセスの bundle identifier（GUI アプリでなければ nil）。
    static func holderBundleIdentifier() -> String? {
        guard let pid = holderPID() else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
    }

    /// 保持プロセスとフォーカス中アプリの bundleId 比較による正当性判定
    /// (fcitx5-macos PR #269 の輸入)。
    /// 一致 = フォーカス中アプリのパスワード欄による正当な Secure Input。
    /// 不一致 = バックグラウンドアプリの解放漏れの疑い。
    /// 判定不能（どちらかが nil）は疑わしい側 (false) に倒す。
    static func isLegitimate(holderBundle: String?, frontmostBundle: String?) -> Bool {
        guard let holderBundle, let frontmostBundle else { return false }
        return holderBundle == frontmostBundle
    }

    /// 現在の保持プロセスがフォーカス中アプリ自身かどうか。
    static func holderLooksLegitimate() -> Bool {
        isLegitimate(
            holderBundle: holderBundleIdentifier(),
            frontmostBundle: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }

    /// ログ用の保持プロセス説明。例: "pid=14255 Ghostty (com.mitchellh.ghostty)"
    static func holderDescription() -> String {
        guard let pid = holderPID() else { return "holder unknown" }
        if let app = NSRunningApplication(processIdentifier: pid) {
            let name = app.localizedName ?? "?"
            let bundle = app.bundleIdentifier ?? "?"
            return "pid=\(pid) \(name) (\(bundle))"
        }
        return isProcessAlive(pid) ? "pid=\(pid)" : "pid=\(pid) (terminated)"
    }

    /// Secure Input が有効ならログに残す。呼び出し元の文脈を context で示す。
    /// front / legit は解放漏れか正当なパスワード入力かの事後判別用。
    static func logIfActive(_ context: String) {
        guard isActive else { return }
        let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
        NSLog(
            "AkazaIME[diag]: SECURE EVENT INPUT ACTIVE (\(holderDescription())) front=\(front) legit=\(holderLooksLegitimate()) ctx=\(context) — キーイベントは IME に配送されない"
        )
    }
}
