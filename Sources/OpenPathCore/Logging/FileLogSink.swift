import Foundation
import os

/// ログをファイルに追記するシンク。
///
/// 書き込みはシリアルキューで非同期に行い、呼び出し元をファイル I/O でブロックしない。
/// キューが書き込み順と排他を保証する。ファイルハンドルを保持せず書き込みごとに開閉するため可変状態を持たず、
/// ログファイルやディレクトリが外部で削除・移動されても次の書き込みで復帰できる。
final class FileLogSink: LogSink {
    private static let queueLabel = "\(AppInfo.bundleIdentifier).logging.file"
    private static let failureLogCategory = "logging"
    private static let failureLogger = Logger(subsystem: AppInfo.bundleIdentifier, category: failureLogCategory)

    let fileURL: URL
    private let rotatedFileURL: URL
    private let maximumFileSize: Int
    private let formatter: LogLineFormatter
    private let onFailure: @Sendable (any Error) -> Void
    private let queue = DispatchQueue(label: queueLabel, qos: .utility)

    init(
        configuration: LogConfiguration,
        timeZone: TimeZone = .current,
        onFailure: @escaping @Sendable (any Error) -> Void = FileLogSink.reportFailure
    ) {
        fileURL = configuration.fileURL
        rotatedFileURL = configuration.rotatedFileURL
        maximumFileSize = configuration.maximumFileSize
        formatter = LogLineFormatter(timeZone: timeZone)
        self.onFailure = onFailure
    }

    func write(_ entry: LogEntry) {
        queue.async { [self] in
            let line = Data(formatter.format(entry).utf8)
            do {
                try append(line)
            } catch {
                onFailure(error)
            }
        }
    }

    func flush() {
        queue.sync {}
    }

    /// エラーの説明文にはログファイルのパスが含まれ得るため、ドメインとコードのみを記録する。
    static func reportFailure(_ error: any Error) {
        let nsError = error as NSError
        failureLogger.error(
            "ログファイルへの書き込みに失敗しました: \(nsError.domain, privacy: .public) (\(nsError.code, privacy: .public))"
        )
    }

    private func append(_ line: Data) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try rotateIfNeeded(adding: line.count, fileManager: fileManager)

        guard fileManager.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            try line.write(to: fileURL)
            return
        }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    /// 追記すると上限を超える場合に現在のファイルを `.1` に退避する。
    /// 空のファイルは退避しないため、上限より大きい 1 行も欠落させずに書き込める。
    private func rotateIfNeeded(adding byteCount: Int, fileManager: FileManager) throws {
        let currentSize = try currentFileSize(fileManager: fileManager)
        guard currentSize > 0, currentSize + byteCount > maximumFileSize else { return }

        if fileManager.fileExists(atPath: rotatedFileURL.path(percentEncoded: false)) {
            try fileManager.removeItem(at: rotatedFileURL)
        }
        try fileManager.moveItem(at: fileURL, to: rotatedFileURL)
    }

    private func currentFileSize(fileManager: FileManager) throws -> Int {
        let path = fileURL.path(percentEncoded: false)
        guard fileManager.fileExists(atPath: path) else { return 0 }
        let attributes = try fileManager.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.intValue ?? 0
    }
}
