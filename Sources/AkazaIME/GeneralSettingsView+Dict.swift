import Cocoa

// MARK: - 辞書セクション（システム辞書・ユーザー辞書）

extension GeneralSettingsView {
    func setupDictViews(below aboveView: NSView) {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        let dictSectionLabel = NSTextField(labelWithString: "辞書")
        dictSectionLabel.font = NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize)
        dictSectionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(dictSectionLabel)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: aboveView.bottomAnchor, constant: 16),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),

            dictSectionLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 8),
            dictSectionLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        ])

        let lastSystemView = setupSystemDictSection(below: dictSectionLabel)
        setupUserDictSection(below: lastSystemView)
    }

    private func setupSystemDictSection(below aboveView: NSView) -> NSView {
        let sysLabel = NSTextField(labelWithString: "システム辞書")
        sysLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        sysLabel.textColor = .secondaryLabelColor
        sysLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(sysLabel)

        NSLayoutConstraint.activate([
            sysLabel.topAnchor.constraint(equalTo: aboveView.bottomAnchor, constant: 8),
            sysLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20)
        ])

        var lastView: NSView = sysLabel
        dictRowUpdaters = []

        for config in predefinedDownloadableDicts {
            let (rowView, update) = makeDownloadableDictRow(config: config)
            dictRowUpdaters.append(update)

            NSLayoutConstraint.activate([
                rowView.topAnchor.constraint(equalTo: lastView.bottomAnchor, constant: 6),
                rowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
                rowView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20)
            ])
            lastView = rowView
        }

        return lastView
    }

    private func makeDownloadableDictRow(
        config: DownloadableDictConfig
    ) -> (view: NSView, update: () -> Void) {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        let nameLabel = NSTextField(labelWithString: config.displayName)
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        let statusLabel = NSTextField(labelWithString: "確認中...")
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(statusLabel)

        let actionButton = NSButton(title: "", target: nil, action: nil)
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(actionButton)

        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nameLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            nameLabel.widthAnchor.constraint(equalToConstant: 160),

            statusLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 12),
            statusLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            statusLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 80),

            actionButton.leadingAnchor.constraint(equalTo: statusLabel.trailingAnchor, constant: 8),
            actionButton.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            actionButton.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            container.heightAnchor.constraint(equalToConstant: 24)
        ])

        let updateStatus = { [weak statusLabel, weak actionButton] in
            guard let statusLabel = statusLabel, let actionButton = actionButton else { return }
            let downloaded = akazaServerProcess.isDictDownloaded(config)
            if downloaded {
                statusLabel.stringValue = "読み込み済み"
                statusLabel.textColor = .systemGreen
                actionButton.title = "削除"
                actionButton.action = #selector(GeneralSettingsView.deleteDictButtonClicked(_:))
            } else {
                statusLabel.stringValue = "未ダウンロード"
                statusLabel.textColor = .systemOrange
                actionButton.title = "ダウンロード"
                actionButton.action = #selector(GeneralSettingsView.downloadDictButtonClicked(_:))
            }
        }

        actionButton.target = self
        actionButton.tag = predefinedDownloadableDicts.firstIndex(where: { $0.id == config.id }) ?? 0
        updateStatus()

        return (container, updateStatus)
    }

    private func setupUserDictSection(below aboveView: NSView) {
        let userLabel = NSTextField(labelWithString: "ユーザー辞書")
        userLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        userLabel.textColor = .secondaryLabelColor
        userLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(userLabel)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("DictPath"))
        column.title = "辞書パス"
        column.resizingMask = .autoresizingMask
        userDictTableView.addTableColumn(column)
        userDictTableView.headerView = nil
        userDictTableView.dataSource = self
        userDictTableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.documentView = userDictTableView
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        addDictButton.target = self
        addDictButton.action = #selector(addDictButtonClicked(_:))
        addDictButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addDictButton)

        removeDictButton.target = self
        removeDictButton.action = #selector(removeDictButtonClicked(_:))
        removeDictButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeDictButton)

        NSLayoutConstraint.activate([
            userLabel.topAnchor.constraint(equalTo: aboveView.bottomAnchor, constant: 12),
            userLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            scrollView.topAnchor.constraint(equalTo: userLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scrollView.heightAnchor.constraint(equalToConstant: 100),

            addDictButton.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            addDictButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),

            removeDictButton.centerYAnchor.constraint(equalTo: addDictButton.centerYAnchor),
            removeDictButton.leadingAnchor.constraint(equalTo: addDictButton.trailingAnchor, constant: 8)
        ])
    }
}

// MARK: - 辞書セクションのアクション

extension GeneralSettingsView {
    @objc fileprivate func downloadDictButtonClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < predefinedDownloadableDicts.count else { return }
        let config = predefinedDownloadableDicts[index]

        sender.isEnabled = false
        akazaServerProcess.downloadDict(config) { _ in
            DispatchQueue.main.async { [weak self] in
                sender.isEnabled = true
                self?.dictRowUpdaters[index]()
                akazaServerProcess.restart()
            }
        }
    }

    @objc fileprivate func deleteDictButtonClicked(_ sender: NSButton) {
        let index = sender.tag
        guard index < predefinedDownloadableDicts.count else { return }
        let config = predefinedDownloadableDicts[index]

        do {
            try akazaServerProcess.deleteDict(config)
        } catch {
            NSLog("AkazaIME: failed to delete \(config.fileName): \(error)")
        }
        dictRowUpdaters[index]()
        akazaServerProcess.restart()
    }

    @objc fileprivate func addDictButtonClicked(_ sender: NSButton) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            DispatchQueue.main.async {
                self?.selectEncoding(for: url)
            }
        }
    }

    private func selectEncoding(for url: URL) {
        let alert = NSAlert()
        alert.messageText = "エンコーディングを選択"
        alert.informativeText = url.lastPathComponent
        alert.addButton(withTitle: "追加")
        alert.addButton(withTitle: "キャンセル")

        let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 150, height: 24))
        popup.addItems(withTitles: ["UTF-8", "EUC-JP"])
        alert.accessoryView = popup

        if alert.runModal() == .alertFirstButtonReturn {
            let encoding = popup.indexOfSelectedItem == 1 ? "eucjp" : "utf8"
            Settings.shared.additionalDictPaths.append("\(url.path):\(encoding)")
            userDictTableView.reloadData()
            akazaServerProcess.restart()
        }
    }

    @objc fileprivate func removeDictButtonClicked(_ sender: NSButton) {
        let row = userDictTableView.selectedRow
        guard row >= 0 else { return }
        Settings.shared.additionalDictPaths.remove(at: row)
        userDictTableView.reloadData()
        akazaServerProcess.restart()
    }
}
