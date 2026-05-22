import Cocoa
import Darwin
import InputMethodKit

// akaza-server クラッシュ時にパイプ書き込みで SIGPIPE によりプロセスが終了するのを防ぐ
signal(SIGPIPE, SIG_IGN)

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
NSLog("AkazaIME: starting")

let connectionName = getConnectionName()
NSLog("AkazaIME: connection name = \(connectionName)")

guard let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
    NSLog("AkazaIME: failed to create IMKServer")
    exit(1)
}
_ = server // IMKServer を保持

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
}

NSApplication.shared.run()
