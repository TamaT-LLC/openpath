import Foundation
import Testing

import OpenPathCore

@Suite("PasteboardSwap: 注入中のペーストボードの差し替えと復元")
@MainActor
struct PasteboardSwapTests {
    private static let path = "/Users/me/repos/github.com/TamaT-LLC/fern"
    private static let japanesePath = "/Users/me/Documents/資料"

    @Test("元の内容を全型読み出して退避してから、パスを書き込む")
    func replacesContentsWithPath() throws {
        let pasteboard = FakePasteboard(contents: .userClipboard)

        _ = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.japanesePath)

        #expect(pasteboard.readTypes == ["public.rtf", "public.utf8-plain-text", "public.png"])
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

    // MARK: - 機密の内容（org.nspasteboard.ConcealedType）

    @Test("元の内容が機密（パスワードマネージャー等）なら、書き戻さずに空にする")
    func clearsInsteadOfRestoringConcealedContents() throws {
        let pasteboard = FakePasteboard(contents: .concealedPassword)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)

        let outcome = swap.restore()

        #expect(outcome == .clearedBecauseConcealed)
        #expect(pasteboard.contents == .empty)
        #expect(pasteboard.writes == [.transientText(Self.path), .empty])
    }

    @Test("機密の印がどのアイテムにあっても、機密として扱う")
    func detectsConcealedMarkerInAnyItem() throws {
        let pasteboard = FakePasteboard(contents: PasteboardSnapshot(
            items: PasteboardSnapshot.userClipboard.items + PasteboardSnapshot.concealedPassword.items
        ))
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)

        #expect(swap.restore() == .clearedBecauseConcealed)
        #expect(pasteboard.contents == .empty)
    }

    @Test("機密の内容は、データを読み出さない（パスワードを複製して持たない）")
    func doesNotReadConcealedData() throws {
        let pasteboard = FakePasteboard(contents: .concealedPassword)

        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        swap.restore()

        #expect(pasteboard.readTypes.isEmpty)
    }

    @Test("機密の内容は、パスを書き込めなかったときも書き戻さない")
    func doesNotWriteBackConcealedContentsWhenWriteFails() {
        let pasteboard = FakePasteboard(contents: .concealedPassword)
        pasteboard.remainingWriteFailures = 1

        #expect(throws: PasteboardSwap.SwapError.writeFailed) {
            try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        }
        #expect(pasteboard.contents == .empty)
        #expect(pasteboard.writes.isEmpty)
    }

    @Test("機密の内容を空にする書き込みが失敗しても、失敗にはしない（利用者の内容は失われていない）")
    func clearingFailureIsNotRestoreFailure() throws {
        let pasteboard = FakePasteboard(contents: .concealedPassword)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        pasteboard.remainingWriteFailures = 1

        #expect(swap.restore() == .clearedBecauseConcealed)
    }

    @Test("元の内容が機密でも、差し替えた後に他者が書き換えていたら、新しい内容を残す")
    func keepsNewerContentsOverConcealedOriginal() throws {
        let pasteboard = FakePasteboard(contents: .concealedPassword)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        pasteboard.simulateExternalWrite(.newerUserCopy)

        let outcome = swap.restore()

        #expect(outcome == .skippedBecauseReplacedByOthers)
        #expect(pasteboard.contents == .newerUserCopy)
    }

    @Test("機密の内容でも、2 回目以降の復元は何もしない")
    func concealedRestoresOnlyOnce() throws {
        let pasteboard = FakePasteboard(contents: .concealedPassword)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)
        swap.restore()
        let writeCountAfterFirstRestore = pasteboard.writes.count

        #expect(swap.restore() == .alreadyRestored)
        #expect(pasteboard.writes.count == writeCountAfterFirstRestore)
    }

    @Test(
        "一時的な内容（TransientType）や自動生成の内容（AutoGeneratedType）は機密ではないため、従来どおり元に戻す",
        arguments: [PasteboardSnapshot.transientMarkerType, PasteboardSnapshot.autoGeneratedMarkerType]
    )
    func restoresNonConcealedMarkedContents(markerType: String) throws {
        let original = PasteboardSnapshot(items: [
            .init(representations: [
                .init(type: PasteboardSnapshot.plainTextType, data: Data("snippet".utf8)),
                .init(type: markerType, data: Data()),
            ]),
        ])
        let pasteboard = FakePasteboard(contents: original)
        let swap = try PasteboardSwap(replacingContentsOf: pasteboard, with: Self.path)

        #expect(swap.restore() == .restored)
        #expect(pasteboard.contents == original)
    }
}
