import Foundation
import Testing

import OpenPathCore

@Suite("PaletteQueryExpansion")
struct PaletteQueryExpansionTests {
    @Test("ディレクトリは末尾に / を付けて、配下のサブディレクトリを検索できるようにする")
    func directoryGetsTrailingSeparator() {
        #expect(PaletteQueryExpansion.query(expanding: "/Users/example/repos/fern", isDirectory: true) == "/Users/example/repos/fern/")
    }

    @Test("既に / で終わるディレクトリやルートには重ねて付けない", arguments: ["/Users/example/", "/"])
    func separatorIsNotDuplicated(path: String) {
        #expect(PaletteQueryExpansion.query(expanding: path, isDirectory: true) == path)
    }

    @Test("ファイルは掘り下げられないため、パスをそのまま展開する")
    func fileIsExpandedAsIs() {
        #expect(PaletteQueryExpansion.query(expanding: "/Users/example/notes.md", isDirectory: false) == "/Users/example/notes.md")
    }

    @Test("日本語を含むパスもそのまま展開する")
    func japanesePath() {
        #expect(PaletteQueryExpansion.query(expanding: "/Users/example/Documents/資料", isDirectory: true) == "/Users/example/Documents/資料/")
    }

    @Test("実ファイルシステムでディレクトリかどうかを判定する")
    func detectsExistingDirectory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "PaletteQueryExpansionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "file.txt")
        try Data().write(to: file)

        #expect(PaletteQueryExpansion.isExistingDirectory(directory.path))
        #expect(PaletteQueryExpansion.isExistingDirectory(file.path) == false)
        #expect(PaletteQueryExpansion.isExistingDirectory(directory.appending(path: "missing").path) == false)
    }
}
