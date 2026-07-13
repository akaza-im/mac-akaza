import Cocoa

class CandidateWindowController {
    private let panel: NSPanel
    private let stackView: NSStackView
    private let maxDisplayCount = 9
    private var candidateLabels: [NSTextField] = []

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: true
        )
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.ignoresMouseEvents = true

        stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 2
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView?.addSubview(stackView)
        if let contentView = panel.contentView {
            NSLayoutConstraint.activate([
                stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
                stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                stackView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
            ])
        }
    }

    func show(candidates: [ConvertCandidate], selectedIndex: Int, cursorRect: NSRect) {
        showSurfaces(candidates.map { $0.surface }, selectedIndex: selectedIndex, cursorRect: cursorRect, stablePosition: false)
    }

    private func clearLabels() {
        for label in candidateLabels {
            stackView.removeArrangedSubview(label)
            label.removeFromSuperview()
        }
        candidateLabels.removeAll()
    }

    private func addCandidateLabels(surfaces: [String], pageStart: Int, pageEnd: Int, selectedIndex: Int) {
        for idx in pageStart..<pageEnd {
            let displayNumber = idx - pageStart + 1
            let label = NSTextField(labelWithString: "\(displayNumber). \(surfaces[idx])")
            label.font = NSFont.systemFont(ofSize: 14)
            label.translatesAutoresizingMaskIntoConstraints = false

            if idx == selectedIndex {
                label.backgroundColor = NSColor.selectedContentBackgroundColor
                label.textColor = NSColor.white
                label.drawsBackground = true
            } else {
                label.backgroundColor = .clear
                label.textColor = NSColor.labelColor
                label.drawsBackground = false
            }

            stackView.addArrangedSubview(label)
            candidateLabels.append(label)
        }
    }

    private func showSurfaces(_ surfaces: [String], selectedIndex: Int, cursorRect: NSRect, stablePosition: Bool) {
        clearLabels()

        guard !surfaces.isEmpty else {
            hide()
            return
        }

        let pageSize = maxDisplayCount
        let currentPage = selectedIndex / pageSize
        let pageStart = currentPage * pageSize
        let pageEnd = min(pageStart + pageSize, surfaces.count)
        let totalPages = (surfaces.count + pageSize - 1) / pageSize

        addCandidateLabels(surfaces: surfaces, pageStart: pageStart, pageEnd: pageEnd, selectedIndex: selectedIndex)

        if totalPages > 1 {
            addPageIndicator(currentPage: currentPage, totalPages: totalPages)
        }

        positionPanel(cursorRect: cursorRect, stablePosition: stablePosition)
    }

    private func addPageIndicator(currentPage: Int, totalPages: Int) {
        let pageIndicator = NSTextField(labelWithString: "[\(currentPage + 1)/\(totalPages)]")
        pageIndicator.font = NSFont.systemFont(ofSize: 12)
        pageIndicator.textColor = NSColor.secondaryLabelColor
        pageIndicator.alignment = .center
        pageIndicator.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(pageIndicator)
        candidateLabels.append(pageIndicator)
    }

    private func positionPanel(cursorRect: NSRect, stablePosition: Bool = false) {
        stackView.layoutSubtreeIfNeeded()
        let contentSize = stackView.fittingSize
        let panelWidth = max(contentSize.width + 16, 120)
        let panelHeight = contentSize.height + 8

        // cursorRect が zero の場合のフォールバック
        guard cursorRect != .zero else {
            panel.setFrame(NSRect(x: 100, y: 100, width: panelWidth, height: panelHeight), display: true)
            panel.orderFront(nil)
            return
        }

        // 上下判定は最大高さで行い、候補数が変わっても位置が安定するようにする
        let heightForDecision: CGFloat
        if stablePosition {
            let lineHeight: CGFloat = 18
            heightForDecision = CGFloat(maxDisplayCount) * lineHeight + 8
        } else {
            heightForDecision = panelHeight
        }

        let showAbove: Bool
        if let screen = NSScreen.main {
            showAbove = cursorRect.origin.y - heightForDecision < screen.visibleFrame.origin.y
        } else {
            showAbove = false
        }

        let originY: CGFloat
        if showAbove {
            // カーソルの上に表示（下端をカーソル上端に合わせる）
            originY = cursorRect.origin.y + cursorRect.size.height
        } else {
            // カーソルの下に表示（上端をカーソル下端に合わせる）
            originY = cursorRect.origin.y - panelHeight
        }

        panel.setFrame(NSRect(x: cursorRect.origin.x, y: originY, width: panelWidth, height: panelHeight), display: true)
        panel.orderFront(nil)
    }

    func showSuggestions(suggestions: [String], selectedIndex: Int, cursorRect: NSRect) {
        showSurfaces(suggestions, selectedIndex: selectedIndex, cursorRect: cursorRect, stablePosition: true)
    }

    func showAlternatives(_ alternatives: [String], selectedIndex: Int, cursorRect: NSRect) {
        showSurfaces(alternatives, selectedIndex: selectedIndex, cursorRect: cursorRect, stablePosition: false)
    }

    func hide() {
        panel.orderOut(nil)
    }
}
