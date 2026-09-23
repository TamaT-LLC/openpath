import Foundation
import Testing

@testable import OpenPathCore

/// `Log` はプロセス全体で共有される状態を持つため、このスイートのテストは直列に実行し、
/// 各テストの終了時に元のロガーへ戻す。
@Suite("Log ファサード", .serialized)
struct LogFacadeTests {
    @Test("既定の共有ロガーは ~/Library/Logs/openpath/openpath.log に書き込む")
    func defaultLoggerWritesToLibraryLogs() {
        let fileSinks = Log.logger.sinks.compactMap { $0 as? FileLogSink }

        #expect(fileSinks.map(\.fileURL) == [LogConfiguration().fileURL])
        #expect(Log.logger.sinks.contains { $0 is OSLogSink })
    }

    @Test("各メソッドは共有ロガーに転送する")
    func forwardsToSharedLogger() {
        let spy = SpyLogSink()
        let previous = Log.install(AppLogger(minimumLevel: .debug, sinks: [spy], clock: { fixedDate }))
        defer { Log.install(previous) }

        Log.debug("d")
        Log.info("i")
        Log.warning("w")
        Log.error("e")
        Log.debugPath("p", path: "/tmp/openpath")
        Log.flush()

        #expect(spy.entries.map(\.level) == [.debug, .info, .warning, .error, .debug])
        #expect(spy.entries.map(\.message) == ["d", "i", "w", "e", "p"])
        #expect(spy.entries.last?.path == "/tmp/openpath")
        #expect(spy.flushCount == 1)
    }

    @Test("差し替え時に以前のロガーを flush する")
    func installFlushesPreviousLogger() {
        let spy = SpyLogSink()
        let previous = Log.install(AppLogger(minimumLevel: .debug, sinks: [spy]))
        defer { Log.install(previous) }

        Log.install(AppLogger(minimumLevel: .debug, sinks: []))

        #expect(spy.flushCount == 1)
    }

    @Test("configure した出力先にミリ秒精度のタイムスタンプ付きで書き込み、info ではパスを出力しない")
    func configureWritesToConfiguredFile() throws {
        try withTemporaryDirectory { directory in
            let previous = Log.logger
            defer { Log.install(previous) }
            let configuration = LogConfiguration(directory: directory, minimumLevel: .info)

            Log.configure(configuration)
            Log.debugPath("candidate selected", path: "/Users/alice/secret-project")
            Log.info("palette shown")
            Log.flush()

            let lines = try readLogLines(at: configuration.fileURL)
            #expect(lines.count == 1)
            let line = try #require(lines.first)
            // ミリ秒精度の ISO 8601 タイムスタンプ（例: 2026-09-23T12:34:56.789+09:00）
            let timestampPattern = #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:Z|[+-]\d{2}:\d{2})/#
            #expect(line.prefixMatch(of: timestampPattern) != nil)
            #expect(line.hasSuffix(" [INFO] palette shown"))
        }
    }

    @Test("同じ出力先のロガーに差し替えた後も、旧ロガー経由の書き込みと順序が保たれ、flush で書き切る")
    func replacementKeepsOrderWithStaleLogger() throws {
        let messages = (0..<100).map { String(format: "event-%03d", $0) }
        try withTemporaryDirectory { directory in
            let previous = Log.logger
            defer { Log.install(previous) }
            let configuration = LogConfiguration(directory: directory, minimumLevel: .info)
            Log.install(AppLogger(minimumLevel: .info, sinks: [FileLogSink(configuration: configuration)]))
            // 差し替えの直前に別スレッドが取得し、差し替え後も使い続ける参照に相当する
            let staleLogger = Log.logger
            Log.install(AppLogger(minimumLevel: .info, sinks: [FileLogSink(configuration: configuration)]))

            for (index, message) in messages.enumerated() {
                if index.isMultiple(of: 2) {
                    staleLogger.info(message)
                } else {
                    Log.info(message)
                }
            }
            Log.flush()

            let written = try readLogLines(at: configuration.fileURL).compactMap { line in
                line.split(separator: " ").last.map(String.init)
            }
            #expect(written == messages)
        }
    }
}
