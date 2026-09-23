import Foundation
import os
import Testing

@testable import OpenPathCore

@Suite("OSLogSink")
struct OSLogSinkTests {
    /// テストの出力をアプリ本体の統合ログと区別するためのサブシステム。
    private static let testSubsystem = "\(AppInfo.bundleIdentifier).tests"

    @Test("LogLevel を統合ログのレベルに対応付ける")
    func mapsLevelToOSLogType() {
        #expect(OSLogSink.osLogType(for: .debug) == .debug)
        #expect(OSLogSink.osLogType(for: .info) == .info)
        #expect(OSLogSink.osLogType(for: .warning) == .default)
        #expect(OSLogSink.osLogType(for: .error) == .error)
    }

    @Test("全レベル・パス付きのエントリを書き込んでもクラッシュしない")
    func writesAllKindsOfEntries() {
        let sink = OSLogSink(subsystem: Self.testSubsystem)

        for level in LogLevel.allCases {
            sink.write(LogEntry(date: fixedDate, level: level, message: "os log sink test"))
        }
        sink.write(LogEntry(date: fixedDate, level: .debug, message: "os log sink test", path: "/tmp/openpath-test"))
        sink.flush()
    }
}
