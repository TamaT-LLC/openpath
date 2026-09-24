import Foundation

import OpenPathCore

/// NSPasteboard の振る舞い（書き込みのたびに消去して changeCount が進む）を再現するペーストボード。
@MainActor
final class FakePasteboard: PasteboardAccessing {
    /// アイテムが持つ型とデータ。data が nil の型は、提供元が応答せず読み出せない型を表す。
    struct Entry {
        let type: String
        let data: Data?
    }

    private struct Item: PasteboardItemReading {
        let entries: [Entry]
        let recordRead: @MainActor (String) -> Void

        var types: [String] {
            entries.map(\.type)
        }

        func data(forType type: String) -> Data? {
            recordRead(type)
            return entries.first { $0.type == type }?.data
        }
    }

    private var storedItems: [[Entry]]
    private(set) var changeCount = 0
    /// 成功した書き込みを発生順に記録する。
    private(set) var writes: [PasteboardSnapshot] = []
    /// この回数だけ、以降の書き込みを失敗させる。
    var remainingWriteFailures = 0
    /// 書き込みが成功するたびに呼ばれる。
    var onWrite: ((PasteboardSnapshot) -> Void)?
    /// データを読み出した型を発生順に記録する（機密の内容を読み出していないことの確認に使う）。
    private(set) var readTypes: [String] = []

    init(items: [[Entry]]) {
        storedItems = items
    }

    convenience init(contents: PasteboardSnapshot = .empty) {
        self.init(items: Self.entries(of: contents))
    }

    /// 現在の内容（読み出せない型は除く）。
    var contents: PasteboardSnapshot {
        PasteboardSnapshot(items: storedItems.map { entries in
            PasteboardSnapshot.Item(representations: entries.compactMap { entry in
                entry.data.map { PasteboardSnapshot.Representation(type: entry.type, data: $0) }
            })
        })
    }

    var items: [any PasteboardItemReading] {
        storedItems.map { entries in
            Item(entries: entries) { [weak self] type in
                self?.readTypes.append(type)
            }
        }
    }

    func replaceContents(with snapshot: PasteboardSnapshot) -> Bool {
        // NSPasteboard と同じく、書き込みの成否に関わらず先に消去され changeCount が進む
        changeCount += 1
        storedItems = []
        guard remainingWriteFailures == 0 else {
            remainingWriteFailures -= 1
            return false
        }
        storedItems = Self.entries(of: snapshot)
        writes.append(snapshot)
        onWrite?(snapshot)
        return true
    }

    /// 他のアプリ（またはユーザーのコピー）による書き込み。
    func simulateExternalWrite(_ snapshot: PasteboardSnapshot) {
        changeCount += 1
        storedItems = Self.entries(of: snapshot)
    }

    private static func entries(of snapshot: PasteboardSnapshot) -> [[Entry]] {
        snapshot.items.map { item in
            item.representations.map { Entry(type: $0.type, data: $0.data) }
        }
    }
}

extension PasteboardSnapshot {
    /// ユーザーが元々コピーしていた内容の例（リッチテキストと、その文字列表現の 2 アイテム）。
    static let userClipboard = PasteboardSnapshot(items: [
        Item(representations: [
            Representation(type: "public.rtf", data: Data("{\\rtf1 hello}".utf8)),
            Representation(type: "public.utf8-plain-text", data: Data("hello".utf8)),
        ]),
        Item(representations: [
            Representation(type: "public.png", data: Data([0x89, 0x50, 0x4E, 0x47])),
        ]),
    ])

    /// パスワードマネージャーがコピーした内容の例（nspasteboard.org の機密の印付き）。
    static let concealedPassword = PasteboardSnapshot(items: [
        Item(representations: [
            Representation(type: "public.utf8-plain-text", data: Data("correct horse battery staple".utf8)),
            Representation(type: "org.nspasteboard.ConcealedType", data: Data()),
        ]),
    ])

    /// 注入中にユーザーが新たにコピーした内容の例。
    static let newerUserCopy = PasteboardSnapshot(items: [
        Item(representations: [
            Representation(type: "public.utf8-plain-text", data: Data("copied during injection".utf8)),
        ]),
    ])
}
