import AppKit
import UserNotifications

/// Secure Event Input 検出時のユーザー通知。
///
/// Secure Input wedge はログ (akaza.log) と入力メニューの警告だけでは気づきにくい
/// （2026-07-23 の再発時、警告は11回記録されていたがユーザーは気づけなかった）。
/// 設定 `notifyOnSecureInput` が有効なときのみ通知センターに警告を出す。デフォルトはオフ。
enum SecureInputNotifier {
    private static let notificationIdentifier = "secure-input-active"

    /// 同一の有効化エピソード内で通知済みか。
    /// activateServer は数秒おきに連発するため、エピソードの最初の1回だけ通知する。
    /// Secure Input が解放されたことを観測したらリセットする。
    private static var notifiedThisEpisode = false

    /// Secure Input の状態を確認し、必要なら通知する。
    /// activateServer / didWake など、Secure Input 中でも届くイベントから呼ぶ。
    static func check() {
        guard Settings.shared.notifyOnSecureInput else { return }
        guard SecureInputDiagnostics.isActive else {
            notifiedThisEpisode = false
            return
        }
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
        guard !notifiedThisEpisode else { return }
        notifiedThisEpisode = true
        deliver(holderName: SecureInputDiagnostics.holderName())
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

    private static func deliver(holderName: String?) {
        let content = UNMutableNotificationContent()
        content.title = "日本語入力が無効になっています"
        let holder = holderName ?? "他のプロセス"
        content.body =
            "「\(holder)」が Secure Input を有効化しているため、キー入力が IME に届きません。"
            + "解放されない場合は「\(holder)」を再起動してください。"
        // identifier を固定し、既存通知を置き換えて積み上がらないようにする
        let request = UNNotificationRequest(
            identifier: notificationIdentifier, content: content, trigger: nil)
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
