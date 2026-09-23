import Foundation
import Testing

import OpenPathCore

@Suite("RootDirectoryScanner: 上限・走査できないルート・キャンセル")
struct RootDirectoryScannerLimitTests {
    private static let smallLimit = 5
    private static let siblingCount = 10
    /// 走査開始時の 1 回目の確認より後、ルート配下を列挙している途中でキャンセル済みと答える回数
    private static let cancelDuringEnumerationAt = 3

    private let tree: FileTreeFixture

    init() throws {
        tree = try FileTreeFixture()
    }

    private func makeSiblings(count: Int) throws {
        for index in 0..<count {
            try tree.makeDirectories("dir\(index)")
        }
    }

    // MARK: - 件数の上限

    @Test("既定の上限は 1 ルートあたり 20,000 件")
    func defaultLimitIsTwentyThousand() {
        #expect(RootScanOptions.defaultItemLimit == 20_000)
        #expect(RootScanOptions().itemLimit == RootScanOptions.defaultItemLimit)
        #expect(RootScanOptions(config: .default).itemLimit == RootScanOptions.defaultItemLimit)
    }

    @Test("上限件数に達したら走査を打ち切り、上限件数だけ返して打ち切りの警告を付ける")
    func truncatesAtLimit() throws {
        try makeSiblings(count: Self.siblingCount)
        let options = RootScanOptions(depth: 1, itemLimit: Self.smallLimit)

        let snapshot = try RootDirectoryScanner(options: options).scan(root: tree.root)

        #expect(snapshot.items.count == Self.smallLimit)
        #expect(snapshot.items.first == .directory(tree.root))
        #expect(Set(snapshot.items).count == Self.smallLimit)
        #expect(snapshot.warnings == [.rootTruncated(root: tree.root, limit: Self.smallLimit)])
    }

    @Test("件数がちょうど上限なら打ち切りの警告を付けない（上限にはルート自身も数える）")
    func doesNotWarnWhenItemsFitExactly() throws {
        try makeSiblings(count: Self.smallLimit - 1)
        let options = RootScanOptions(depth: 1, itemLimit: Self.smallLimit)

        let snapshot = try RootDirectoryScanner(options: options).scan(root: tree.root)

        #expect(snapshot.items.count == Self.smallLimit)
        #expect(snapshot.warnings.isEmpty)
    }

    @Test("候補にならない項目（除外・隠し・ファイル）は上限に数えない")
    func countsOnlyReturnedItems() throws {
        try makeSiblings(count: Self.smallLimit - 1)
        try tree.makeDirectories("node_modules", ".hidden")
        try tree.makeFiles("a.txt", "b.txt")
        let options = RootScanOptions(depth: 1, includeFiles: false, itemLimit: Self.smallLimit)

        let snapshot = try RootDirectoryScanner(options: options).scan(root: tree.root)

        #expect(snapshot.items.count == Self.smallLimit)
        #expect(snapshot.warnings.isEmpty)
    }

    // MARK: - 走査できないルート

    @Test("存在しないルートはエラーにせず、空の候補と notFound の警告を返す")
    func missingRootIsSkipped() throws {
        let missing = tree.path("missing")

        let snapshot = try RootDirectoryScanner(options: RootScanOptions()).scan(root: missing)

        #expect(snapshot.items.isEmpty)
        #expect(snapshot.warnings == [.rootUnavailable(root: missing, reason: .notFound)])
    }

    @Test("ルートがファイルなら、空の候補と notDirectory の警告を返す")
    func fileRootIsSkipped() throws {
        try tree.makeFiles("file.txt")
        let fileRoot = tree.path("file.txt")

        let snapshot = try RootDirectoryScanner(options: RootScanOptions()).scan(root: fileRoot)

        #expect(snapshot.items.isEmpty)
        #expect(snapshot.warnings == [.rootUnavailable(root: fileRoot, reason: .notDirectory)])
    }

    @Test("読めないルートは、空の候補と unreadable の警告を返す")
    func unreadableRootIsSkipped() throws {
        try tree.makeDirectories("locked/inner")
        let locked = tree.path("locked")
        try FileTreeFixture.setPermissions(FileTreeFixture.noPermissions, atPath: locked)
        defer { try? FileTreeFixture.setPermissions(FileTreeFixture.ownerAllPermissions, atPath: locked) }

        let snapshot = try RootDirectoryScanner(options: RootScanOptions()).scan(root: locked)

        #expect(snapshot.items.isEmpty)
        #expect(snapshot.warnings == [.rootUnavailable(root: locked, reason: .unreadable)])
    }

    @Test("読めないサブディレクトリがあっても走査を続け、そのディレクトリ自身は候補に含める")
    func continuesPastUnreadableSubdirectory() throws {
        try tree.makeDirectories("locked/inner", "open/inner")
        let locked = tree.path("locked")
        try FileTreeFixture.setPermissions(FileTreeFixture.noPermissions, atPath: locked)
        defer { try? FileTreeFixture.setPermissions(FileTreeFixture.ownerAllPermissions, atPath: locked) }

        let snapshot = try RootDirectoryScanner(options: RootScanOptions(depth: 2)).scan(root: tree.root)

        #expect(snapshot.pathSet == [tree.root, locked, tree.path("open"), tree.path("open/inner")])
        #expect(snapshot.warnings.isEmpty)
    }

    // MARK: - キャンセル

    @Test("キャンセルされたタスクから走査すると CancellationError を投げる")
    func throwsWhenTaskIsCancelled() async throws {
        try makeSiblings(count: Self.siblingCount)
        let scanner = RootDirectoryScanner(options: RootScanOptions())
        let root = tree.root

        await #expect(throws: CancellationError.self) {
            try await CancelledTaskRunner.run { try scanner.scan(root: root) }
        }
    }

    @Test("列挙の途中でキャンセルされたら、残りを走査せず CancellationError を投げる")
    func throwsWhenCancelledDuringEnumeration() throws {
        try makeSiblings(count: Self.siblingCount)
        let trigger = CancelAfterChecks(threshold: Self.cancelDuringEnumerationAt)
        let scanner = RootDirectoryScanner(options: RootScanOptions()) { trigger.isCancelled() }

        #expect(throws: CancellationError.self) {
            try scanner.scan(root: tree.root)
        }
    }
}
