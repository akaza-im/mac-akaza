import Cocoa

class GeneralSettingsView: NSView {
    private let punctuationPopUp = NSPopUpButton()
    let romkanPopUp = NSPopUpButton()
    private let showPredictiveCandidatesCheckbox = NSButton(
        checkboxWithTitle: "推測候補表示",
        target: nil,
        action: nil
    )
    private let notifyOnSecureInputCheckbox = NSButton(
        checkboxWithTitle: "他アプリの Secure Input で日本語入力が無効になったら通知",
        target: nil,
        action: nil
    )
    private let modelVersionLabel = NSTextField(labelWithString: "読み込み中...")
    private let modelBuildTimestampLabel = NSTextField(labelWithString: "")
    let userDictTableView = NSTableView()
    let addDictButton = NSButton(title: "+ 追加", target: nil, action: nil)
    let removeDictButton = NSButton(title: "- 削除", target: nil, action: nil)

    // ダウンロード可能辞書の行ごとのステータス更新クロージャ
    var dictRowUpdaters: [() -> Void] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadModelInfo()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadModelInfo()
    }

    private func setupUI() {
        let punctuationLabel = NSTextField(labelWithString: "句読点スタイル:")
        punctuationLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(punctuationLabel)

        punctuationPopUp.translatesAutoresizingMaskIntoConstraints = false
        punctuationPopUp.addItems(withTitles: [
            "「、。」（標準）",
            "「，．」（カンマ・ピリオド）"
        ])
        punctuationPopUp.selectItem(at: Settings.shared.punctuationStyle.rawValue)
        punctuationPopUp.target = self
        punctuationPopUp.action = #selector(punctuationStyleChanged(_:))
        addSubview(punctuationPopUp)

        let romkanLabel = setupRomkanControls()

        showPredictiveCandidatesCheckbox.translatesAutoresizingMaskIntoConstraints = false
        showPredictiveCandidatesCheckbox.state = Settings.shared.showPredictiveCandidates ? .on : .off
        showPredictiveCandidatesCheckbox.target = self
        showPredictiveCandidatesCheckbox.action = #selector(showPredictiveCandidatesChanged(_:))
        addSubview(showPredictiveCandidatesCheckbox)

        notifyOnSecureInputCheckbox.translatesAutoresizingMaskIntoConstraints = false
        notifyOnSecureInputCheckbox.state = Settings.shared.notifyOnSecureInput ? .on : .off
        notifyOnSecureInputCheckbox.target = self
        notifyOnSecureInputCheckbox.action = #selector(notifyOnSecureInputChanged(_:))
        addSubview(notifyOnSecureInputCheckbox)

        NSLayoutConstraint.activate([
            punctuationLabel.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            punctuationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            punctuationLabel.widthAnchor.constraint(equalToConstant: 90),

            punctuationPopUp.centerYAnchor.constraint(equalTo: punctuationLabel.centerYAnchor),
            punctuationPopUp.leadingAnchor.constraint(equalTo: punctuationLabel.trailingAnchor, constant: 8),
            punctuationPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            romkanLabel.topAnchor.constraint(equalTo: punctuationLabel.bottomAnchor, constant: 12),
            romkanLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            romkanLabel.widthAnchor.constraint(equalToConstant: 90),

            romkanPopUp.centerYAnchor.constraint(equalTo: romkanLabel.centerYAnchor),
            romkanPopUp.leadingAnchor.constraint(equalTo: romkanLabel.trailingAnchor, constant: 8),
            romkanPopUp.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),

            showPredictiveCandidatesCheckbox.topAnchor.constraint(
                equalTo: romkanLabel.bottomAnchor, constant: 12),
            showPredictiveCandidatesCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            showPredictiveCandidatesCheckbox.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -20),

            notifyOnSecureInputCheckbox.topAnchor.constraint(
                equalTo: showPredictiveCandidatesCheckbox.bottomAnchor, constant: 8),
            notifyOnSecureInputCheckbox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            notifyOnSecureInputCheckbox.trailingAnchor.constraint(
                lessThanOrEqualTo: trailingAnchor, constant: -20)
        ])

        let lastModelView = setupModelInfoViews(below: notifyOnSecureInputCheckbox)
        setupDictViews(below: lastModelView)
    }

    @discardableResult
    private func setupModelInfoViews(below aboveView: NSView) -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let modelSectionLabel = NSTextField(labelWithString: "モデル情報")
        modelSectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        modelSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modelSectionLabel)

        let modelVersionKeyLabel = NSTextField(labelWithString: "バージョン:")
        modelVersionKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modelVersionKeyLabel)

        modelVersionLabel.translatesAutoresizingMaskIntoConstraints = false
        modelVersionLabel.isSelectable = true
        addSubview(modelVersionLabel)

        let modelBuildKeyLabel = NSTextField(labelWithString: "ビルド日時:")
        modelBuildKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(modelBuildKeyLabel)

        modelBuildTimestampLabel.translatesAutoresizingMaskIntoConstraints = false
        modelBuildTimestampLabel.isSelectable = true
        addSubview(modelBuildTimestampLabel)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: aboveView.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            modelSectionLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            modelSectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            modelVersionKeyLabel.topAnchor.constraint(equalTo: modelSectionLabel.bottomAnchor, constant: 8),
            modelVersionKeyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            modelVersionKeyLabel.widthAnchor.constraint(equalToConstant: 80),

            modelVersionLabel.centerYAnchor.constraint(equalTo: modelVersionKeyLabel.centerYAnchor),
            modelVersionLabel.leadingAnchor.constraint(equalTo: modelVersionKeyLabel.trailingAnchor, constant: 8),

            modelBuildKeyLabel.topAnchor.constraint(equalTo: modelVersionKeyLabel.bottomAnchor, constant: 6),
            modelBuildKeyLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            modelBuildKeyLabel.widthAnchor.constraint(equalToConstant: 80),

            modelBuildTimestampLabel.centerYAnchor.constraint(equalTo: modelBuildKeyLabel.centerYAnchor),
            modelBuildTimestampLabel.leadingAnchor.constraint(
                equalTo: modelBuildKeyLabel.trailingAnchor, constant: 8)
        ])

        return modelBuildKeyLabel
    }

}

// MARK: - Actions

extension GeneralSettingsView {
    @objc private func punctuationStyleChanged(_ sender: NSPopUpButton) {
        if let style = PunctuationStyle(rawValue: sender.indexOfSelectedItem) {
            Settings.shared.punctuationStyle = style
        }
    }

    @objc private func showPredictiveCandidatesChanged(_ sender: NSButton) {
        Settings.shared.showPredictiveCandidates = sender.state == .on
    }

    @objc private func notifyOnSecureInputChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        Settings.shared.notifyOnSecureInput = enabled
        // 通知許可ダイアログはユーザーがオンにした瞬間（設定画面操作中）に出すのが自然
        if enabled {
            SecureInputNotifier.requestAuthorization()
        }
    }

    private func loadModelInfo() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let info = akazaClient.modelInfoSync()
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.modelVersionLabel.stringValue = info?.akazaDataVersion ?? "(不明)"
                self.modelBuildTimestampLabel.stringValue = info?.buildTimestamp ?? "(不明)"
            }
        }
    }
}
