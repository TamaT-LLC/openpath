import Foundation
import Testing

import OpenPathCore

@Suite("PasteboardSnapshot: ペーストボードの退避")
@MainActor
struct PasteboardSnapshotTests {
    private static let plainTextType = "public.utf8-plain-text"
    private static let rtfType = "public.rtf"
    private static let pngType = "public.png"
    private static let lazyType = "com.example.lazy"
    private static let japanesePath = "/Users/me/Documents/資料"

    @Test("全アイテムを、アイテムの順と型の順を保ったまま型ごとの Data で退避する")
    func capturesAllItemsAndTypesInOrder() {
        let pasteboard = FakePasteboard(contents: .userClipboard)

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        #expect(snapshot == .userClipboard)
    }

    @Test("データを読み出せない型は書き戻せないため除く")
    func skipsUnreadableTypes() {
        let pasteboard = FakePasteboard(items: [[
            .init(type: Self.rtfType, data: Data("rtf".utf8)),
            .init(type: Self.lazyType, data: nil),
            .init(type: Self.plainTextType, data: Data("text".utf8)),
        ]])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        #expect(snapshot.items.map { $0.representations.map(\.type) } == [[Self.rtfType, Self.plainTextType]])
    }

    @Test("どの型も読み出せないアイテムは除く")
    func skipsItemsWithoutReadableData() {
        let pasteboard = FakePasteboard(items: [
            [.init(type: Self.lazyType, data: nil)],
            [.init(type: Self.pngType, data: Data([0x01]))],
        ])

        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        #expect(snapshot == PasteboardSnapshot(items: [
            .init(representations: [.init(type: Self.pngType, data: Data([0x01]))]),
        ]))
    }

    @Test("空のペーストボードは空のスナップショットになる")
    func capturesEmptyPasteboard() {
        let snapshot = PasteboardSnapshot.capture(from: FakePasteboard(contents: .empty))

        #expect(snapshot == .empty)
        #expect(snapshot.isEmpty)
    }

    @Test("注入用の文字列は UTF-8 の文字列型として書き、日本語もそのまま読み戻せる")
    func transientTextKeepsJapanesePath() throws {
        let snapshot = PasteboardSnapshot.transientText(Self.japanesePath)

        let item = try #require(snapshot.items.first)
        #expect(snapshot.items.count == 1)
        let text = try #require(item.representations.first { $0.type == PasteboardSnapshot.plainTextType })
        #expect(String(decoding: text.data, as: UTF8.self) == Self.japanesePath)
    }

    @Test("注入用の文字列にはクリップボード履歴アプリに記録させない印を付ける")
    func transientTextIsMarkedTransient() throws {
        let item = try #require(PasteboardSnapshot.transientText(Self.japanesePath).items.first)

        #expect(item.representations.map(\.type) == [PasteboardSnapshot.plainTextType, PasteboardSnapshot.transientMarkerType])
        #expect(PasteboardSnapshot.plainTextType == "public.utf8-plain-text")
        #expect(PasteboardSnapshot.transientMarkerType == "org.nspasteboard.TransientType")
    }
}
