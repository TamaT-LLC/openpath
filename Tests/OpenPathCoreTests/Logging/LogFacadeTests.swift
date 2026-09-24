import Foundation
import Testing

@testable import OpenPathCore

/// `Log` はプロセス全体で共有される状態を持つため、このスイートのテストは直列に実行し、
/// 各テストの終了時に元のロガーへ戻す。テストプロセスでは誰も `Log.configure` を呼ばないため、
/// 各テストの開始時点の共有ロガーは configure 前の既定ロガーになる。
///
/// 他スイートのテストも Core のコード経由で `Log` を並行して呼び、差し替えた共有ロガーに出力が混ざり得る。
/// そのため、共有ロガーに届いた出力は `makeLogMarker()` の文字列で自分の分だけを取り出して検証する。
@Suite("Log ファサード", .serialized)
struct LogFacadeTests {
    @Test("configure する前の共有ロガーは統合ログにのみ出力し、ファイルシンクを持たない")
    func unconfiguredLoggerOutputsOnlyToUnifiedLog() {
        let logger = Log.logger

        #expect(!logger.sinks.isEmpty)
        #expect(logger.sinks.allSatisfy { $0 is OSLogSink })
        #expect(logger.minimumLevel == LogConfiguration.defaultMinimumLevel)
    }

    @Test("configure する前は各メソッドを呼んでも、既定の出力先を含めどこにもファイルを作らない")
    func unconfiguredLoggerCreatesNoFiles() throws {
        // ファイルシンクを持つ状態でログを出すと実ユーザーの ~/Library/Logs に書き込んでしまうため、先に打ち切る
        try #require(Log.logger.sinks.allSatisfy { $0 is OSLogSink })
        let defaultConfiguration = LogConfiguration()
        let directoryPath = defaultConfiguration.directory.path(percentEncoded: false)
        let directoryExisted = FileManager.default.fileExists(atPath: directoryPath)
        let marker = makeLogMarker()

        Log.debug(marker)
        Log.info(marker)
        Log.warning(marker)
        Log.error(marker)
        Log.debugPath(marker, path: "/tmp/\(marker)")
        Log.flush()

        if !directoryExisted {
            #expect(!FileManager.default.fileExists(atPath: directoryPath))
        }
        // 実アプリが同じファイルへ書き込んでいても判定できるよう、このテストが出したマーカーの有無で確かめる
        for url in [defaultConfiguration.fileURL, defaultConfiguration.rotatedFileURL] {
            let contents = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            #expect(!contents.contains(marker))
        }
    }

    @Test("各メソッドは共有ロガーに転送する")
    func forwardsToSharedLogger() {
        let marker = makeLogMarker()
        let spy = SpyLogSink()
        let previous = Log.install(AppLogger(minimumLevel: .debug, sinks: [spy], clock: { fixedDate }))
        defer { Log.install(previous) }

        Log.debug("\(marker) d")
        Log.info("\(marker) i")
        Log.warning("\(marker) w")
        Log.error("\(marker) e")
        Log.debugPath("\(marker) p", path: "/tmp/openpath")
        Log.flush()

        let entries = spy.entries.filter { $0.message.hasPrefix(marker) }
        #expect(entries.map(\.level) == [.debug, .info, .warning, .error, .debug])
        #expect(entries.map(\.message) == ["d", "i", "w", "e", "p"].map { "\(marker) \($0)" })
        #expect(entries.last?.path == "/tmp/openpath")
        // 他スイートが呼んだ flush も数え得るため、転送されたことだけを確かめる
        #expect(spy.flushCount >= 1)
    }

    @Test("差し替え時に以前のロガーを flush する")
    func installFlushesPreviousLogger() {
        let spy = SpyLogSink()
        let previous = Log.install(AppLogger(minimumLevel: .debug, sinks: [spy]))
        defer { Log.install(previous) }

        Log.install(AppLogger(minimumLevel: .debug, sinks: []))

        // 他スイートが呼んだ flush も数え得るため、1 回以上であることを確かめる
        #expect(spy.flushCount >= 1)
    }

    @Test("configure した出力先にミリ秒精度のタイムスタンプ付きで書き込み、info ではパスを出力しない")
    func configureWritesToConfiguredFile() throws {
        let marker = makeLogMarker()
        try withTemporaryDirectory { directory in
            let previous = Log.logger
            defer { Log.install(previous) }
            let configuration = LogConfiguration(directory: directory, minimumLevel: .info)

            Log.configure(configuration)
            Log.debugPath("\(marker) candidate selected", path: "/Users/alice/secret-project")
            Log.info("\(marker) palette shown")
            Log.flush()

            let contents = try String(contentsOf: configuration.fileURL, encoding: .utf8)
            let lines = try readLogLines(at: configuration.fileURL).filter { $0.contains(marker) }
            #expect(!contents.contains("secret-project"))
            #expect(lines.count == 1)
            let line = try #require(lines.first)
            // ミリ秒精度の ISO 8601 タイムスタンプ（例: 2026-09-23T12:34:56.789+09:00）
            let timestampPattern = #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}(?:Z|[+-]\d{2}:\d{2})/#
            #expect(line.prefixMatch(of: timestampPattern) != nil)
            #expect(line.hasSuffix(" [INFO] \(marker) palette shown"))
        }
    }

    @Test("同じ出力先のロガーに差し替えた後も、旧ロガー経由の書き込みと順序が保たれ、flush で書き切る")
    func replacementKeepsOrderWithStaleLogger() throws {
        let marker = makeLogMarker()
        let messages = (0..<100).map { "\(marker)-event-" + String(format: "%03d", $0) }
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

            let written = try readLogLines(at: configuration.fileURL)
                .compactMap { line in line.split(separator: " ").last.map(String.init) }
                .filter { $0.hasPrefix(marker) }
            #expect(written == messages)
        }
    }

    @Test("isDebugEnabled は共有ロガーの最小レベルが debug のときだけ true", arguments: LogLevel.allCases)
    func isDebugEnabledFollowsMinimumLevel(level: LogLevel) {
        let previous = Log.install(AppLogger(minimumLevel: level, sinks: [SpyLogSink()], clock: { fixedDate }))
        defer { Log.install(previous) }

        #expect(Log.isDebugEnabled == (level == .debug))
    }
}

