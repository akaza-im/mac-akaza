import Cocoa
import InputMethodKit

// MARK: - Menu

extension AkazaInputController {
    override func menu() -> NSMenu! {
        let menu = NSMenu()
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
