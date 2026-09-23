import Testing

import OpenPathCore

@Suite("PasteboardSwap: 注入中のペーストボードの差し替えと復元")
@MainActor
struct PasteboardSwapTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let japanesePath = "/Users/me/Documents/資料"

    @Test("元の内容を退避してから、パスを書き込む")
    func replacesContentsWithPath() throws {
        let pasteboard = FakePasteboard(contents: .userClipboard)

        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.japanesePath)

        #expect(swap.original == .userClipboard)
        #expect(pasteboard.contents == .transientText(Self.japanesePath))
    }

    @Test("復元すると、元の全アイテム・全型の内容に戻る")
    func restoresOriginalContents() throws {
        let pasteboard = FakePasteboard(contents: .userClipboard)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)

        let outcome = swap.restore()

        #expect(outcome == .restored)
        #expect(pasteboard.contents == .userClipboard)
    }

    @Test("元が空なら、パスを消して空に戻す")
    func restoresEmptyPasteboard() throws {
        let pasteboard = FakePasteboard(contents: .empty)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)

        let outcome = swap.restore()

        #expect(outcome == .restored)
        #expect(pasteboard.contents == .empty)
    }

    @Test("差し替えた後に他のアプリやユーザーが書き換えていたら、新しい内容を優先して戻さない")
    func doesNotOverwriteNewerContents() throws {
        let pasteboard = FakePasteboard(contents: .userClipboard)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        pasteboard.simulateExternalWrite(.newerUserCopy)

        let outcome = swap.restore()

        #expect(outcome == .skippedBecauseReplacedByOthers)
        #expect(pasteboard.contents == .newerUserCopy)
    }

    @Test("2 回目以降の復元は何もしない")
    func restoresOnlyOnce() throws {
        let pasteboard = FakePasteboard(contents: .userClipboard)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        swap.restore()
        let writeCountAfterFirstRestore = pasteboard.writes.count

        let outcome = swap.restore()

        #expect(outcome == .alreadyRestored)
        #expect(pasteboard.writes.count == writeCountAfterFirstRestore)
    }

    @Test("書き戻しに失敗したら failed を返す")
    func reportsRestoreFailure() throws {
        let pasteboard = FakePasteboard(contents: .userClipboard)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        pasteboard.remainingWriteFailures = 1

        #expect(swap.restore() == .failed)
    }

    @Test("パスを書き込めなければ、元の内容に戻してから writeFailed を投げる")
    func restoresOriginalWhenWriteFails() {
        let pasteboard = FakePasteboard(contents: .userClipboard)
        pasteboard.remainingWriteFailures = 1

        #expect(throws: PasteboardSwap.SwapError.writeFailed) {
            try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        }
        #expect(pasteboard.contents == .userClipboard)
    }
}
