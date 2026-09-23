import Foundation
import Testing

@testable import OpenPathCore

@Suite("FileLogSink")
struct FileLogSinkTests {
    private static let formatter = LogLineFormatter(timeZone: utcTimeZone)
    private static let linePrefix = "2023-11-14T22:13:20.125Z [INFO] "
    /// "line-1" 〜 "line-9" は同じ長さになるため、上限を行数で表現できる。
    private static let linesPerFile = 3

    private static func entry(_ message: String) -> LogEntry {
        LogEntry(date: fixedDate, level: .info, message: message)
    }

    private static func lineSize(_ message: String) -> Int {
        formatter.format(entry(message)).utf8.count
    }

    /// 各行からメッセージ部分（行末の単語）を取り出す。
    private static func messages(at url: URL) throws -> [String] {
        try readLogLines(at: url).compactMap { line in
            line.split(separator: " ").last.map(String.init)
        }
    }

    private static func makeSink(
        configuration: LogConfiguration,
        failures: FailureRecorder = FailureRecorder()
    ) -> FileLogSink {
        FileLogSink(configuration: configuration, timeZone: utcTimeZone, onFailure: failures.record)
    }

    @Test("出力先ディレクトリが無ければ作成して書き込む")
    func createsDirectory() throws {
        try withTemporaryDirectory { root in
            let configuration = LogConfiguration(directory: root.appending(path: "nested/logs", directoryHint: .isDirectory))
            let sink = Self.makeSink(configuration: configuration)

            sink.write(Self.entry("hello"))
            sink.flush()

            let lines = try readLogLines(at: configuration.fileURL)
            #expect(lines == ["\(Self.linePrefix)hello"])
        }
    }

    @Test("書き込み順に追記し、既存の内容を保持する")
    func appendsInOrder() throws {
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(directory: directory)
            try "existing\n".write(to: configuration.fileURL, atomically: true, encoding: .utf8)
            let sink = Self.makeSink(configuration: configuration)

            sink.write(Self.entry("first"))
            sink.write(Self.entry("second"))
            sink.flush()

            let lines = try readLogLines(at: configuration.fileURL)
            #expect(lines == [
                "existing",
                "\(Self.linePrefix)first",
                "\(Self.linePrefix)second",
            ])
        }
    }

    @Test("サイズ上限を超える書き込みの前に既存ファイルを .1 に退避する")
    func rotatesWhenExceedingLimit() throws {
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(
                directory: directory,
                maximumFileSize: Self.lineSize("line-1") * Self.linesPerFile
            )
            let sink = Self.makeSink(configuration: configuration)

            for index in 1...(Self.linesPerFile + 1) {
                sink.write(Self.entry("line-\(index)"))
            }
            sink.flush()

            let rotated = try Self.messages(at: configuration.rotatedFileURL)
            let current = try Self.messages(at: configuration.fileURL)
            #expect(rotated == ["line-1", "line-2", "line-3"])
            #expect(current == ["line-4"])
        }
    }

    @Test("上限ちょうどまでは退避しない")
    func doesNotRotateAtExactLimit() throws {
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(
                directory: directory,
                maximumFileSize: Self.lineSize("line-1") * Self.linesPerFile
            )
            let sink = Self.makeSink(configuration: configuration)

            for index in 1...Self.linesPerFile {
                sink.write(Self.entry("line-\(index)"))
            }
            sink.flush()

            let current = try Self.messages(at: configuration.fileURL)
            #expect(current == ["line-1", "line-2", "line-3"])
            #expect(!FileManager.default.fileExists(atPath: configuration.rotatedFileURL.path(percentEncoded: false)))
        }
    }

    @Test("再ローテーション時は .1 を上書きし、1 世代だけ保持する")
    func keepsSingleGeneration() throws {
        let totalLines = Self.linesPerFile * 2 + 1
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(
                directory: directory,
                maximumFileSize: Self.lineSize("line-1") * Self.linesPerFile
            )
            let sink = Self.makeSink(configuration: configuration)

            for index in 1...totalLines {
                sink.write(Self.entry("line-\(index)"))
            }
            sink.flush()

            let rotated = try Self.messages(at: configuration.rotatedFileURL)
            let current = try Self.messages(at: configuration.fileURL)
            #expect(rotated == ["line-4", "line-5", "line-6"])
            #expect(current == ["line-7"])
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            #expect(Set(files) == ["openpath.log", "openpath.log.1"])
        }
    }

    @Test("上限より大きい 1 行も欠落させずに書き込む")
    func writesOversizedLine() throws {
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(directory: directory, maximumFileSize: 1)
            let sink = Self.makeSink(configuration: configuration)

            sink.write(Self.entry("first"))
            sink.write(Self.entry("second"))
            sink.flush()

            let rotated = try Self.messages(at: configuration.rotatedFileURL)
            let current = try Self.messages(at: configuration.fileURL)
            #expect(rotated == ["first"])
            #expect(current == ["second"])
        }
    }

    @Test("書き込み中にディレクトリが削除されても再作成して書き込む")
    func recreatesDeletedDirectory() throws {
        try withTemporaryDirectory { root in
            let configuration = LogConfiguration(directory: root.appending(path: "logs", directoryHint: .isDirectory))
            let sink = Self.makeSink(configuration: configuration)
            sink.write(Self.entry("before"))
            sink.flush()

            try FileManager.default.removeItem(at: configuration.directory)
            sink.write(Self.entry("after"))
            sink.flush()

            let current = try Self.messages(at: configuration.fileURL)
            #expect(current == ["after"])
        }
    }

    @Test("複数スレッドから同時に書き込んでも行が欠落・混在しない")
    func concurrentWrites() throws {
        let writeCount = 200
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(directory: directory)
            let sink = Self.makeSink(configuration: configuration)

            DispatchQueue.concurrentPerform(iterations: writeCount) { index in
                sink.write(Self.entry("message-\(index)"))
            }
            sink.flush()

            let lines = try readLogLines(at: configuration.fileURL)
            let messages = try Self.messages(at: configuration.fileURL)
            #expect(lines.count == writeCount)
            #expect(lines.allSatisfy { $0.hasPrefix("\(Self.linePrefix)message-") })
            #expect(Set(messages) == Set((0..<writeCount).map { "message-\($0)" }))
        }
    }

    @Test("書き込めない場合はクラッシュせず失敗を通知する")
    func reportsFailure() throws {
        try withTemporaryDirectory { root in
            // ディレクトリを作るべき場所に通常ファイルを置き、書き込みを失敗させる
            let blockingFile = root.appending(path: "not-a-directory")
            try Data().write(to: blockingFile)
            let failures = FailureRecorder()
            let sink = Self.makeSink(configuration: LogConfiguration(directory: blockingFile), failures: failures)

            sink.write(Self.entry("lost"))
            sink.flush()

            #expect(failures.count == 1)
        }
    }
}
