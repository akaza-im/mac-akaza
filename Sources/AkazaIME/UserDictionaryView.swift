import Cocoa

class UserDictionaryView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let tableView = NSTableView()
    private var entries: [(yomi: String, surface: String)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        loadEntries()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        loadEntries()
    }

    private func setupUI() {
        let yomiColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("yomi"))
        yomiColumn.title = "読み"
        yomiColumn.width = 200
        tableView.addTableColumn(yomiColumn)

        let surfaceColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("surface"))
        surfaceColumn.title = "表記"
        surfaceColumn.width = 200
        tableView.addTableColumn(surfaceColumn)

        tableView.dataSource = self
        tableView.delegate = self

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        addSubview(scrollView)

        let addButton = NSButton(title: "追加...", target: self, action: #selector(addEntry(_:)))
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(addButton)

        let deleteButton = NSButton(title: "削除", target: self, action: #selector(deleteEntry(_:)))
        deleteButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(deleteButton)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            scrollView.bottomAnchor.constraint(equalTo: addButton.topAnchor, constant: -8),

            addButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            addButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),

            deleteButton.leadingAnchor.constraint(equalTo: addButton.trailingAnchor, constant: 8),
            deleteButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
    }

    private func loadEntries() {
        guard let dictEntries = akazaClient.userDictListSync() else { return }
        entries = dictEntries.flatMap { entry in
            entry.surfaces.map { surface in (yomi: entry.yomi, surface: surface) }
        }
        tableView.reloadData()
    }

    @objc private func addEntry(_ sender: Any?) {
        UserDictionaryView.showAddEntryDialog(prefillYomi: nil) { [weak self] in
            self?.loadEntries()
        }
    }

    static func showAddEntryDialog(prefillYomi: String?, completion: (() -> Void)? = nil) {
        let alert = NSAlert()
        alert.messageText = "ユーザー辞書に追加"
        alert.addButton(withTitle: "追加")
        alert.addButton(withTitle: "キャンセル")

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 60))

        let yomiLabel = NSTextField(labelWithString: "読み:")
        yomiLabel.frame = NSRect(x: 0, y: 34, width: 50, height: 22)
        container.addSubview(yomiLabel)

        let yomiField = NSTextField(frame: NSRect(x: 55, y: 34, width: 240, height: 22))
        if let yomi = prefillYomi {
            yomiField.stringValue = yomi
        }
        container.addSubview(yomiField)

        let surfaceLabel = NSTextField(labelWithString: "表記:")
        surfaceLabel.frame = NSRect(x: 0, y: 4, width: 50, height: 22)
        container.addSubview(surfaceLabel)

        let surfaceField = NSTextField(frame: NSRect(x: 55, y: 4, width: 240, height: 22))
        container.addSubview(surfaceField)

        yomiField.nextKeyView = surfaceField
        surfaceField.nextKeyView = yomiField

        alert.accessoryView = container
        alert.window.initialFirstResponder = prefillYomi != nil ? surfaceField : yomiField

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let yomi = yomiField.stringValue.trimmingCharacters(in: .whitespaces)
        let surface = surfaceField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !yomi.isEmpty, !surface.isEmpty else { return }

        _ = akazaClient.userDictAddSync(yomi: yomi, surface: surface)
        completion?()
    }

    @objc private func deleteEntry(_ sender: Any?) {
        let row = tableView.selectedRow
        guard row >= 0, row < entries.count else { return }

        let entry = entries[row]
        _ = akazaClient.userDictDeleteSync(yomi: entry.yomi, surface: entry.surface)
        loadEntries()
    }

    // MARK: - NSTableViewDataSource

    func numberOfRows(in tableView: NSTableView) -> Int {
        entries.count
    }

    // MARK: - NSTableViewDelegate

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < entries.count else { return nil }

        let entry = entries[row]
        let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("")
        let text: String
        switch identifier.rawValue {
        case "yomi":
            text = entry.yomi
        case "surface":
            text = entry.surface
        default:
            text = ""
        }

        let cellView = NSTableCellView()
        let textField = NSTextField(labelWithString: text)
        textField.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(textField)
        cellView.textField = textField
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cellView.leadingAnchor, constant: 2),
            textField.centerYAnchor.constraint(equalTo: cellView.centerYAnchor)
        ])
        return cellView
    }
}
