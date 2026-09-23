import Foundation

/// パネルのファイル一覧から、選択モードの推定に使う先頭の行を読む（DSN-001 §2.3）。
///
/// NSOpenPanel のファイル一覧（FinderKit）の構造（macOS 26 で確認）:
/// - カラム表示（AXBrowser）: AXColumns（左の列から順）の最後の列が今のフォルダ。列（AXScrollArea）の子の AXList の項目
///   （AXGroup）の AXTitleUIElement が、名前の AXTextField。ファイルを選ぶと右にプレビューの列（AXList を持たない）が出る
/// - リスト表示（AXOutline）: 行（AXRow）の最初のセル（名前の列）の AXTitleUIElement が、名前の AXTextField。
///   並べ替えの見出しの行など、名前の要素を持たない行もある
/// - アイコン表示（AXList / AXCollectionList）: AXVisibleChildren がセクション（AXList / AXSectionList。グループ分けで複数になる）で、
///   セクションの AXVisibleChildren が項目（AXGroup）。項目は AXTitleUIElement を持たず、子の AXImage が AXURL と AXEnabled を持つ。
///   AXImage は文字列を持たないため文字色は読めないが、選べない項目は AXEnabled が false になる
/// - 名前の要素の AXURL（ファイル参照 URL）は、ディレクトリなら末尾が "/" になる
///
/// AX の往復を抑えるため、次のようにする:
/// - 表示中の行（AXVisibleRows / AXVisibleChildren）だけを先頭から読む。フォルダの項目がすべて返る AXChildren は使わない
/// - ディレクトリの行は URL まで、ファイルの行は文字色（読めなければ AXEnabled）まで読む。アイコン表示では文字色を読まず AXEnabled を読む
/// - 選べるファイルの行が見つかったら推定が確定するため、以降の行は読まない
public enum FileListRowSampler {
    private static let browserRole = "AXBrowser"
    private static let tableRoles: Set<String> = ["AXOutline", "AXTable"]
    /// カラム表示の列の中の一覧のロール
    private static let columnListRole = "AXList"
    /// カラム表示で今のフォルダの列を探す数。右端のプレビューの列の分だけ、最後から 2 列まで見る
    private static let browserColumnsToSearch = 2

    /// fileList の表示中の行を、先頭から最大 limit 行読む。
    /// - Parameter role: fileList のロール（`AXBrowser` / `AXOutline` / `AXTable`、アイコン表示の `AXList`）。
    ///   それ以外のロールでは何も読まない。`AXList` は、`OpenPanelClassifier` がアイコン表示（サブロールが AXCollectionList）と
    ///   確かめた一覧である前提で読む。
    /// - Throws: 読み取りに失敗したら `PanelTreeReadError`。
    public static func sampleRows<Reader: PanelTreeReader>(
        in fileList: Reader.Node,
        role: String,
        reader: Reader,
        limit: Int = PanelSelectionModeEstimator.sampledRowCount
    ) throws -> [FileListRow] {
        let limit = max(0, limit)
        let items: [Reader.Node]
        let layout: ItemLayout
        if role == browserRole {
            items = try currentFolderItems(inBrowser: fileList, reader: reader)
            layout = .browserItem
        } else if tableRoles.contains(role) {
            items = try reader.visibleRows(of: fileList)
            layout = .tableRow
        } else if role == OpenPanelCriteria.collectionListRole {
            items = try visibleItems(inIconView: fileList, reader: reader, limit: limit)
            layout = .iconItem
        } else {
            return []
        }

        var rows: [FileListRow] = []
        for item in items.prefix(limit) {
            let row = try readRow(item, layout: layout, reader: reader)
            rows.append(row)
            if row.isDirectory == false, row.isSelectable == true {
                break
            }
        }
        return rows
    }

    /// カラム表示の今のフォルダ（AXList を持つ最後の列）の、表示中の項目。
    private static func currentFolderItems<Reader: PanelTreeReader>(
        inBrowser browser: Reader.Node,
        reader: Reader
    ) throws -> [Reader.Node] {
        for column in try reader.columns(of: browser).reversed().prefix(browserColumnsToSearch) {
            for child in try reader.children(of: column) where try reader.role(of: child) == columnListRole {
                return try reader.visibleChildren(of: child)
            }
        }
        return []
    }

    /// アイコン表示の、セクションの順に並べた表示中の項目。limit 個の項目が集まったら、残りのセクションは読まない。
    private static func visibleItems<Reader: PanelTreeReader>(
        inIconView iconView: Reader.Node,
        reader: Reader,
        limit: Int
    ) throws -> [Reader.Node] {
        var items: [Reader.Node] = []
        for section in try reader.visibleChildren(of: iconView) {
            guard items.count < limit else { break }
            items += try reader.visibleChildren(of: section)
        }
        return items
    }

    /// 行を 1 つ読む。名前の要素や URL がなければ、種類の分からない行にする。
    private static func readRow<Reader: PanelTreeReader>(
        _ item: Reader.Node,
        layout: ItemLayout,
        reader: Reader
    ) throws -> FileListRow {
        guard let name = try nameElement(of: item, layout: layout, reader: reader),
              let url = try reader.url(of: name) else {
            return FileListRow(isDirectory: nil)
        }
        if url.hasDirectoryPath {
            return FileListRow(isDirectory: true)
        }
        if layout == .iconItem {
            // アイコン表示の AXImage は文字列を持たず文字色を読めないが、AXEnabled が選べるかをそのまま表す
            return FileListRow(isDirectory: false, isEnabled: try reader.isEnabled(of: name), isEnabledAuthoritative: true)
        }
        // FinderKit のリスト表示・カラム表示では AXEnabled が常に true で判断に使えないため、文字色を先に読む
        if let textOpacity = try reader.textOpacity(of: name) {
            return FileListRow(isDirectory: false, textOpacity: textOpacity)
        }
        return FileListRow(isDirectory: false, isEnabled: try reader.isEnabled(of: name))
    }

    private static func nameElement<Reader: PanelTreeReader>(
        of item: Reader.Node,
        layout: ItemLayout,
        reader: Reader
    ) throws -> Reader.Node? {
        switch layout {
        case .browserItem:
            return try reader.titleElement(of: item)
        case .tableRow:
            guard let nameCell = try reader.children(of: item).first else { return nil }
            return try reader.titleElement(of: nameCell)
        case .iconItem:
            return try reader.children(of: item).first
        }
    }
}

/// 行（項目）から名前の要素への辿り方。
private enum ItemLayout {
    /// カラム表示の項目: 項目の AXTitleUIElement
    case browserItem
    /// リスト表示の行: 最初のセルの AXTitleUIElement
    case tableRow
    /// アイコン表示の項目: 項目の最初の子（AXURL と AXEnabled を持つ AXImage）
    case iconItem
}
