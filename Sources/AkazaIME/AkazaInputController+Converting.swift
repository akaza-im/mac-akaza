import Cocoa
import InputMethodKit

// MARK: - Converting state handlers
extension AkazaInputController {
    func handleConvertingState(event: NSEvent, keyCode: UInt16, client: any IMKTextInput) -> Bool {
        let isShiftPressed = event.modifierFlags.contains(.shift)

        switch keyCode {
        case 49: // Space
            if isShiftPressed {
                return handlePreviousCandidateInConverting(client: client)
            }
            return handleNextCandidateInConverting(client: client)
        case 125: // Down arrow
            return handleNextCandidateInConverting(client: client)
        case 126: // Up arrow
            return handlePreviousCandidateInConverting(client: client)
        case 123, 124: // Left, Right arrow
            return handleArrowKeyInConverting(keyCode: keyCode, isShiftPressed: isShiftPressed, client: client)
        case 36: // Enter
            return handleEnterInConverting(client: client)
        case 53: // Escape
            return handleEscapeInConverting(client: client)
        case 51: // Backspace
            return handleBackspaceInConverting(client: client)
        default:
            return handleDefaultKeyInConverting(event: event, client: client)
        }
    }

    private func handleArrowKeyInConverting(keyCode: UInt16, isShiftPressed: Bool, client: any IMKTextInput) -> Bool {
        switch keyCode {
        case 123: // Left arrow
            return isShiftPressed ? handleShrinkClauseLeft(client: client) : handlePreviousClauseInConverting(client: client)
        case 124: // Right arrow
            return isShiftPressed ? handleExtendClauseRight(client: client) : handleNextClauseInConverting(client: client)
        default:
            return false
        }
    }

    private func handleDefaultKeyInConverting(event: NSEvent, client: any IMKTextInput) -> Bool {
        if let characters = event.characters, let char = characters.first,
           let number = Int(String(char)), (1...9).contains(number) {
            return handleNumberKeyInConverting(number: number, client: client)
        }

        if let characters = event.characters, let first = characters.first,
           !first.isNewline && !first.isWhitespace && (first.isLetter || first.isNumber || first.isPunctuation || first.isSymbol) {
            commitConvertingText(client: client)
            return handleCharacterInput(event: event, client: client)
        }

        return true
    }

    private func handleNextCandidateInConverting(client: any IMKTextInput) -> Bool {
        guard case .converting(var session) = inputState else { return false }
        session.nextCandidate()
        inputState = .converting(session)
        updateConvertingMarkedText(client: client)
        updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
        return true
    }

    private func handlePreviousCandidateInConverting(client: any IMKTextInput) -> Bool {
        guard case .converting(var session) = inputState else { return false }
        session.previousCandidate()
        inputState = .converting(session)
        updateConvertingMarkedText(client: client)
        updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
        return true
    }

    private func handlePreviousClauseInConverting(client: any IMKTextInput) -> Bool {
        guard case .converting(var session) = inputState else { return false }
        session.focusPreviousClause()
        inputState = .converting(session)
        updateConvertingMarkedText(client: client)
        updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
        return true
    }

    private func handleNextClauseInConverting(client: any IMKTextInput) -> Bool {
        guard case .converting(var session) = inputState else { return false }
        session.focusNextClause()
        inputState = .converting(session)
        updateConvertingMarkedText(client: client)
        updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
        return true
    }

    private func handleEnterInConverting(client: any IMKTextInput) -> Bool {
        commitConvertingText(client: client)
        return true
    }

    private func handleEscapeInConverting(client: any IMKTextInput) -> Bool {
        guard case .converting(let session) = inputState else { return false }
        composedHiragana = session.originalHiragana
        inputState = .composing
        Self.candidateWindow.hide()
        updateComposingMarkedText(client: client)
        return true
    }

    private func handleBackspaceInConverting(client: any IMKTextInput) -> Bool {
        guard case .converting(let session) = inputState else { return false }
        composedHiragana = session.originalHiragana
        inputState = .composing
        inputHistory.removeAll()
        Self.candidateWindow.hide()
        return handleBackspaceInComposing(client: client)
    }

    private func handleNumberKeyInConverting(number: Int, client: any IMKTextInput) -> Bool {
        guard case .converting(var session) = inputState else { return false }
        let pageSize = 9
        let currentPage = session.focusedDisplaySelectedIndex / pageSize
        let displayIndex = currentPage * pageSize + (number - 1)
        if session.selectDisplayedCandidate(at: displayIndex) {
            inputState = .converting(session)
            commitConvertingText(client: client)
        }
        return true
    }

    private func handleExtendClauseRight(client: any IMKTextInput) -> Bool {
        guard case .converting(let session) = inputState else { return false }
        guard let (yomi, forceRanges) = session.forceRangesForExtendRight() else { return true }

        let focusedIndex = session.focusedClauseIndex
        let originalHiragana = session.originalHiragana

        akazaClient.convertAsync(yomi: yomi, forceRanges: forceRanges) { [weak self] result in
            guard let self = self else { return }
            guard case .converting(let current) = self.inputState,
                  current.originalHiragana == originalHiragana else { return }
            guard let result = result, !result.isEmpty else { return }

            var newSession = ConversionSession(originalHiragana: yomi, clauses: result)
            newSession.focusedClauseIndex = min(focusedIndex, newSession.clauses.count - 1)
            self.inputState = .converting(newSession)
            self.updateConvertingMarkedText(client: client)
            self.updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
        }
        return true
    }

    private func handleShrinkClauseLeft(client: any IMKTextInput) -> Bool {
        guard case .converting(let session) = inputState else { return false }
        guard let (yomi, forceRanges) = session.forceRangesForExtendLeft() else { return true }

        let focusedIndex = session.focusedClauseIndex
        let originalHiragana = session.originalHiragana

        akazaClient.convertAsync(yomi: yomi, forceRanges: forceRanges) { [weak self] result in
            guard let self = self else { return }
            guard case .converting(let current) = self.inputState,
                  current.originalHiragana == originalHiragana else { return }
            guard let result = result, !result.isEmpty else { return }

            var newSession = ConversionSession(originalHiragana: yomi, clauses: result)
            newSession.focusedClauseIndex = min(focusedIndex, newSession.clauses.count - 1)
            self.inputState = .converting(newSession)
            self.updateConvertingMarkedText(client: client)
            self.updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
        }
        return true
    }
}

// MARK: - Marked text display
extension AkazaInputController {
    func updateConversionCandidateWindow(client: any IMKTextInput, trigger: CandidateWindowTrigger) {
        if candidateWindowVisibilityPolicy.shouldShowWindow(for: trigger) {
            showCandidateWindow(client: client)
        } else {
            Self.candidateWindow.hide()
        }
    }

    func updateComposingMarkedText(client: any IMKTextInput) {
        let preedit = functionKeyState?.displayText ?? (composedHiragana + romajiConverter.pendingRomaji)
        if preedit.isEmpty {
            diagSetMarkedText(
                NSAttributedString(string: ""),
                selectionRange: NSRange(location: 0, length: 0),
                client: client,
                "composing-empty"
            )
        } else {
            let attrs: [NSAttributedString.Key: Any] = [
                .underlineStyle: NSUnderlineStyle.single.rawValue
            ]
            let attributed = NSAttributedString(string: preedit, attributes: attrs)
            let length = (preedit as NSString).length
            diagSetMarkedText(
                attributed,
                selectionRange: NSRange(location: length, length: 0),
                client: client,
                "composing"
            )
        }
    }

    func updateConvertingMarkedText(client: any IMKTextInput) {
        guard case .converting(let session) = inputState else { return }

        let attributed = NSMutableAttributedString()

        for (clauseIndex, candidates) in session.clauses.enumerated() {
            guard !candidates.isEmpty else { continue }
            let selectedIndex = session.selectedCandidateIndices[clauseIndex]
            let surface = candidates[selectedIndex].surface
            let isFocused = clauseIndex == session.focusedClauseIndex

            let underlineStyle: NSUnderlineStyle = isFocused ? .thick : .single
            let attrs: [NSAttributedString.Key: Any] = [
                .underlineStyle: underlineStyle.rawValue,
                .markedClauseSegment: clauseIndex
            ]
            let segment = NSAttributedString(string: surface, attributes: attrs)
            attributed.append(segment)
        }

        let fullLength = attributed.length
        diagSetMarkedText(
            attributed,
            selectionRange: NSRange(location: fullLength, length: 0),
            client: client,
            "converting"
        )
    }

    func showCandidateWindow(client: any IMKTextInput) {
        guard case .converting(let session) = inputState else { return }

        let candidates = session.focusedDisplayCandidates
        guard !candidates.isEmpty else {
            Self.candidateWindow.hide()
            return
        }

        var lineHeightRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)

        Self.candidateWindow.show(
            candidates: candidates,
            selectedIndex: session.focusedDisplaySelectedIndex,
            cursorRect: lineHeightRect
        )
    }
}
