import Cocoa
import Darwin
import InputMethodKit

// akaza-server クラッシュ時にパイプ書き込みで SIGPIPE によりプロセスが終了するのを防ぐ
signal(SIGPIPE, SIG_IGN)

private func setupApplicationMenu() {
    let app = NSApplication.shared  // NSApp が nil のまま mainMenu を設定するとクラッシュするため先に初期化する

    let mainMenu = NSMenu()

    let appMenuItem = NSMenuItem()
    mainMenu.addItem(appMenuItem)

    let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: "Edit")
    editMenu.addItem(
        NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
    editMenu.addItem(
        NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z"))
    editMenu.addItem(NSMenuItem.separator())
    editMenu.addItem(
        NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
    editMenu.addItem(
        NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
    editMenu.addItem(
        NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
    editMenu.addItem(
        NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    app.mainMenu = mainMenu
}

private func setupLogging() {
    let logDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AkazaIME")
    try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)

    let logFile = logDir.appendingPathComponent("akaza.log")
    if !FileManager.default.fileExists(atPath: logFile.path) {
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
    }

    if let handle = FileHandle(forWritingAtPath: logFile.path) {
        handle.seekToEndOfFile()
        // stderr をログファイルにリダイレクト
        dup2(handle.fileDescriptor, STDERR_FILENO)
    }
}

private func getConnectionName() -> String {
    if let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String {
        return name
    }
    return (Bundle.main.bundleIdentifier ?? "com.github.tokuhirom.inputmethod.Japanese.Akaza") + "_Connection"
}

setupLogging()
setupApplicationMenu()
NSLog("AkazaIME: starting")

let connectionName = getConnectionName()
NSLog("AkazaIME: connection name = \(connectionName)")

// wake 時に作り直せるよう var で保持する（経路A: 接続腐敗の予防実験）
var imkServer = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
guard imkServer != nil else {
    NSLog("AkazaIME: failed to create IMKServer")
    exit(1)
}

let akazaServerProcess = AkazaServerProcess()
let akazaClient = JSONRPCClient(serverProcess: akazaServerProcess)

// SKK-JISYO.L がなければバックグラウンドでダウンロードしてから起動
// 既にある場合はそのまま即起動
func startServer() {
    akazaServerProcess.start()
    akazaClient.startReaderLoop()
}

if let skkJisyoLConfig = predefinedDownloadableDicts.first(where: { $0.id == "skk-jisyo-l" }) {
    akazaServerProcess.downloadDict(skkJisyoLConfig) { _ in
        DispatchQueue.main.async { startServer() }
    }
} else {
    startServer()
}

NSLog("AkazaIME: IMKServer created successfully")

// スリープ復帰後にサーバーを再起動してパイプ接続を回復する
// macOS はスリープ中にパイプ接続を破棄することがあるため、ウェイク時に再起動が必要
NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.didWakeNotification,
    object: nil,
    queue: .main
) { _ in
    NSLog("AkazaIME: wake from sleep — restarting akaza-server")
    akazaServerProcess.restart()

    // 経路A 予防実験: wake 後に OS↔AkazaIME の IMKit 接続が腐って keyDown(往路)が
    // 届かなくなる wedge を、接続が壊れる前に IMKServer を能動的に張り直して防ぐ。
    // 効果は未検証なので [diag] で観測する。最悪 IMKServer が作れなくても killall /
    // 自動再起動で回復するため、reboot を要する現状の wedge より悪化はしない。
    //
    // 手順を分けるのが重要: まず旧 IMKServer を解放し、runloop を1サイクル回して
    // Mach ポート名の解放(非同期)を待ってから、同名で作り直す。同期に nil→再 init
    // すると名前衝突で失敗しやすい。
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
        NSLog("AkazaIME[diag]: wake — releasing IMKServer (name=\(connectionName))")
        imkServer = nil // 旧接続を畳む（ARC で dealloc → Mach ポート名を解放）

        func recreate(attempt: Int) {
            imkServer = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier)
            if imkServer != nil {
                NSLog("AkazaIME[diag]: IMKServer recreated on wake (attempt=\(attempt))")
            } else if attempt < 5 {
                NSLog("AkazaIME[diag]: IMKServer recreate failed (attempt=\(attempt)) — retrying")
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { recreate(attempt: attempt + 1) }
            } else {
                NSLog("AkazaIME[diag]: WARNING IMKServer recreate gave up after \(attempt) attempts — killall to recover")
            }
        }
        // 解放を runloop に消化させてから再生成する
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { recreate(attempt: 1) }
    }
}

NSApplication.shared.run()
