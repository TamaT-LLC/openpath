import Foundation

/// パネルのファイル一覧から、選択モードの推定に使う行を読む（DSN-001 §2.3）。
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
/// AX の往復を抑えるため、次のようにする（読む項目の場所は `FileListItemSource`）:
/// - 表示中の行（AXVisibleRows / AXVisibleChildren）を先頭から読む
/// - 先頭の行がディレクトリばかりのときだけ、一覧の末尾の数行を範囲を指定して読む。フォルダの項目をすべて受け取らない
/// - ディレクトリの行は URL まで、ファイルの行は文字色（読めなければ AXEnabled）まで読む。アイコン表示では文字色を読まず AXEnabled を読む
/// - 選べるファイルの行が見つかったら推定が確定するため、以降の行は読まない
public enum FileListRowSampler {
    /// 選択モードの推定に使う行を読む。
    /// 1. 先頭の行: 表示中の行を先頭から最大 `PanelSelectionModeEstimator.sampledRowCount` 行（`sampleRows` と同じ）
    /// 2. 末尾の行: 先頭の行にディレクトリの行があり、ディレクトリ以外の行がないときだけ、一覧の末尾から最大
    ///    `PanelSelectionModeEstimator.trailingSampledRowCount` 行（先頭の行と重ならない範囲）。
    ///    「フォルダを先頭に表示」の並びやサブフォルダの多いフォルダでは、ファイルが表示範囲の外（一覧の末尾）に並ぶため（Issue #73）
    /// - Parameter role: fileList のロール（`sampleRows` と同じ）。
    /// - Throws: 読み取りに失敗したら `PanelTreeReadError`。
    public static func sample<Reader: PanelTreeReader>(
        in fileList: Reader.Node,
        role: String,
        reader: Reader
    ) throws -> FileListSample {
        let leadingLimit = PanelSelectionModeEstimator.sampledRowCount
        guard let source = try FileListItemSource(fileList: fileList, role: role, reader: reader, leadingLimit: leadingLimit) else {
            return FileListSample(leadingRows: [], trailingRows: [])
        }
        let leadingRows = try readRows(source.leadingItems.prefix(leadingLimit), layout: source.layout, reader: reader)
        guard needsTrailingRows(after: leadingRows) else {
            return FileListSample(leadingRows: leadingRows, trailingRows: [])
        }
        return FileListSample(leadingRows: leadingRows, trailingRows: trailingRows(of: source, after: leadingRows.count, reader: reader))
    }

    /// 末尾の行は、先頭の行で推定できなかったときの補いにすぎないため、読み取りに失敗したら読まなかったことにし、
    /// 先頭の行だけで推定する（表示範囲の外の要素が無効な実装でも、先頭の行を読めた結果を捨てない）。
    private static func trailingRows<Reader: PanelTreeReader>(
        of source: FileListItemSource<Reader.Node>,
        after leadingCount: Int,
        reader: Reader
    ) -> [FileListRow] {
        do {
            let items = try source.trailingItems(
                after: leadingCount,
                limit: PanelSelectionModeEstimator.trailingSampledRowCount,
                reader: reader
            )
            return try readRows(items, layout: source.layout, reader: reader)
        } catch {
            return []
        }
    }

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
        guard let source = try FileListItemSource(fileList: fileList, role: role, reader: reader, leadingLimit: limit) else {
            return []
        }
        return try readRows(source.leadingItems.prefix(limit), layout: source.layout, reader: reader)
    }

    /// 先頭の行がディレクトリばかりで、末尾の行も読む必要があるか。
    /// 行がない（空のフォルダ・読み込み前）か、ディレクトリ以外の行がある（推定できる、または選べるかを読めない）なら読まない。
    private static func needsTrailingRows(after leadingRows: [FileListRow]) -> Bool {
        leadingRows.contains { $0.isDirectory == true } && !leadingRows.contains { $0.isDirectory == false }
    }

    /// items を順に読む。選べるファイルの行が見つかったら、推定が確定するため以降の行は読まない。
    private static func readRows<Reader: PanelTreeReader>(
        _ items: some Sequence<Reader.Node>,
        layout: ItemLayout,
        reader: Reader
    ) throws -> [FileListRow] {
        var rows: [FileListRow] = []
        for item in items {
            let row = try readRow(item, layout: layout, reader: reader)
            rows.append(row)
            if row.isDirectory == false, row.isSelectable == true {
                break
            }
        }
        return rows
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
        if isDirectoryPath(url) {
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

    /// 名前の要素の AXURL がディレクトリを指すか（末尾が "/" か）。
    ///
    /// `URL.hasDirectoryPath` は使わない。Swift 6.2 系（macOS 27 の既定）の Foundation は、
    /// パスが Apple のファイル ID 参照の形式（`/.file/id=<番号>...`）に一致すると、URL の構築時に
    /// その番号をファイルシステムへ問い合わせて実在のパスへ解決しようとする。番号が実在しない
    /// （テストの二重体が使う架空の ID など）と解決に失敗し、URL がルート（`path` が `/`）や
    /// `com-apple-unresolvable-file-reference-url:` という不正な URL に化けてしまい、
    /// `hasDirectoryPath` が本来の値と無関係に `true` を返すようになる（ファイルの行が
    /// すべてディレクトリと誤判定される不具合の原因）。この問い合わせは OS やビルドによって
    /// 挙動が変わりうるため、文字列表現の末尾が "/" かを直接見て判定する
    /// （ファイル一覧の名前の要素の AXURL は、ディレクトリなら末尾が "/" になるとの前提は変わらない）。
    private static func isDirectoryPath(_ url: URL) -> Bool {
        url.absoluteString.hasSuffix("/")
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
