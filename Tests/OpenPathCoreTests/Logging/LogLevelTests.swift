import Testing

@testable import OpenPathCore

@Suite("LogLevel")
struct LogLevelTests {
    @Test("重要度は debug < info < warning < error の順")
    func ordering() {
        #expect(LogLevel.allCases == [.debug, .info, .warning, .error])
        #expect(LogLevel.debug < .info)
        #expect(LogLevel.info < .warning)
        #expect(LogLevel.warning < .error)
    }

    @Test(
        "ファイル出力用のラベルは大文字表記",
        arguments: [
            (LogLevel.debug, "DEBUG"),
            (.info, "INFO"),
            (.warning, "WARNING"),
            (.error, "ERROR"),
        ]
    )
    func label(level: LogLevel, expected: String) {
        #expect(level.label == expected)
    }

    @Test(
        "info 以上のメッセージはパスを伏せ字にする（NFR-05）",
        arguments: [
            (LogLevel.debug, false),
            (.info, true),
            (.warning, true),
            (.error, true),
        ]
    )
    func redactsPaths(level: LogLevel, expected: Bool) {
        #expect(level.redactsPaths == expected)
    }
}
