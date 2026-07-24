import AppKit
import UserNotifications

/// Secure Event Input 検出時のユーザー通知。
///
/// Secure Input wedge はログ (akaza.log) と入力メニューの警告だけでは気づきにくい
/// （2026-07-23 の再発時、警告は11回記録されていたがユーザーは気づけなかった）。
/// 設定 `notifyOnSecureInput` が有効なときのみ通知センターに警告を出す。デフォルトはオフ。
enum SecureInputNotifier {
    private static let notificationIdentifier = "secure-input-active"

    /// 直近に通知した保持者の状況。
    /// activateServer は数秒おきに連発するため同一状況では 1 回だけ通知するが、
    /// 「保持アプリを再起動したのに死んだ pid が Secure Input を握ったまま残留」のように
    /// 状況が変わったら案内を更新して再通知したいので、bool ではなく状態で覚える。
    /// Secure Input が解放されたことを観測したらリセットする。
    private enum NotifiedState: Equatable {
        case none
        case aliveHolder(pid: pid_t)
        case deadHolder(pid: pid_t)
        case unknownHolder
    }
    private static var notified: NotifiedState = .none

    /// Secure Input の状態を確認し、必要なら通知する。
    /// activateServer / didWake など、Secure Input 中でも届くイベントから呼ぶ。
    static func check() {
        guard Settings.shared.notifyOnSecureInput else { return }
        guard SecureInputDiagnostics.isActive else {
            notified = .none
            return
        }
        switch SecureInputDiagnostics.holderState() {
        case .alive(let pid):
            // ロック画面 (loginwindow) の保持は正当かつ一時的なので通知しない。
            // didWake 時はほぼ毎回 loginwindow が保持しているため、これを除外しないと wake のたびに鳴る。
            if SecureInputDiagnostics.holderBundleIdentifier() == "com.apple.loginwindow" {
                return
            }
            // フォーカス中アプリ自身の保持は本物のパスワード欄（正当・一時的）なので通知しない。
            // 解放漏れならフォーカスが他アプリに移った後の activateServer で不一致になり通知される。
            if SecureInputDiagnostics.holderLooksLegitimate() {
                return
            }
            guard notified != .aliveHolder(pid: pid) else { return }
            notified = .aliveHolder(pid: pid)
            deliver(body: bodyText(holderName: SecureInputDiagnostics.holderName()))
        case .dead(let pid):
            guard notified != .deadHolder(pid: pid) else { return }
            notified = .deadHolder(pid: pid)
            deliver(body: deadHolderBodyText(pid: pid))
        case .unknown:
            guard notified != .unknownHolder else { return }
            notified = .unknownHolder
            deliver(body: bodyText(holderName: nil))
        }
    }

    /// 保持プロセスが生きている（または不明な）場合の本文。再起動を案内する。
    static func bodyText(holderName: String?) -> String {
        let holder = holderName ?? "他のプロセス"
        return "「\(holder)」が Secure Input を有効化しているため、キー入力が IME に届きません。"
            + "解放されない場合は「\(holder)」を再起動してください。"
    }

    /// 保持プロセスが既に終了している場合の本文。
    /// 死んだプロセスは再起動できないため、実測で解放を確認済みの回復手段
    /// （画面ロック → 解錠、2026-07-13）を案内する。
    static func deadHolderBodyText(pid: pid_t) -> String {
        "Secure Input を有効化したプロセス (pid=\(pid)) は既に終了しましたが、"
            + "Secure Input が解放されずに残っています。"
            + "画面をロック（Ctrl+Cmd+Q）して解錠すると解放されることがあります。"
    }

    /// 通知許可をリクエストする。設定でオンにしたタイミング（ユーザー操作中）に呼ぶ。
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, error in
            if let error {
                NSLog("AkazaIME: notification authorization failed: \(error)")
            } else if !granted {
                NSLog("AkazaIME: notification authorization denied")
            }
        }
    }

    private static func deliver(body: String) {
        let content = UNMutableNotificationContent()
        content.title = "日本語入力が無効になっています"
        content.body = body
        // identifier を固定し、既存通知を置き換えて積み上がらないようにする
        let request = UNNotificationRequest(
            identifier: notificationIdentifier, content: content, trigger: nil)
        let holder = SecureInputDiagnostics.holderDescription()
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("AkazaIME: failed to deliver secure input notification: \(error)")
            } else {
                // 通知が実際に出たかを akaza.log から事後確認できるようにする
                NSLog("AkazaIME: secure input notification delivered (holder=\(holder))")
            }
        }
    }
}
