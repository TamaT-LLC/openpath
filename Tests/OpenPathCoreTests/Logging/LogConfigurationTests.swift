import Foundation
import Testing

import OpenPathCore

@Suite("LogConfiguration")
struct LogConfigurationTests {
    @Test("既定の出力先は ~/Library/Logs/openpath/openpath.log（NFR-05）")
    func defaultFileURL() {
        let expected = URL.homeDirectory.appending(path: "Library/Logs/openpath/openpath.log")

        let configuration = LogConfiguration()

        #expect(configuration.fileURL.path(percentEncoded: false) == expected.path(percentEncoded: false))
    }

    @Test("ローテーション先はログファイル名に .1 を付けたもの")
    func rotatedFileURL() {
        let configuration = LogConfiguration()

        #expect(configuration.rotatedFileURL.lastPathComponent == "openpath.log.1")
        #expect(configuration.rotatedFileURL.deletingLastPathComponent() == configuration.fileURL.deletingLastPathComponent())
    }

    @Test("出力先ディレクトリを注入できる")
    func injectedDirectory() {
        let directory = URL(filePath: "/tmp/openpath-test-logs", directoryHint: .isDirectory)

        let configuration = LogConfiguration(directory: directory)

        #expect(configuration.fileURL == directory.appending(path: "openpath.log"))
        #expect(configuration.rotatedFileURL == directory.appending(path: "openpath.log.1"))
    }

    @Test("サイズ上限と最小レベルを指定できる")
    func customValues() {
        let configuration = LogConfiguration(maximumFileSize: 1_024, minimumLevel: .warning)

        #expect(configuration.maximumFileSize == 1_024)
        #expect(configuration.minimumLevel == .warning)
    }

    @Test("既定のサイズ上限は正の値")
    func defaultMaximumFileSizeIsPositive() {
        #expect(LogConfiguration().maximumFileSize > 0)
    }
}
