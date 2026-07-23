import Cocoa
import InputMethodKit

// 経路A(OS↔Swift / IMKit)調査用の一時計測。
//
// スリープ復帰後に変換できなくなる "サイレント wedge" の原因を次回発生時に確定するためのログ。
// 「往路(OS→IME のキーイベント配送)」と「復路(IME→アプリへの insertText/setMarkedText)」の
// どちらが断たれているかを切り分けるのが目的。
//
// 方針:
//   - キー内容(keyCode/characters)は記録しない(キーロガー化を避ける)。
//   - client(IMKTextInput)の同一性・応答性のみ記録し、復帰前後で client が
//     入れ替わる/応答しなくなることを検出する。
//   - 原因特定後に削除する。検索しやすいよう全行に "[diag]" を付ける。
extension AkazaInputController {
    /// client の素性を安全な範囲でログ用に文字列化する。
    /// - bundle: 入力先アプリのバンドル ID(どのアプリで wedge したか)
    /// - ptr: client オブジェクトのポインタ(復帰前後で client が入れ替わったか)
    /// - insert/mark: insertText / setMarkedText に応答するか(復路セレクタの生存確認)
    static func diagClientDescription(_ sender: Any!) -> String {
        guard let client = sender as? (any IMKTextInput) else {
            return "client=<non-IMKTextInput:\(String(describing: sender))>"
        }
        let obj = client as AnyObject
        let bundle = client.bundleIdentifier() ?? "nil"
        let ptr = Unmanaged.passUnretained(obj).toOpaque()
        let respondsInsert = obj.responds(to: #selector(IMKTextInput.insertText(_:replacementRange:)))
        let respondsMark = obj.responds(to: #selector(IMKTextInput.setMarkedText(_:selectionRange:replacementRange:)))
        return "client=\(bundle) ptr=\(ptr) insert=\(respondsInsert) mark=\(respondsMark)"
    }

    /// 復路: insertText を計測付きで実行する。全 insertText 呼び出しはこれを経由する。
    func diagInsertText(_ text: String, client: any IMKTextInput, _ context: String) {
        NSLog("AkazaIME[diag]: insertText id=\(diagID) ctx=\(context) len=\((text as NSString).length) \(AkazaInputController.diagClientDescription(client))")
        client.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
    }

    /// 復路: setMarkedText を計測付きで実行する。全 setMarkedText 呼び出しはこれを経由する。
    func diagSetMarkedText(
        _ string: NSAttributedString,
        selectionRange: NSRange,
        client: any IMKTextInput,
        _ context: String
    ) {
        NSLog("AkazaIME[diag]: setMarkedText id=\(diagID) ctx=\(context) len=\(string.length) \(AkazaInputController.diagClientDescription(client))")
        client.setMarkedText(
            string,
            selectionRange: selectionRange,
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
    }

    /// 変換応答が反映されず破棄された(in-process ドロップ)ことを理由付きで記録する。
    func diagConvertDropped(_ reason: String) {
        NSLog("AkazaIME[diag]: convert completion dropped id=\(diagID) — \(reason)")
    }

    /// self 解放済みで diagID を参照できないドロップ専用。
    static func diagConvertDroppedNoSelf() {
        NSLog("AkazaIME[diag]: convert completion dropped — controller deallocated")
    }

    /// OS がこのコントローラを活性化したことを記録する(往路の確立確認)。
    /// 復帰後に activateServer が呼ばれない/別 client で呼ばれる、を検出する。
    override open func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        NSLog("AkazaIME[diag]: activateServer id=\(diagID) \(AkazaInputController.diagClientDescription(sender))")
        // Secure Input 中は keyDown が IME に届かない(= handle が来ない wedge に見える)。
        // activateServer は Secure Input 中でも届くので、ここが検出ポイントとして最適。
        SecureInputDiagnostics.logIfActive("activateServer")
        SecureInputNotifier.check()
    }
}
