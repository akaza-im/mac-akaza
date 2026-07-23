import Cocoa
import InputMethodKit

// MARK: - Menu

extension AkazaInputController {
    override func menu() -> NSMenu! {
        let menu = NSMenu()
        // Secure Input を他プロセスが握っていると日本語入力が全アプリで効かなくなる。
        // ユーザーがログを見なくても原因に気づけるよう、入力メニューに警告を出す。
        // フォーカス中アプリ自身の保持は本物のパスワード欄（正当・一時的）なので警告しない
        // (fcitx5-macos PR #269 方式)。
        if SecureInputDiagnostics.isActive && !SecureInputDiagnostics.holderLooksLegitimate() {
            let holder = SecureInputDiagnostics.holderName() ?? "不明なプロセス"
            let warnItem = NSMenuItem(
                title: "⚠️ 「\(holder)」が Secure Input を有効化中 — 日本語入力不可",
                action: nil, keyEquivalent: "")
            menu.addItem(warnItem)
            menu.addItem(NSMenuItem.separator())
        }
        let registerItem = NSMenuItem(
            title: "単語を登録...", action: #selector(registerWord(_:)), keyEquivalent: "")
        registerItem.target = self
        menu.addItem(registerItem)
        menu.addItem(NSMenuItem.separator())
        let settingsItem = NSMenuItem(
            title: "設定...", action: #selector(openSettings(_:)), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        return menu
    }

    @objc func registerWord(_ sender: Any?) {
        let prefillYomi: String?
        switch inputState {
        case .composing:
            let yomi = composedHiragana.isEmpty ? nil : composedHiragana
            prefillYomi = yomi
        default:
            prefillYomi = nil
        }
        NSApp.activate(ignoringOtherApps: true)
        UserDictionaryView.showAddEntryDialog(prefillYomi: prefillYomi)
    }

    @objc func openSettings(_ sender: Any?) {
        PreferencesWindowController.shared.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }
}
