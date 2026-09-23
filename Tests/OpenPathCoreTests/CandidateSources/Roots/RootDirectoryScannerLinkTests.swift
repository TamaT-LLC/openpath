import Foundation
import Testing

import OpenPathCore

@Suite("RootDirectoryScanner: シンボリックリンク・パッケージ")
struct RootDirectoryScannerLinkTests {
    private static let loopDepth = 4

    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
    }

    private func scan(root: String? = nil, depth: Int = Config.defaultDepth, includeFiles: Bool) throws -> CandidateSourceSnapshot {
        let options = RootScanOptions(depth: depth, includeFiles: includeFiles)
        return try RootDirectoryScanner(options: options).scan(root: root ?? tree.root)
    }

    // MARK: - ルートのシンボリックリンク

    @Test("ルートがディレクトリへのシンボリックリンクなら、リンク先を走査してリンク側の表記でパスを返す")
    func followsSymlinkedRoot() throws {
        try tree.makeDirectories("a/b")
        let linkedRoot = tree.outsidePath("linked-root")
        try FileTreeFixture.makeSymbolicLink(atPath: linkedRoot, to: tree.root)

        let snapshot = try scan(root: linkedRoot, depth: 2, includeFiles: false)

        #expect(snapshot.itemSet == [
            .directory(linkedRoot), .directory(linkedRoot + "/a"), .directory(linkedRoot + "/a/b"),
        ])
    }

    @Test("リンク切れのシンボリックリンクをルートにした場合は notFound として扱う")
    func brokenSymlinkRootIsNotFound() throws {
        let brokenRoot = tree.outsidePath("broken-root")
        try FileTreeFixture.makeSymbolicLink(atPath: brokenRoot, to: tree.outsidePath("missing"))

        let snapshot = try scan(root: brokenRoot, includeFiles: false)

        #expect(snapshot.items.isEmpty)
        #expect(snapshot.warnings == [.rootUnavailable(root: brokenRoot, reason: .notFound)])
    }

    // MARK: - 配下のシンボリックリンク

    @Test("ディレクトリへのシンボリックリンクはディレクトリとして含めるが、リンク先には潜らない")
    func includesDirectoryLinkWithoutDescending() throws {
        try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("target/child"))
        try tree.makeSymbolicLink("link", to: tree.outsidePath("target"))

        let snapshot = try scan(depth: 3, includeFiles: true)

        #expect(snapshot.itemSet == [.directory(tree.root), .directory(tree.path("link"))])
    }

    @Test("ファイルへのシンボリックリンクは includeFiles=true のときだけファイルとして含める")
    func includesFileLinkOnlyWhenFilesAreIncluded() throws {
        try FileTreeFixture.makeFile(atPath: tree.outsidePath("note.txt"))
        try tree.makeSymbolicLink("note-link", to: tree.outsidePath("note.txt"))

        let withoutFiles = try scan(includeFiles: false)
        let withFiles = try scan(includeFiles: true)

        #expect(withoutFiles.itemSet == [.directory(tree.root)])
        #expect(withFiles.itemSet == [.directory(tree.root), .file(tree.path("note-link"))])
    }

    @Test("リンク切れのシンボリックリンクは含めない")
    func excludesBrokenLinks() throws {
        try tree.makeSymbolicLink("broken", to: tree.outsidePath("missing"))

        let snapshot = try scan(includeFiles: true)

        #expect(snapshot.itemSet == [.directory(tree.root)])
    }

    @Test("祖先を指す循環したシンボリックリンクがあっても、リンク自身を 1 件含めて走査を終える")
    func terminatesOnSymlinkLoop() throws {
        try tree.makeDirectories("a")
        try tree.makeSymbolicLink("a/loop", to: tree.root)

        let snapshot = try scan(depth: Self.loopDepth, includeFiles: false)

        #expect(snapshot.itemSet == [.directory(tree.root), .directory(tree.path("a")), .directory(tree.path("a/loop"))])
        #expect(snapshot.items.count == 3)
    }

    // MARK: - パッケージ

    @Test("パッケージ（.app）は中に潜らず、ファイルとして扱う")
    func treatsPackagesAsFiles() throws {
        try tree.makeDirectories("Tool.app/Contents/MacOS", "plain")

        let withoutFiles = try scan(depth: 3, includeFiles: false)
        let withFiles = try scan(depth: 3, includeFiles: true)

        #expect(withoutFiles.itemSet == [.directory(tree.root), .directory(tree.path("plain"))])
        #expect(withFiles.itemSet == [.directory(tree.root), .file(tree.path("Tool.app")), .directory(tree.path("plain"))])
    }

    @Test("パッケージへのシンボリックリンクもファイルとして扱う")
    func treatsLinkToPackageAsFile() throws {
        try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("Tool.app/Contents"))
        try tree.makeSymbolicLink("tool-link", to: tree.outsidePath("Tool.app"))

        let snapshot = try scan(includeFiles: true)

        #expect(snapshot.itemSet == [.directory(tree.root), .file(tree.path("tool-link"))])
    }
}
