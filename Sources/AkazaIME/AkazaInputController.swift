import Cocoa
import InputMethodKit

extension Notification.Name {
    static let romkanTableDidChange = Notification.Name("AkazaIMERomkanTableDidChange")
}

struct ComposingSnapshot {
    let composedHiragana: String
    let romajiBuffer: String
    let rawRomajiInput: String
}

@objc(AkazaInputController)
class AkazaInputController: IMKInputController {
    var composedHiragana: String = ""
    var rawRomajiInput: String = ""
    let romajiConverter = RomajiConverter(tableName: Settings.shared.romkanTable)
    var inputState: InputState = .composing
    static let candidateWindow = CandidateWindowController()
    var inputHistory: [ComposingSnapshot] = []
    var functionKeyState: FunctionKeyState?

    // [diag] コントローラ生成/活性化のチャーン追跡用の連番ID。原因特定後に削除する一時計測。
    private static var diagCounter = 0
    let diagID: Int = {
        AkazaInputController.diagCounter += 1
        return AkazaInputController.diagCounter
    }()

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        super.init(server: server, delegate: delegate, client: inputClient)
        NSLog("AkazaIME[diag]: controller init id=\(diagID) \(AkazaInputController.diagClientDescription(inputClient))")
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRomkanTableDidChange),
            name: .romkanTableDidChange,
            object: nil
        )
    }

    deinit {
        NSLog("AkazaIME[diag]: controller deinit id=\(diagID)")
        NotificationCenter.default.removeObserver(self, name: .romkanTableDidChange, object: nil)
    }

    @objc private func handleRomkanTableDidChange() {
        resetToComposing()
        romajiConverter.reload(tableName: Settings.shared.romkanTable)
    }

    var pendingSuggestRequestID: Int?
    var latestSuggestYomi: String?

    var candidateWindowVisibilityPolicy: CandidateWindowVisibilityPolicy {
        CandidateWindowVisibilityPolicy(
            showPredictiveCandidates: Settings.shared.showPredictiveCandidates
        )
    }

    // 大文字 ASCII を入力したときに true になる直接入力モード。
    // このモードでは後続の printable ASCII もローマ字変換せず preedit に積み、
    // スペースで変換せずそのままコミットする（例: "Java" → "Java"）。
    var isDirectInputMode = false

    var hasPreedit: Bool {
        if functionKeyState != nil { return true }
        switch inputState {
        case .composing:
            return !composedHiragana.isEmpty || !romajiConverter.pendingRomaji.isEmpty
        case .suggesting:
            return true
        case .converting:
            return true
        }
    }

    // MARK: - Main event handler

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event = event, event.type == .keyDown else { return false }
        guard let client = sender as? (any IMKTextInput) else { return false }

        let keyCode = event.keyCode
        // [diag] 往路の生存確認のみ。キー内容はキーロガー化を避けるため記録しない。
        NSLog("AkazaIME[diag]: handle id=\(diagID) \(AkazaInputController.diagClientDescription(sender))")

        if isJISKanaKey(keyCode) { return true }

        if isBackspaceEvent(event, keyCode: keyCode) {
            return handleBackspaceEvent(event: event, client: client)
        }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let functionKeyCode = resolveFunctionKeyCode(keyCode: keyCode, flags: flags), hasPreedit {
            return handleFunctionKeyFromAnyState(keyCode: functionKeyCode, client: client)
        }
        if Self.isFunctionKey(keyCode) { return false }
        return handleNonFunctionKey(flags: flags, event: event, keyCode: keyCode, client: client)
    }

    // MARK: - Composing state

    private func handleComposingState(event: NSEvent, keyCode: UInt16, client: any IMKTextInput) -> Bool {
        if functionKeyState != nil {
            if keyCode == 53 { return handleEscapeInFunctionKey(client: client) } // Escape
            commitFunctionKeyState(client: client)
            if keyCode == 36 { return true } // Enter
        }

        switch keyCode {
        case 49: // Space
            return handleSpaceInComposing(client: client)
        case 36: // Enter
            return handleEnterInComposing(client: client)
        case 53: // Escape
            return handleEscapeInComposing(client: client)
        case 51: // Backspace
            return handleBackspaceInComposing(client: client)
        case 48: // Tab - let system handle focus navigation
            return false
        case 123, 124, 125, 126: // Arrow keys (Left, Right, Down, Up)
            // If we have preedit, consume the arrow key without doing anything
            // If no preedit, let the system handle it (return false)
            return hasPreedit
        default:
            return handleCharacterInput(event: event, client: client)
        }
    }

    private func handleSpaceInComposing(client: any IMKTextInput) -> Bool {
        guard hasPreedit else { return false }

        var text = composedHiragana
        if let flushed = romajiConverter.flush() {
            text += flushed
        }
        guard !text.isEmpty else { return false }

        // 直接入力モードではかな変換せずそのままコミット（例: "Java" → "Java"）
        if isDirectInputMode {
            diagInsertText(text, client: client, "space-direct")
            composedHiragana = ""
            isDirectInputMode = false
            clearInputHistory()
            Self.candidateWindow.hide()
            return true
        }

        // 変換結果が返るまでひらがなのままマークアップして表示
        composedHiragana = text
        clearInputHistory()
        updateComposingMarkedText(client: client)
        Self.candidateWindow.hide()

        cancelPendingSuggest()
        akazaClient.convertAsync(yomi: text) { [weak self] result in
            // [diag] 変換応答が返ったのに反映されず破棄される "サイレントドロップ" を検出する。
            guard let self = self else { AkazaInputController.diagConvertDroppedNoSelf(); return }
            // 変換待ち中に別のキーが押されて状態が変わった場合は無視
            guard case .composing = self.inputState else { self.diagConvertDropped("state changed"); return }
            guard self.composedHiragana == text else { self.diagConvertDropped("composedHiragana changed"); return }
            guard let result = result, !result.isEmpty else { self.diagConvertDropped("empty/nil result"); return }

            let session = ConversionSession(originalHiragana: text, clauses: result)
            self.inputState = .converting(session)
            self.composedHiragana = ""
            self.updateConvertingMarkedText(client: client)
            self.updateConversionCandidateWindow(client: client, trigger: .conversionStarted)
        }
        return true
    }

    private func handleEnterInComposing(client: any IMKTextInput) -> Bool {
        guard hasPreedit else { return false }

        var text = composedHiragana
        if let flushed = romajiConverter.flush() {
            text += flushed
        }
        guard !text.isEmpty else {
            composedHiragana = ""
            isDirectInputMode = false
            clearInputHistory()
            Self.candidateWindow.hide()
            return true
        }

        diagInsertText(text, client: client, "enter")
        composedHiragana = ""
        isDirectInputMode = false
        rawRomajiInput = ""
        clearInputHistory()
        Self.candidateWindow.hide()
        return true
    }

    private func handleEscapeInComposing(client: any IMKTextInput) -> Bool {
        guard hasPreedit else { return false }
        composedHiragana = ""
        isDirectInputMode = false
        rawRomajiInput = ""
        romajiConverter.clear()
        clearInputHistory()
        updateComposingMarkedText(client: client)
        return true
    }

    func handleBackspaceInComposing(client: any IMKTextInput) -> Bool {
        guard !inputHistory.isEmpty else {
            return handleBackspaceWithoutHistoryInComposing(client: client)
        }

        // Skip snapshots with non-empty romajiBuffer to treat multi-key romaji sequences
        // (e.g. "ge" → "げ") as a single character for backspace purposes.
        var snapshot: ComposingSnapshot
        repeat {
            snapshot = inputHistory.removeLast()
        } while !snapshot.romajiBuffer.isEmpty && !inputHistory.isEmpty

        composedHiragana = snapshot.composedHiragana
        romajiConverter.setBuffer(snapshot.romajiBuffer)
        rawRomajiInput = snapshot.rawRomajiInput
        updateComposingMarkedText(client: client)
        scheduleSuggest(client: client)
        return true
    }

    func handleCharacterInput(event: NSEvent, client: any IMKTextInput) -> Bool {
        guard let characters = event.characters, !characters.isEmpty else { return false }
        for char in characters {
            guard let scalar = char.unicodeScalars.first?.value else { continue }
            if scalar == 0x08 { return handleBackspaceInComposing(client: client) }
            if scalar < 0x20 || scalar == 0x7F || (0xF700...0xF8FF).contains(scalar) { return true }
            saveInputSnapshot()
            rawRomajiInput.append(char)
            processCharacter(char, scalar: scalar)
        }
        updateComposingMarkedText(client: client)
        scheduleSuggest(client: client)
        return true
    }

    // MARK: - Input history

    private func saveInputSnapshot() {
        let snapshot = ComposingSnapshot(
            composedHiragana: composedHiragana,
            romajiBuffer: romajiConverter.pendingRomaji,
            rawRomajiInput: rawRomajiInput
        )
        inputHistory.append(snapshot)
    }

    func clearInputHistory() {
        inputHistory.removeAll()
    }
}

// MARK: - Key event routing

extension AkazaInputController {
    /// ファンクションキーコードを解決する。
    /// JISキーボード: Ctrl+: (keyCode 39) → F10
    /// USキーボード: Ctrl+Shift+; (keyCode 41) → `:` → F10
    private func resolveFunctionKeyCode(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> UInt16? {
        if Self.isFunctionKey(keyCode) { return keyCode }
        return resolveCtrlShortcut(keyCode: keyCode, flags: flags)
    }

    private func resolveCtrlShortcut(
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags
    ) -> UInt16? {
        if flags == .control {
            return switch keyCode {
            case 38: 97   // Ctrl+J → F6 (ひらがな)
            case 40: 98   // Ctrl+K → F7 (カタカナ)
            case 37: 101  // Ctrl+L → F9 (全角英数)
            case 41: 100  // Ctrl+; → F8 (半角カタカナ)
            case 39: 109  // Ctrl+: → F10 (半角英数) ※JISキーボード
            default: nil
            }
        }
        if flags == [.control, .shift] {
            return switch keyCode {
            case 41: 109  // Ctrl+Shift+; → Ctrl+: → F10 ※USキーボード
            default: nil
            }
        }
        return nil
    }

    private func isJISKanaKey(_ keyCode: UInt16) -> Bool {
        keyCode == 0x68 // kVK_JIS_Kana
    }

    private func handleNonFunctionKey(
        flags: NSEvent.ModifierFlags,
        event: NSEvent,
        keyCode: UInt16,
        client: any IMKTextInput
    ) -> Bool {
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            if hasPreedit { commitCurrentState(client: client) }
            return false
        }
        switch inputState {
        case .composing:
            return handleComposingState(event: event, keyCode: keyCode, client: client)
        case .suggesting:
            return handleSuggestingState(event: event, keyCode: keyCode, client: client)
        case .converting:
            return handleConvertingState(event: event, keyCode: keyCode, client: client)
        }
    }
}

// MARK: - Commit helpers

extension AkazaInputController {
    func commitCurrentState(client: any IMKTextInput) {
        switch inputState {
        case .composing:
            commitComposingText(client: client)
        case .suggesting:
            commitSuggestingText(client: client)
        case .converting:
            commitConvertingText(client: client)
        }
    }

    func commitComposingText(client: any IMKTextInput) {
        if functionKeyState != nil {
            commitFunctionKeyState(client: client)
            return
        }
        var text = composedHiragana
        if let flushed = romajiConverter.flush() {
            text += flushed
        }
        guard !text.isEmpty else {
            composedHiragana = ""
            isDirectInputMode = false
            clearInputHistory()
            return
        }
        diagInsertText(text, client: client, "commit-composing")
        composedHiragana = ""
        isDirectInputMode = false
        rawRomajiInput = ""
        clearInputHistory()
    }

    func commitConvertingText(client: any IMKTextInput) {
        guard case .converting(let session) = inputState else { return }
        let text = session.committedText
        diagInsertText(text, client: client, "commit-converting")
        akazaClient.learnAsync(candidates: session.selectedCandidates)
        resetToComposing()
    }

    func resetToComposing() {
        cancelPendingSuggest()
        functionKeyState = nil
        inputState = .composing
        composedHiragana = ""
        isDirectInputMode = false
        rawRomajiInput = ""
        romajiConverter.clear()
        clearInputHistory()
        Self.candidateWindow.hide()
    }
}

// MARK: - Punctuation style

extension AkazaInputController {
    func applyPunctuationStyle(_ text: String) -> String {
        guard Settings.shared.punctuationStyle == .commaPeriod else { return text }
        return text.replacingOccurrences(of: "。", with: "．").replacingOccurrences(of: "、", with: "，")
    }
}

// MARK: - Deactivate

extension AkazaInputController {
    override func deactivateServer(_ sender: Any!) {
        NSLog("AkazaIME[diag]: deactivateServer id=\(diagID) \(AkazaInputController.diagClientDescription(sender))")
        cancelPendingSuggest()
        if let client = sender as? (any IMKTextInput), hasPreedit {
            commitCurrentState(client: client)
        }
        resetToComposing()
        super.deactivateServer(sender)
    }
}
