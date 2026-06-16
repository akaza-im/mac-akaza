import Cocoa
import InputMethodKit

// MARK: - Suggesting state handlers
extension AkazaInputController {
    func handleSuggestingState(event: NSEvent, keyCode: UInt16, client: any IMKTextInput) -> Bool {
        let isShiftPressed = event.modifierFlags.contains(.shift)

        switch keyCode {
        case 48, 49: // Tab or Space
            return handleTabOrSpaceInSuggesting(keyCode: keyCode, isShiftPressed: isShiftPressed, client: client)
        case 36: // Enter
            return handleEnterInSuggesting(client: client)
        case 53: // Escape
            return handleEscapeInSuggesting(client: client)
        case 51: // Backspace
            return handleBackspaceInSuggesting(client: client)
        case 125: // Down arrow
            return handleNextPathInSuggesting(client: client)
        case 126: // Up arrow
            return handlePreviousPathInSuggesting(client: client)
        case 123, 124: // Left, Right arrow: consume to avoid tofu input
            return true
        default:
            return handleCharacterInSuggesting(event: event, client: client)
        }
    }

    private func handleTabOrSpaceInSuggesting(
        keyCode: UInt16, isShiftPressed: Bool, client: any IMKTextInput
    ) -> Bool {
        if keyCode == 49 && !isShiftPressed {
            return handleSpaceInSuggesting(client: client)
        }
        return isShiftPressed
            ? handlePreviousPathInSuggesting(client: client)
            : handleNextPathInSuggesting(client: client)
    }

    private func handleNextPathInSuggesting(client: any IMKTextInput) -> Bool {
        guard case .suggesting(var session) = inputState else { return false }
        session.nextPath()
        inputState = .suggesting(session)
        updateSuggestingMarkedText(client: client)
        showSuggestCandidateWindow(client: client)
        return true
    }

    private func handlePreviousPathInSuggesting(client: any IMKTextInput) -> Bool {
        guard case .suggesting(var session) = inputState else { return false }
        session.previousPath()
        inputState = .suggesting(session)
        updateSuggestingMarkedText(client: client)
        showSuggestCandidateWindow(client: client)
        return true
    }

    private func handleSpaceInSuggesting(client: any IMKTextInput) -> Bool {
        guard case .suggesting(let session) = inputState else { return false }
        let conversionSession = session.toConversionSession()
        inputState = .converting(conversionSession)
        composedHiragana = ""
        updateConvertingMarkedText(client: client)
        updateConversionCandidateWindow(client: client, trigger: .conversionStarted)
        return true
    }

    private func handleEnterInSuggesting(client: any IMKTextInput) -> Bool {
        commitSuggestingText(client: client)
        return true
    }

    private func handleEscapeInSuggesting(client: any IMKTextInput) -> Bool {
        guard case .suggesting(let session) = inputState else { return false }
        composedHiragana = session.originalHiragana
        inputState = .composing
        Self.candidateWindow.hide()
        updateComposingMarkedText(client: client)
        return true
    }

    private func handleBackspaceInSuggesting(client: any IMKTextInput) -> Bool {
        guard case .suggesting(let session) = inputState else { return false }
        composedHiragana = session.originalHiragana
        inputState = .composing
        // 候補ウィンドウは隠さない（新しいサジェストで更新される）
        return handleBackspaceInComposing(client: client)
    }

    private func handleCharacterInSuggesting(event: NSEvent, client: any IMKTextInput) -> Bool {
        guard case .suggesting(let session) = inputState else { return false }
        composedHiragana = session.originalHiragana
        inputState = .composing
        // 候補ウィンドウは隠さない（新しいサジェストで更新される）
        return handleCharacterInput(event: event, client: client)
    }

    // MARK: - Commit

    func commitSuggestingText(client: any IMKTextInput) {
        guard case .suggesting(let session) = inputState else { return }
        let text = session.originalHiragana
        diagInsertText(text, client: client, "commit-suggesting")
        resetToComposing()
    }

    // MARK: - Display

    func updateSuggestingMarkedText(client: any IMKTextInput) {
        // preedit はひらがなのまま（composing と同じ表示）
        updateComposingMarkedText(client: client)
    }

    func showSuggestCandidateWindow(client: any IMKTextInput) {
        guard case .suggesting(let session) = inputState else { return }
        guard candidateWindowVisibilityPolicy.shouldShowWindow(for: .composingSuggestion) else {
            Self.candidateWindow.hide()
            return
        }

        let suggestions = session.displayTexts
        guard !suggestions.isEmpty else {
            Self.candidateWindow.hide()
            return
        }

        var lineHeightRect = NSRect.zero
        client.attributes(forCharacterIndex: 0, lineHeightRectangle: &lineHeightRect)

        Self.candidateWindow.showSuggestions(
            suggestions: suggestions,
            selectedIndex: session.selectedDisplayIndex,
            cursorRect: lineHeightRect
        )
    }
}

// MARK: - Suggest scheduling

extension AkazaInputController {
    func scheduleSuggest(client: any IMKTextInput) {
        cancelPendingSuggest()

        // 直接入力モード中はサジェストを抑制する
        guard !isDirectInputMode else {
            Self.candidateWindow.hide()
            return
        }

        let yomi = composedHiragana
        guard !yomi.isEmpty else {
            latestSuggestYomi = nil
            Self.candidateWindow.hide()
            return
        }
        guard yomi != latestSuggestYomi else { return }

        latestSuggestYomi = yomi
        let requestID = akazaClient.convertKBestAsync(
            yomi: yomi,
            maxPaths: Settings.shared.suggestMaxPaths
        ) { [weak self] paths in
            guard let self = self else { return }
            guard case .composing = self.inputState else { return }
            guard let paths = paths, !paths.isEmpty else { return }
            guard self.composedHiragana == yomi else { return }

            let session = SuggestSession(originalHiragana: yomi, paths: paths)
            self.inputState = .suggesting(session)
            self.updateSuggestingMarkedText(client: client)
            self.showSuggestCandidateWindow(client: client)
        }
        pendingSuggestRequestID = requestID
    }

    func cancelPendingSuggest() {
        if let id = pendingSuggestRequestID {
            akazaClient.cancelRequest(id: id)
            pendingSuggestRequestID = nil
        }
    }
}
