import Cocoa
import InputMethodKit

struct AlternativeSelectionState {
    let conversionSession: ConversionSession
    let alternatives: [String]
    var selectedIndex: Int = 0
}

// MARK: - Alternative selection (0 key during conversion)
extension AkazaInputController {
    func enterAlternativeSelection(client: any IMKTextInput) -> Bool {
        guard case .converting(let session) = inputState else { return false }
        guard let yomi = session.focusedCandidates.first?.yomi, !yomi.isEmpty else { return true }

        let alternatives = buildAlternatives(yomi: yomi)
        guard !alternatives.isEmpty else { return true }

        alternativeSelectionState = AlternativeSelectionState(
            conversionSession: session,
            alternatives: alternatives
        )
        updateAlternativeMarkedText(client: client)
        showAlternativeCandidateWindow(client: client)
        return true
    }

    // Returns nil when not in alternative selection mode, Bool otherwise.
    func handleAlternativeSelection(event: NSEvent, keyCode: UInt16, client: any IMKTextInput) -> Bool? {
        guard alternativeSelectionState != nil else { return nil }

        let isShiftPressed = event.modifierFlags.contains(.shift)

        switch keyCode {
        case 49: // Space
            moveAlternativeSelection(by: isShiftPressed ? -1 : 1, client: client)
            return true
        case 125: // Down
            moveAlternativeSelection(by: 1, client: client)
            return true
        case 126: // Up
            moveAlternativeSelection(by: -1, client: client)
            return true
        case 36: // Enter
            commitSelectedAlternative(client: client)
            return true
        case 53, 29: // Escape or 0 — cancel
            cancelAlternativeSelection(client: client)
            return true
        default:
            if let chars = event.characters, let char = chars.first,
               let number = Int(String(char)), (1...9).contains(number) {
                let index = number - 1
                if index < alternativeSelectionState!.alternatives.count {
                    selectAlternativeAt(index, client: client)
                }
                return true
            }
            cancelAlternativeSelection(client: client)
            return handleConvertingState(event: event, keyCode: keyCode, client: client)
        }
    }

    private func moveAlternativeSelection(by offset: Int, client: any IMKTextInput) {
        guard var state = alternativeSelectionState else { return }
        let count = state.alternatives.count
        state.selectedIndex = (state.selectedIndex + offset + count) % count
        alternativeSelectionState = state
        updateAlternativeMarkedText(client: client)
        showAlternativeCandidateWindow(client: client)
    }

    private func selectAlternativeAt(_ index: Int, client: any IMKTextInput) {
        guard var state = alternativeSelectionState, index < state.alternatives.count else { return }
        state.selectedIndex = index
        alternativeSelectionState = state
        commitSelectedAlternative(client: client)
    }

    func commitSelectedAlternative(client: any IMKTextInput) {
        guard let state = alternativeSelectionState else { return }
        let alternative = state.alternatives[state.selectedIndex]
        let session = state.conversionSession

        let text = session.clauses.enumerated().compactMap { idx, candidates -> String? in
            guard !candidates.isEmpty else { return nil }
            return idx == session.focusedClauseIndex
                ? alternative
                : candidates[session.selectedCandidateIndices[idx]].surface
        }.joined()

        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        alternativeSelectionState = nil
        resetToComposing()
    }

    func cancelAlternativeSelection(client: any IMKTextInput) {
        guard let state = alternativeSelectionState else { return }
        alternativeSelectionState = nil
        inputState = .converting(state.conversionSession)
        updateConvertingMarkedText(client: client)
        updateConversionCandidateWindow(client: client, trigger: .conversionNavigation)
    }

    func updateAlternativeMarkedText(client: any IMKTextInput) {
        guard let state = alternativeSelectionState else { return }
        let session = state.conversionSession
        let alternative = state.alternatives[state.selectedIndex]

        let attributed = NSMutableAttributedString()
        for (clauseIndex, candidates) in session.clauses.enumerated() {
            guard !candidates.isEmpty else { continue }
            let isFocused = clauseIndex == session.focusedClauseIndex
            let surface = isFocused ? alternative : candidates[session.selectedCandidateIndices[clauseIndex]].surface
            let underlineStyle: NSUnderlineStyle = isFocused ? .thick : .single
            let attrs: [NSAttributedString.Key: Any] = [
                .underlineStyle: underlineStyle.rawValue,
                .markedClauseSegment: clauseIndex
            ]
            attributed.append(NSAttributedString(string: surface, attributes: attrs))
        }

        let fullLength = attributed.length
        client.setMarkedText(
            attributed,
            selectionRange: NSRange(location: fullLength, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    func showAlternativeCandidateWindow(client: any IMKTextInput) {
        guard let state = alternativeSelectionState else { return }
        var lineHeightRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)
        Self.candidateWindow.showAlternatives(
            state.alternatives,
            selectedIndex: state.selectedIndex,
            cursorRect: lineHeightRect
        )
    }

    private func buildAlternatives(yomi: String) -> [String] {
        var result: [String] = [yomi]
        let katakana = yomi.toKatakana()
        if katakana != yomi { result.append(katakana) }
        let halfKatakana = yomi.toHalfWidthKatakana()
        if halfKatakana != katakana { result.append(halfKatakana) }
        return result
    }
}
