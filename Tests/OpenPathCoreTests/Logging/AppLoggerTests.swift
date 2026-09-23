import Foundation
import Testing

@testable import OpenPathCore

@Suite("AppLogger")
struct AppLoggerTests {
    private static let secretPath = "/Users/alice/secret-project"

    private static func makeLogger(minimumLevel: LogLevel, sinks: [any LogSink]) -> AppLogger {
        AppLogger(minimumLevel: minimumLevel, sinks: sinks, clock: { fixedDate })
    }

    @Test("既定の設定から作ったロガーは統合ログと ~/Library/Logs/openpath/openpath.log に、既定の最小レベルで出力する")
    func defaultConfigurationLoggerWritesToLibraryLogs() {
        let configuration = LogConfiguration()

        // シンクの生成時にはファイルに触れないため、実ユーザーのログディレクトリには書き込まない
        let logger = AppLogger(configuration: configuration)

        let fileSinks = logger.sinks.compactMap { $0 as? FileLogSink }
        #expect(fileSinks.map(\.fileURL) == [configuration.fileURL])
        #expect(logger.sinks.contains { $0 is OSLogSink })
        #expect(logger.minimumLevel == LogConfiguration.defaultMinimumLevel)
    }

    @Test("最小レベル以上のログだけをシンクに渡す", arguments: LogLevel.allCases, LogLevel.allCases)
    func filtersByMinimumLevel(minimumLevel: LogLevel, level: LogLevel) {
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: minimumLevel, sinks: [spy])

        logger.log(level, "message")

        #expect(spy.entries.count == (level >= minimumLevel ? 1 : 0))
    }

    @Test("レベル別のメソッドはそれぞれのレベルで記録する")
    func levelMethods() {
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .debug, sinks: [spy])

        logger.debug("d")
        logger.info("i")
        logger.warning("w")
        logger.error("e")

        #expect(spy.entries.map(\.level) == [.debug, .info, .warning, .error])
        #expect(spy.entries.map(\.message) == ["d", "i", "w", "e"])
    }

    @Test("出力しないレベルのメッセージは組み立てない")
    func skipsEvaluatingFilteredMessage() {
        var isEvaluated = false
        func makeMessage() -> String {
            isEvaluated = true
            return "expensive"
        }
        let logger = Self.makeLogger(minimumLevel: .info, sinks: [SpyLogSink()])

        logger.debug(makeMessage())

        #expect(!isEvaluated)
    }

    @Test("レイテンシ計測のため呼び出し時点の時刻を記録する")
    func recordsCallTime() {
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .info, sinks: [spy])

        logger.info("panel detected")

        #expect(spy.entries.map(\.date) == [fixedDate])
    }

    @Test("debugPath は debug レベルでパスをメッセージと分けて記録する")
    func debugPathRecordsPathAtDebug() {
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .debug, sinks: [spy])

        logger.debugPath("candidate selected", path: Self.secretPath)

        #expect(spy.entries == [
            LogEntry(date: fixedDate, level: .debug, message: "candidate selected", path: Self.secretPath),
        ])
    }

    @Test("最小レベルが info 以上なら debugPath は何も出力せず、パスも評価しない", arguments: [LogLevel.info, .warning, .error])
    func debugPathIsSuppressedAboveDebug(minimumLevel: LogLevel) {
        var isPathEvaluated = false
        func makePath() -> String {
            isPathEvaluated = true
            return Self.secretPath
        }
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: minimumLevel, sinks: [spy])

        logger.debugPath("candidate selected", path: makePath())

        #expect(spy.entries.isEmpty)
        #expect(!isPathEvaluated)
    }

    @Test("info 以上のメッセージに含まれるパスは伏せ字にする", arguments: [LogLevel.info, .warning, .error])
    func redactsPathsAtInfoOrAbove(level: LogLevel) {
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .debug, sinks: [spy])

        logger.log(level, "opened \(Self.secretPath)")

        #expect(spy.entries.map(\.message) == ["opened <path>"])
    }

    @Test(
        "空白や閉じ記号を含むパスの断片が OSLogSink・FileLogSink のどちらにも渡らない（NFR-05）",
        arguments: [
            ("opened \"/Users/alice/report\".secret\" in 12ms", "opened \"<path>"),
            ("opened /Users/alice/My Documents/secret.txt", "opened <path>"),
            ("opened '/Users/alice/Bob's secret.txt' in 12ms", "opened '<path>"),
        ]
    )
    func sinksNeverReceivePathFragments(message: String, expected: String) throws {
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(directory: directory, minimumLevel: .info)
            // 統合ログの出力は観測できないため、OSLogSink に渡る内容を記録してから転送する
            let osLogInput = SpyLogSink(forwardingTo: OSLogSink(subsystem: testOSLogSubsystem))
            let logger = AppLogger(
                minimumLevel: configuration.minimumLevel,
                sinks: [osLogInput, FileLogSink(configuration: configuration)]
            )

            logger.info(message)
            logger.warning(message)
            logger.error(message)
            logger.flush()

            let fileContents = try String(contentsOf: configuration.fileURL, encoding: .utf8)
            let fileMessages = try readLogLines(at: configuration.fileURL).map { line in
                line.split(separator: "] ", maxSplits: 1).last.map(String.init) ?? line
            }
            #expect(osLogInput.entries.map(\.message) == [expected, expected, expected])
            #expect(fileMessages == [expected, expected, expected])
            #expect(!fileContents.contains("alice"))
            #expect(!fileContents.contains("secret"))
        }
    }

    @Test("debug のメッセージは伏せ字にしない")
    func keepsPathsAtDebug() {
        let spy = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .debug, sinks: [spy])

        logger.debug("opened \(Self.secretPath)")

        #expect(spy.entries.map(\.message) == ["opened \(Self.secretPath)"])
    }

    @Test("すべてのシンクに同じエントリを渡す")
    func fansOutToAllSinks() {
        let first = SpyLogSink()
        let second = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .info, sinks: [first, second])

        logger.info("palette shown")

        #expect(first.entries == [LogEntry(date: fixedDate, level: .info, message: "palette shown")])
        #expect(second.entries == first.entries)
    }

    @Test("flush はすべてのシンクに伝わる")
    func flushPropagatesToAllSinks() {
        let first = SpyLogSink()
        let second = SpyLogSink()
        let logger = Self.makeLogger(minimumLevel: .info, sinks: [first, second])

        logger.flush()

        #expect(first.flushCount == 1)
        #expect(second.flushCount == 1)
    }

    @Test("最小レベルが info のとき、ログファイルにパス文字列は出力されない（NFR-05）")
    func fileOutputExcludesPathsAtInfo() throws {
        try withTemporaryDirectory { directory in
            let configuration = LogConfiguration(directory: directory, minimumLevel: .info)
            let logger = AppLogger(
                minimumLevel: configuration.minimumLevel,
                sinks: [FileLogSink(configuration: configuration)]
            )

            logger.debugPath("candidate selected", path: Self.secretPath)
            logger.debug("debug \(Self.secretPath)")
            logger.info("opened \(Self.secretPath)")
            logger.warning("retrying \(Self.secretPath)")
            logger.error("failed \(Self.secretPath)")
            logger.flush()

            let contents = try String(contentsOf: configuration.fileURL, encoding: .utf8)
            #expect(!contents.contains("secret-project"))
            #expect(!contents.contains("candidate selected"))
            #expect(contents.contains("[INFO] opened <path>"))
            #expect(contents.contains("[WARNING] retrying <path>"))
            #expect(contents.contains("[ERROR] failed <path>"))
        }
    }
}
