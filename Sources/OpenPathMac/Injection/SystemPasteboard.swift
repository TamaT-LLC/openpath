import AppKit

import OpenPathCore

/// `NSPasteboard` を注入用のペーストボードとして扱うアダプタ。
/// 退避・復元の判断（どの型を残すか、他者の書き込みを上書きしないか、機密の内容を戻さないか）は OpenPathCore の `PasteboardSwap` が持つ。
@MainActor
public final class SystemPasteboard: PasteboardAccessing {
    private let pasteboard: NSPasteboard

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int {
        pasteboard.changeCount
    }

    public var items: [any PasteboardItemReading] {
        (pasteboard.pasteboardItems ?? []).map(PasteboardItemReader.init)
    }

    public func replaceContents(with snapshot: PasteboardSnapshot) -> Bool {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return true }
        return pasteboard.writeObjects(snapshot.items.map(Self.makePasteboardItem))
    }

    private static func makePasteboardItem(from item: PasteboardSnapshot.Item) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        for representation in item.representations {
            // 一部の型を書けなくても、残りの型で元の内容にできるだけ近づけるため続ける
            _ = pasteboardItem.setData(representation.data, forType: NSPasteboard.PasteboardType(representation.type))
        }
        return pasteboardItem
    }
}

private struct PasteboardItemReader: PasteboardItemReading {
    let item: NSPasteboardItem

    var types: [String] {
        item.types.map(\.rawValue)
    }

    func data(forType type: String) -> Data? {
        item.data(forType: NSPasteboard.PasteboardType(type))
    }
}
