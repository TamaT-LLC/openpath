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

    @Test(
        "設定値（defaults の logLevel）から読む。大文字小文字と前後の空白は区別しない",
        arguments: [
            ("debug", LogLevel.debug),
            ("DEBUG", .debug),
            (" Info\n", .info),
            ("warning", .warning),
            ("error", .error),
        ]
    )
    func parsesPreferenceValue(value: String, expected: LogLevel) {
        #expect(LogLevel(preferenceValue: value) == expected)
    }

    @Test("どのレベルにも当たらない設定値は nil", arguments: ["", "verbose", "warn", "1", "debug info"])
    func rejectsUnknownPreferenceValue(value: String) {
        #expect(LogLevel(preferenceValue: value) == nil)
    }

    @Test("設定値として書く文字列は小文字で、読み戻すと同じレベルになる", arguments: LogLevel.allCases)
    func preferenceValueRoundTrips(level: LogLevel) {
        #expect(level.preferenceValue == level.label.lowercased())
        #expect(LogLevel(preferenceValue: level.preferenceValue) == level)
    }
}
