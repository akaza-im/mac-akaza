import Foundation

/// akaza.log の起動時ローテーション。
///
/// stderr を dup2 でログファイルに直結しているため実行中のローテーションはできない。
/// 起動時にサイズを確認し、上限を超えていたら 1 世代だけ退避する
/// （akaza.log → akaza.log.1、既存の .1 は破棄）。
/// 2026-07-23 時点で無制限のまま 194MB まで肥大化していたための対処。
enum LogRotation {
    /// この上限を超えていたら起動時に退避する。
    /// IME は数週間起動しっぱなしになるため、運用中の肥大は許容し世代退避で回収する。
    static let maxBytes = 10 * 1024 * 1024

    /// logFile が maxBytes を超えていたら logFile.1 に退避する。
    /// - Returns: 退避を行ったら true。
    @discardableResult
    static func rotateIfNeeded(
        at logFile: URL,
        maxBytes: Int = LogRotation.maxBytes,
        fileManager: FileManager = .default
    ) -> Bool {
        guard
            let attrs = try? fileManager.attributesOfItem(atPath: logFile.path),
            let size = attrs[.size] as? Int,
            size > maxBytes
        else { return false }

        let rotated = logFile.appendingPathExtension("1")
        do {
            if fileManager.fileExists(atPath: rotated.path) {
                try fileManager.removeItem(at: rotated)
            }
            try fileManager.moveItem(at: logFile, to: rotated)
            return true
        } catch {
            // ローテーション失敗でロギング自体を止めない(既存ファイルへの追記を続ける)
            NSLog("AkazaIME: log rotation failed: \(error)")
            return false
        }
    }
}
