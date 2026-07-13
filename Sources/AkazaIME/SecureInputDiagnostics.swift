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

    /// 保持プロセスのアプリ名（GUI アプリでなければ nil）。
    static func holderName() -> String? {
        guard let pid = holderPID() else { return nil }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    /// ログ用の保持プロセス説明。例: "pid=14255 Ghostty (com.mitchellh.ghostty)"
    static func holderDescription() -> String {
        guard let pid = holderPID() else { return "holder unknown" }
        if let app = NSRunningApplication(processIdentifier: pid) {
            let name = app.localizedName ?? "?"
            let bundle = app.bundleIdentifier ?? "?"
            return "pid=\(pid) \(name) (\(bundle))"
        }
        return "pid=\(pid)"
    }

    /// Secure Input が有効ならログに残す。呼び出し元の文脈を context で示す。
    static func logIfActive(_ context: String) {
        guard isActive else { return }
        NSLog(
            "AkazaIME[diag]: SECURE EVENT INPUT ACTIVE (\(holderDescription())) ctx=\(context) — キーイベントは IME に配送されない"
        )
    }
}
