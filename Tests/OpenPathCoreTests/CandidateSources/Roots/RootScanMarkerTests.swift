import Foundation
import Testing

import OpenPathCore

/// roots の走査の記録（RootScanMarker）による変更の検知（Issue #78）。
///
/// 周期の再構築の前に、走査で中身を読んだディレクトリ（ルートと depth 未満の各ディレクトリ）だけを stat し直し、
/// 走査し直すと候補が変わりうるかを確かめる。
@Suite("RootDirectoryScanner: 変更の検知")
struct RootScanMarkerTests {
    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
    }

    private func trackedScan(
        root: String? = nil,
        depth: Int = Config.defaultDepth,
        itemLimit: Int = RootScanOptions.defaultItemLimit
    ) throws -> RootScanResult {
        let options = RootScanOptions(depth: depth, itemLimit: itemLimit)
        return try RootDirectoryScanner(options: options).trackedScan(root: root ?? tree.root)
    }

    private func marker(root: String? = nil, depth: Int = Config.defaultDepth) throws -> RootScanMarker {
        try #require(try trackedScan(root: root, depth: depth).marker)
    }

    private static func remove(_ path: String) throws {
        try FileManager.default.removeItem(atPath: path)
    }

    // MARK: - 変更なし

    @Test("走査の直後は変更なしと判定する")
    func unchangedRightAfterScan() throws {
        try tree.makeDirectories("a/b/c", "d")
        try tree.makeFiles("a/note.txt")

        let marker = try marker()

        #expect(!marker.hasChanges())
    }

    @Test("走査の結果（候補と警告）は scan(root:) と同じ")
    func snapshotMatchesPlainScan() throws {
        try tree.makeDirectories("a/b/c", "d", "node_modules/x", ".hidden/y")
        try tree.makeFiles("a/note.txt")
        let scanner = RootDirectoryScanner(options: RootScanOptions(depth: 2, includeFiles: true))

        let tracked = try scanner.trackedScan(root: tree.root)
        let plain = try scanner.scan(root: tree.root)

        #expect(tracked.snapshot.itemSet == plain.itemSet)
        #expect(tracked.snapshot.items.count == plain.items.count)
        #expect(tracked.snapshot.warnings == plain.warnings)
    }

    // MARK: - 変更あり

    /// 走査で中身を読んだディレクトリに加える変更
    enum ListedDirectoryChange: CaseIterable, CustomTestStringConvertible {
        case addToRoot
        case removeFromRoot
        case renameInRoot
        case addToFirstLevel
        case removeFromFirstLevel
        case addFileToFirstLevel

        var testDescription: String {
            switch self {
            case .addToRoot: "ルート直下への追加"
            case .removeFromRoot: "ルート直下の削除"
            case .renameInRoot: "ルート直下の改名"
            case .addToFirstLevel: "depth 未満のディレクトリへの追加"
            case .removeFromFirstLevel: "depth 未満のディレクトリの中の削除"
            case .addFileToFirstLevel: "depth 未満のディレクトリへのファイルの追加"
            }
        }

        func apply(to tree: FileTreeFixture) throws {
            switch self {
            case .addToRoot:
                try tree.makeDirectories("new")
            case .removeFromRoot:
                try RootScanMarkerTests.remove(tree.path("d"))
            case .renameInRoot:
                try FileManager.default.moveItem(atPath: tree.path("d"), toPath: tree.path("renamed"))
            case .addToFirstLevel:
                try tree.makeDirectories("a/new")
            case .removeFromFirstLevel:
                try RootScanMarkerTests.remove(tree.path("a/b"))
            case .addFileToFirstLevel:
                try tree.makeFiles("a/new.txt")
            }
        }
    }

    @Test("ルートと depth 未満のディレクトリの直下の追加・削除・改名を検知する", arguments: ListedDirectoryChange.allCases)
    func detectsChangesInListedDirectories(change: ListedDirectoryChange) throws {
        try tree.makeDirectories("a/b", "d")
        let marker = try marker(depth: 2)

        try change.apply(to: tree)

        #expect(marker.hasChanges())
    }

    @Test("depth 未満のディレクトリの権限が変わったら変更ありとする（読めなくなると候補が変わるため）")
    func detectsPermissionChange() throws {
        try tree.makeDirectories("a/b")
        let marker = try marker(depth: 2)
        let locked = tree.path("a")

        try FileTreeFixture.setPermissions(FileTreeFixture.noPermissions, atPath: locked)
        defer { try? FileTreeFixture.setPermissions(FileTreeFixture.ownerAllPermissions, atPath: locked) }

        #expect(marker.hasChanges())
    }

    @Test("ルートが消えたら変更ありとする")
    func detectsRemovedRoot() throws {
        try tree.makeDirectories("a")
        let marker = try marker()

        try Self.remove(tree.root)

        #expect(marker.hasChanges())
    }

    @Test("ルートがシンボリックリンクなら、リンク先の直下の変化を検知する")
    func followsSymbolicLinkRoot() throws {
        try tree.makeDirectories("a")
        let linkedRoot = tree.outsidePath("linked-root")
        try FileTreeFixture.makeSymbolicLink(atPath: linkedRoot, to: tree.root)
        let marker = try marker(root: linkedRoot)
        #expect(!marker.hasChanges())

        try tree.makeDirectories("a/new")

        #expect(marker.hasChanges())
    }

    // MARK: - 候補に影響しない変化

    /// 走査で中身を読まないディレクトリ（候補に影響しない）への変更
    enum UnlistedDirectoryChange: CaseIterable, CustomTestStringConvertible {
        case insideDepthLevel
        case insideIgnored
        case insideHidden
        case insidePackage
        case insideLinkTarget

        var testDescription: String {
            switch self {
            case .insideDepthLevel: "depth の階層のディレクトリの中"
            case .insideIgnored: "除外（ignore）したディレクトリの中"
            case .insideHidden: "隠しディレクトリの中"
            case .insidePackage: "パッケージの中"
            case .insideLinkTarget: "シンボリックリンクのリンク先の中"
            }
        }

        func apply(to tree: FileTreeFixture) throws {
            switch self {
            case .insideDepthLevel:
                try tree.makeDirectories("a/b/new")
            case .insideIgnored:
                try tree.makeDirectories("node_modules/new")
            case .insideHidden:
                try tree.makeDirectories(".hidden/new")
            case .insidePackage:
                try tree.makeDirectories("Tool.app/Contents/new")
            case .insideLinkTarget:
                try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("target/new"))
            }
        }
    }

    @Test("走査で中身を読まないディレクトリの中の変化は変更なしとする", arguments: UnlistedDirectoryChange.allCases)
    func ignoresChangesOutsideListedDirectories(change: UnlistedDirectoryChange) throws {
        try tree.makeDirectories("a/b", "node_modules/x", ".hidden/x", "Tool.app/Contents")
        try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("target"))
        try tree.makeSymbolicLink("link", to: tree.outsidePath("target"))
        let marker = try marker(depth: 2)
        let before = try trackedScan(depth: 2).snapshot

        try change.apply(to: tree)

        #expect(!marker.hasChanges())
        // 変更なしと判定したときは、走査し直しても同じ候補になる
        #expect(try trackedScan(depth: 2).snapshot.itemSet == before.itemSet)
    }

    // MARK: - 記録するディレクトリ

    @Test(
        "記録するのは中身を読んだディレクトリ（ルートと depth 未満の各ディレクトリ）だけ",
        arguments: zip([0, 1, 2, 3], [[""], [""], ["", "a", "d"], ["", "a", "a/b", "d", "d/e"]])
    )
    func recordsOnlyListedDirectories(depth: Int, expectedRelativePaths: [String]) throws {
        try tree.makeDirectories("a/b/c", "d/e", "node_modules/x", ".hidden/y", "Tool.app/Contents")
        try tree.makeFiles("f.txt")
        try FileTreeFixture.makeDirectory(atPath: tree.outsidePath("target"))
        try tree.makeSymbolicLink("link", to: tree.outsidePath("target"))

        let marker = try marker(depth: depth)

        #expect(marker.directoryCount == expectedRelativePaths.count)
    }

    @Test("ルートを走査できないとき（存在しない・ディレクトリでない）は記録を作らない")
    func noMarkerForUnavailableRoot() throws {
        try tree.makeFiles("file.txt")

        #expect(try trackedScan(root: tree.path("missing")).marker == nil)
        #expect(try trackedScan(root: tree.path("file.txt")).marker == nil)
    }

    @Test("上限で打ち切った走査でも記録を作り、読んだディレクトリの変化を検知する")
    func truncatedScanIsTracked() throws {
        try tree.makeDirectories("a/x", "a/y", "b/x", "b/y")
        let result = try trackedScan(depth: 2, itemLimit: 3)
        let marker = try #require(result.marker)
        #expect(result.snapshot.warnings == [.rootTruncated(root: tree.root, limit: 3)])
        #expect(!marker.hasChanges())

        try tree.makeDirectories("c")

        #expect(marker.hasChanges())
    }
}
