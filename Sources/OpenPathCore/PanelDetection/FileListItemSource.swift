/// ファイル一覧の中で、選択モードの推定に読む項目の場所（DSN-001 §2.3）。`FileListRowSampler` が使う。
///
/// - 先頭の項目: 表示中の項目（AXVisibleRows / AXVisibleChildren）。フォルダの項目がすべて返る AXChildren は使わない。
///   ただしカラム表示で今のフォルダの列に表示中の項目がなければ、列の先頭の項目を読む。ブラウザが今のフォルダの列まで
///   横にスクロールしていない（列が表示範囲の外にある）と、AXVisibleChildren が空になるため（macOS 27 のプロセス内のパネルで確認）
/// - 末尾の項目: 一覧の末尾から数件。AXRows / AXChildren の要素数を読み、末尾の範囲だけを読む（Issue #73）。
///   カラム表示とリスト表示だけ（表示範囲の外の行も読めることを macOS 27 のプロセス内のパネルで確認）
struct FileListItemSource<Node> {
    let layout: ItemLayout
    /// 先頭の行として読む項目（表示中の項目を先頭から）
    let leadingItems: [Node]
    /// 末尾の行を読む一覧。カラム表示は今のフォルダの列の AXList、リスト表示は AXOutline / AXTable（アイコン表示は読まない）
    private let list: Node

    /// fileList の先頭の項目を探す。ファイル一覧でないロールや、カラム表示で今のフォルダの列が見つからなければ nil。
    /// - Parameter leadingLimit: 先頭の行として読む最大の数。アイコン表示のセクションと、表示範囲の外の列の項目の読み取りを打ち切る。
    init?<Reader: PanelTreeReader>(
        fileList: Node,
        role: String,
        reader: Reader,
        leadingLimit: Int
    ) throws where Reader.Node == Node {
        if role == FileListRoles.browser {
            guard let list = try Self.currentFolderList(inBrowser: fileList, reader: reader) else { return nil }
            layout = .browserItem
            self.list = list
            let visible = try reader.visibleChildren(of: list)
            leadingItems = visible.isEmpty ? try reader.items(.children, of: list, in: 0..<leadingLimit) : visible
        } else if FileListRoles.tables.contains(role) {
            layout = .tableRow
            list = fileList
            leadingItems = try reader.visibleRows(of: fileList)
        } else if role == OpenPanelCriteria.collectionListRole {
            layout = .iconItem
            list = fileList
            leadingItems = try Self.visibleItems(inIconView: fileList, reader: reader, limit: leadingLimit)
        } else {
            return nil
        }
    }

    /// 一覧の末尾の最大 limit 個の項目。先頭の行として読んだ leadingCount 個とは重ならない範囲だけを返す
    /// （表示中の項目は一覧の先頭から並んでいる前提。スクロールされていて重なっても、推定の結果は変わらない）。
    ///
    /// アイコン表示では読まない（空を返す）。NSCollectionView は表示範囲の外の項目を実体化しておらず、
    /// セクションの要素数（AXUIElementGetAttributeValueCount）はフォルダの全項目を数えるが、範囲外の要素は読むと
    /// 無効な要素（invalidUIElement）になるため（macOS 27 のプロセス内のパネルで確認）。
    func trailingItems<Reader: PanelTreeReader>(
        after leadingCount: Int,
        limit: Int,
        reader: Reader
    ) throws -> [Node] where Reader.Node == Node {
        let attribute: PanelTreeItemsAttribute
        switch layout {
        case .browserItem:
            attribute = .children
        case .tableRow:
            attribute = .rows
        case .iconItem:
            return []
        }
        let count = try reader.itemCount(attribute, of: list)
        let start = max(count - max(0, limit), leadingCount)
        guard start < count else { return [] }
        return try reader.items(attribute, of: list, in: start..<count)
    }

    /// カラム表示の今のフォルダの列（AXList を持つ最後の列）の AXList。
    private static func currentFolderList<Reader: PanelTreeReader>(
        inBrowser browser: Node,
        reader: Reader
    ) throws -> Node? where Reader.Node == Node {
        for column in try reader.columns(of: browser).reversed().prefix(FileListRoles.browserColumnsToSearch) {
            for child in try reader.children(of: column) where try reader.role(of: child) == FileListRoles.columnList {
                return child
            }
        }
        return nil
    }

    /// アイコン表示の、セクションの順に並べた表示中の項目。limit 個の項目が集まったら、残りのセクションは読まない。
    private static func visibleItems<Reader: PanelTreeReader>(
        inIconView iconView: Node,
        reader: Reader,
        limit: Int
    ) throws -> [Node] where Reader.Node == Node {
        var items: [Node] = []
        for section in try reader.visibleChildren(of: iconView) {
            guard items.count < limit else { break }
            items += try reader.visibleChildren(of: section)
        }
        return items
    }
}

/// ファイル一覧のロール。ジェネリックな型は静的な格納プロパティを持てないため、別に置く。
private enum FileListRoles {
    static let browser = "AXBrowser"
    static let tables: Set<String> = ["AXOutline", "AXTable"]
    /// カラム表示の列の中の一覧のロール
    static let columnList = "AXList"
    /// カラム表示で今のフォルダの列を探す数。右端のプレビューの列の分だけ、最後から 2 列まで見る
    static let browserColumnsToSearch = 2
}

/// 行（項目）から名前の要素への辿り方。
enum ItemLayout {
    /// カラム表示の項目: 項目の AXTitleUIElement
    case browserItem
    /// リスト表示の行: 最初のセルの AXTitleUIElement
    case tableRow
    /// アイコン表示の項目: 項目の最初の子（AXURL と AXEnabled を持つ AXImage）
    case iconItem
}
