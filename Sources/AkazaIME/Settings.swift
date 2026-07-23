import Foundation

enum PunctuationStyle: Int {
    case kutouten = 0    // 、。
    case commaPeriod = 1 // ，．
}

class Settings {
    static let shared = Settings()

    private let defaults: UserDefaults

    private enum DefaultsName {
        static let showPredictiveCandidates = "showPredictiveCandidates"
        static let notifyOnSecureInput = "notifyOnSecureInput"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            DefaultsName.showPredictiveCandidates: true,
            DefaultsName.notifyOnSecureInput: false
        ])
    }

    var punctuationStyle: PunctuationStyle {
        get { PunctuationStyle(rawValue: defaults.integer(forKey: "punctuationStyle")) ?? .kutouten }
        set { defaults.set(newValue.rawValue, forKey: "punctuationStyle") }
    }

    var additionalDictPaths: [String] {
        get { defaults.stringArray(forKey: "additionalDictPaths") ?? [] }
        set { defaults.set(newValue, forKey: "additionalDictPaths") }
    }

    var showPredictiveCandidates: Bool {
        get { defaults.bool(forKey: DefaultsName.showPredictiveCandidates) }
        set { defaults.set(newValue, forKey: DefaultsName.showPredictiveCandidates) }
    }

    // Secure Input wedge (他プロセスが Secure Event Input を握って日本語入力が死ぬ) の
    // 検出時にユーザー通知を出すか。通知許可ダイアログを伴うためデフォルトはオフ。
    var notifyOnSecureInput: Bool {
        get { defaults.bool(forKey: DefaultsName.notifyOnSecureInput) }
        set { defaults.set(newValue, forKey: DefaultsName.notifyOnSecureInput) }
    }

    var romkanTable: String {
        get { defaults.string(forKey: "romkanTable") ?? "default" }
        set { defaults.set(newValue, forKey: "romkanTable") }
    }

    // サジェスト候補の最大パス数。k=9 は速度が遅いため k=5 をデフォルトとする (2026-02-26)
    // defaults write com.github.tokuhirom.inputmethod.Japanese.Akaza suggestMaxPaths -int 5
    var suggestMaxPaths: Int {
        get {
            let value = defaults.integer(forKey: "suggestMaxPaths")
            if value <= 0 { return 5 }
            return min(value, 20)
        }
        set { defaults.set(newValue, forKey: "suggestMaxPaths") }
    }
}
