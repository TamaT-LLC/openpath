import Foundation
import Testing

@testable import OpenPathCore

@Suite("LogLineFormatter")
struct LogLineFormatterTests {
    @Test("ミリ秒精度の ISO 8601 タイムスタンプ・レベル・メッセージを 1 行で出力する")
    func formatsSingleLine() {
        let formatter = LogLineFormatter(timeZone: utcTimeZone)
        let entry = LogEntry(date: fixedDate, level: .info, message: "panel detected")

        let line = formatter.format(entry)

        #expect(line == "2023-11-14T22:13:20.125Z [INFO] panel detected\n")
    }

    @Test("タイムゾーンのオフセットをコロン区切りで出力する")
    func formatsTimeZoneOffset() throws {
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        let formatter = LogLineFormatter(timeZone: tokyo)
        let entry = LogEntry(date: fixedDate, level: .error, message: "failed")

        let line = formatter.format(entry)

        #expect(line == "2023-11-15T07:13:20.125+09:00 [ERROR] failed\n")
    }

    @Test(
        "ミリ秒未満は切り捨てて常に 3 桁で出力する",
        arguments: [
            (1_700_000_000.0, "20.000Z"),
            (1_700_000_000.5, "20.500Z"),
            (1_700_000_000.9999, "20.999Z"),
        ]
    )
    func millisecondPrecision(seconds: TimeInterval, expectedSuffix: String) {
        let formatter = LogLineFormatter(timeZone: utcTimeZone)
        let entry = LogEntry(date: Date(timeIntervalSince1970: seconds), level: .debug, message: "x")

        let line = formatter.format(entry)

        #expect(line.hasPrefix("2023-11-14T22:13:\(expectedSuffix) [DEBUG] "))
    }

    @Test("パス付きエントリは「メッセージ: パス」で出力する")
    func formatsPath() {
        let formatter = LogLineFormatter(timeZone: utcTimeZone)
        let entry = LogEntry(date: fixedDate, level: .debug, message: "candidate selected", path: "/Users/alice/repo")

        let line = formatter.format(entry)

        #expect(line == "2023-11-14T22:13:20.125Z [DEBUG] candidate selected: /Users/alice/repo\n")
    }

    @Test("メッセージ中の改行はエスケープし、1 エントリ 1 行を保つ")
    func escapesNewlines() {
        let formatter = LogLineFormatter(timeZone: utcTimeZone)
        let entry = LogEntry(date: fixedDate, level: .warning, message: "first\nsecond\r\nthird", path: "/a\nb")

        let line = formatter.format(entry)

        #expect(line == "2023-11-14T22:13:20.125Z [WARNING] first\\nsecond\\nthird: /a\\nb\n")
        #expect(line.filter(\.isNewline).count == 1)
    }
}
