import Cocoa

class AkazaServerProcess {
    private var process: Process?
    private(set) var stdinPipe: Pipe?
    private(set) var stdoutPipe: Pipe?

    private var restartCount = 0
    private var shouldRestart = true
    private var pendingRestart: DispatchWorkItem?

    var onRestart: (() -> Void)?
    private var terminationObserver: NSObjectProtocol?

    private func akazaDataDir() -> URL? {
        guard let xdgData = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            .map({ URL(fileURLWithPath: $0) })
            ?? Optional(FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/share"))
        else { return nil }
        return xdgData.appendingPathComponent("akaza")
    }

    func dictPath(for config: DownloadableDictConfig) -> URL? {
        return akazaDataDir()?.appendingPathComponent(config.fileName)
    }

    func isDictDownloaded(_ config: DownloadableDictConfig) -> Bool {
        guard let path = dictPath(for: config) else { return false }
        return FileManager.default.fileExists(atPath: path.path)
    }

    func downloadDict(_ config: DownloadableDictConfig, completion: @escaping (Bool) -> Void) {
        guard let dest = dictPath(for: config) else {
            completion(false)
            return
        }
        guard !FileManager.default.fileExists(atPath: dest.path) else {
            completion(true)
            return
        }

        NSLog("AkazaIME: \(config.fileName) not found, downloading...")
        let dirURL = dest.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            NSLog("AkazaIME: failed to create directory \(dirURL.path): \(error)")
            completion(false)
            return
        }

        URLSession.shared.downloadTask(with: config.downloadURL) { tmpURL, _, error in
            if let error = error {
                NSLog("AkazaIME: failed to download \(config.fileName): \(error)")
                completion(false)
                return
            }
            guard let tmpURL = tmpURL else {
                completion(false)
                return
            }
            do {
                try FileManager.default.moveItem(at: tmpURL, to: dest)
                NSLog("AkazaIME: \(config.fileName) downloaded to \(dest.path)")
                completion(true)
            } catch {
                NSLog("AkazaIME: failed to save \(config.fileName): \(error)")
                completion(false)
            }
        }.resume()
    }

    func deleteDict(_ config: DownloadableDictConfig) throws {
        guard let path = dictPath(for: config) else { return }
        guard FileManager.default.fileExists(atPath: path.path) else { return }
        try FileManager.default.removeItem(at: path)
        NSLog("AkazaIME: \(config.fileName) deleted")
    }

    func start() {
        if let existing = process, existing.isRunning {
            NSLog("AkazaIME: akaza-server already running (pid=\(existing.processIdentifier)), skipping start")
            return
        }

        let serverPath = Bundle.main.bundlePath + "/Contents/MacOS/akaza-server"
        let modelPath = Bundle.main.bundlePath + "/Contents/Resources/model"

        guard FileManager.default.fileExists(atPath: serverPath) else {
            NSLog("AkazaIME: akaza-server not found at \(serverPath)")
            return
        }

        let downloadedPaths = predefinedDownloadableDicts.compactMap { config -> String? in
            guard isDictDownloaded(config), let path = dictPath(for: config) else { return nil }
            return "\(path.path):\(config.encoding)"
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: serverPath)
        proc.arguments = [modelPath] + downloadedPaths + Settings.shared.additionalDictPaths

        let stdin = Pipe()
        let stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout

        proc.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            NSLog("AkazaIME: akaza-server terminated with status \(status)")
            DispatchQueue.main.async { self?.handleTermination(of: terminatedProcess) }
        }

        do {
            try proc.run()
            NSLog("AkazaIME: akaza-server started (pid=\(proc.processIdentifier))")
            self.process = proc
            self.stdinPipe = stdin
            self.stdoutPipe = stdout
            self.restartCount = 0
        } catch {
            NSLog("AkazaIME: failed to start akaza-server: \(error)")
        }

        if terminationObserver == nil {
            terminationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.stop()
            }
        }
    }

    // メインキューで呼ばれること。self.process === terminatedProcess チェックで
    // restart() が既に新プロセスを起動済みの場合の二重起動を防ぐ。
    private func handleTermination(of terminatedProcess: Process) {
        guard process === terminatedProcess, shouldRestart else { return }

        let delay = min(pow(2.0, Double(restartCount)), 15.0)
        restartCount += 1
        NSLog("AkazaIME: restarting akaza-server in \(delay)s (attempt \(restartCount))")

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.pendingRestart = nil
            self.start()
            self.onRestart?()
        }
        pendingRestart = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func restart() {
        pendingRestart?.cancel()
        pendingRestart = nil
        shouldRestart = false
        process?.terminate()
        process?.waitUntilExit()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        shouldRestart = true
        restartCount = 0
        start()
        onRestart?()
    }

    func stop() {
        pendingRestart?.cancel()
        pendingRestart = nil
        shouldRestart = false
        guard let proc = process, proc.isRunning else { return }
        NSLog("AkazaIME: stopping akaza-server")
        proc.terminate()
        proc.waitUntilExit()
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
    }
}
