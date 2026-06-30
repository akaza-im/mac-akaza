# InputMethodKit documentation review

Date: 2026-06-26

This note summarizes a review of Apple's InputMethodKit documentation against the current AkazaIME implementation. The review covered the InputMethodKit top-level documentation and the linked classes, protocols, constants, data types, and method pages exposed from that page. The same contracts were cross-checked against the Xcode SDK headers because the Apple Developer Documentation pages are DocC/JavaScript backed.

Primary sources:

- https://developer.apple.com/documentation/inputmethodkit
- https://developer.apple.com/documentation/inputmethodkit/imkserver
- https://developer.apple.com/documentation/inputmethodkit/imkinputcontroller
- https://developer.apple.com/documentation/inputmethodkit/imkcandidates
- https://developer.apple.com/documentation/inputmethodkit/imkstatesetting
- https://developer.apple.com/documentation/inputmethodkit/imkserverinput
- Xcode SDK headers:
  - `InputMethodKit.framework/Headers/IMKServer.h`
  - `InputMethodKit.framework/Headers/IMKInputController.h`
  - `HIToolbox.framework/Headers/IMKInputSession.h`
  - `HIToolbox.framework/Headers/TextInputSources.h`

## Summary

The current one-server startup model is consistent with IMKit. `IMKServer` should be created by the input method's main function and kept as the server for client sessions. The previous wake-time experiment that released and recreated `IMKServer` inside the running process was not consistent with the documented model and likely contributed to the 2026-06-26 hang.

The remaining issues are mostly around composition lifecycle coverage and asynchronous callbacks. The highest-priority implementation gap is `commitComposition(_:)`, which IMKit can call independently of `deactivateServer(_:)`.

## Documentation contracts relevant to AkazaIME

### `IMKServer`

`IMKServer` represents the input method to the rest of the system and manages client sessions. The SDK header states that an input method should create exactly one `IMKServer`. It creates a connection and creates an `IMKInputController` for each client input session.

Implication for AkazaIME:

- Creating a single server in `main.swift` is correct.
- Releasing and recreating `IMKServer` on wake is risky and should not be used as a recovery strategy.
- Recovery from OS-side IMKit registration corruption should be handled outside the live `IMKServer` object, such as through bundle registration/install flows or user-session recovery.

Current state:

- `main.swift` now keeps a single `let imkServer`.
- Wake handling only restarts `akaza-server`; it no longer touches `IMKServer`.

### `IMKServerInput`

IMKit supports three input styles:

1. key binding via `inputText(_:client:)` and `didCommand(by:client:)`
2. unpacked key data via `inputText(_:key:modifiers:client:)`
3. direct `NSEvent` delivery via `handle(_:client:)`

AkazaIME uses the third style by overriding `handle(_:client:)`, which is appropriate for its key-code-sensitive Japanese IME behavior.

Important return-value contract:

- Return `true` only when the event was handled.
- Return `false` when the client application should receive the event.

Current state:

- This is broadly respected for Tab, function keys with no preedit, and command/control/option cases.
- The code intentionally consumes some keys to prevent unwanted text insertion while composing/converting.

### `commitComposition(_:)`

The `IMKServerInput` informal protocol includes `commitComposition(_:)`. IMKit calls it when the client wants the composition session to end immediately. The documented response is to call the client's `insertText` and clean up per-session buffers.

`recognizedEvents(_:)` defaults to key-down events. When an input method only recognizes key-down events, IMKit provides default mouse handling. If there is an active composition and the user clicks outside it, IMKit sends `commitComposition(_:)`.

Issue:

- AkazaIME commits on `deactivateServer(_:)`, but it does not currently implement `commitComposition(_:)`.
- This leaves an IMKit-standard composition-ending path uncovered.

Recommended fix:

- Implement `commitComposition(_:)` on `AkazaInputController`.
- If `sender` conforms to `IMKTextInput` and `hasPreedit` is true, call `commitCurrentState(client:)`.
- Always reset composition state and hide candidate UI afterward.

### `deactivateServer(_:)`

`deactivateServer(_:)` is the activation lifecycle hook. It is not the only composition-ending path.

Current state:

- AkazaIME cancels pending suggestions, commits current state when possible, resets local state, and calls `super.deactivateServer(sender)`.
- This is reasonable, but should not be treated as a substitute for `commitComposition(_:)`.

### `IMKTextInput`

`insertText(_:replacementRange:)` and `setMarkedText(_:selectionRange:replacementRange:)` use `NSNotFound` replacement ranges to mean "current insertion point." Selection ranges are relative to the marked string.

Current state:

- AkazaIME's `diagInsertText` and `diagSetMarkedText` use `NSRange(location: NSNotFound, length: 0)`, which matches the documented current-insertion-point behavior.
- Selection ranges for marked text are relative to the marked string, which matches the documentation.

### Async conversion callbacks

IMKit creates an `IMKInputController` per client input session, and that controller has a client object. AkazaIME's conversion requests return asynchronously and capture the `client` passed to the key event handler.

Issue:

- If the controller is deactivated, the composition is reset, or a stale conversion result arrives after a client/session transition, the callback can still attempt to update marked text or candidate UI using the captured client.
- Existing state guards catch many stale responses, but they do not explicitly invalidate callbacks on activation/deactivation generation changes.

Recommended fix:

- Add a generation token on `AkazaInputController`.
- Increment it on `activateServer(_:)`, `deactivateServer(_:)`, and `commitComposition(_:)`.
- Capture the generation when starting async conversion/suggestion work.
- Drop completion callbacks when the generation no longer matches.

### Candidate UI

`IMKCandidates` is optional. Custom candidate windows are allowed in practice, but the IMKit docs and headers provide facilities that matter for correct placement and event behavior.

Issue:

- AkazaIME uses a custom `NSPanel`, not `IMKCandidates`.
- The panel level is fixed to `.popUpMenu`.
- IMK's client protocol exposes `windowLevel()` specifically so custom candidate windows can align with the client window level.
- Candidate positioning uses `NSScreen.main`, which can be wrong for multi-display, full-screen, or different-Space client windows.

Recommended fix:

- When showing the custom candidate window, use `client.windowLevel() + 1` where available instead of a fixed level.
- Determine the screen from the cursor rect rather than `NSScreen.main`.
- Keep the zero-rect fallback, but log it as diagnostic information while this issue is being investigated.

### Info.plist and TIS registration

`TextInputSources.h` says application-based input methods live in `~/Library/Input Methods/` or `/Library/Input Methods/`. For input methods, top-level `TISInputSourceID` is typically the same as the bundle ID; if omitted, the bundle ID is used. Input modes are declared under `ComponentInputModeDict` with `tsInputModeListKey`, and mode `TISInputSourceID` values should begin with the parent input method's ID or bundle ID.

Current state:

- `ComponentInputModeDict` and `tsInputModeListKey` are present.
- Japanese and Roman mode IDs begin with `com.github.tokuhirom.inputmethod.Japanese.Akaza`.
- The top-level `TISInputSourceID` is omitted, relying on the default bundle ID behavior.

Recommended hardening:

- Add top-level `TISInputSourceID` with `com.github.tokuhirom.inputmethod.Japanese.Akaza` to make registration state less implicit.
- Continue signing the `.app` bundle during `make bundle`; otherwise the signature identifier can diverge from `CFBundleIdentifier`, confusing LaunchServices/TIS.

### Preferences menu

IMKit provides a default `showPreferences(_:)` path if a menu item uses that selector and a preferences nib/controller is configured. AkazaIME uses a custom SwiftUI/AppKit preferences window instead.

Current state:

- This is acceptable, but it is outside the standard `showPreferences(_:)` path.
- No immediate correctness issue was found.

## Prioritized action list

1. Implement `commitComposition(_:)`.
2. Add async callback generation invalidation around conversion and suggestion completions.
3. Add top-level `TISInputSourceID` to `Info.plist`.
4. Use the client window level and cursor screen for the custom candidate panel.
5. Keep `IMKServer` lifetime fixed for the process lifetime; do not recreate it on wake.
6. Keep app-bundle signing in the build/install flow.

## Notes from 2026-06-26 incident

The wake-time `IMKServer` recreation experiment logged `wake — releasing IMKServer` and then failed to log either success or retry failure. Since the next statement after recreation would have logged the result, the likely failure mode is that `IMKServer(name:bundleIdentifier:)` did not return on the main thread. This is consistent with the documentation warning implied by the `IMKServer` lifetime model: the server is intended to be created once, not treated as a reconnectable session object.
