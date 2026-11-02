extension PaletteViewModel {
    /// キー操作（`PaletteKeyBinding` の結果）を適用し、外（AppCoordinator）へ伝えるイベントがあれば返す。
    ///
    /// ロック中（注入中）はどの操作も適用しない。キー処理側でも捨てているが、
    /// ロックの切り替わりとキー入力が前後した場合に注入中のパスや検索語を変えないよう、ここでも守る。
    /// - Parameter isDirectory: 種別判定の差し替え。既定では候補取得時の種別を使い、キー操作で同期 I/O を行わない。
    public func perform(
        _ action: PaletteAction,
        isDirectory: ((String) -> Bool)? = nil
    ) -> PaletteEvent? {
        guard !isLocked else { return nil }
        switch action {
        case .moveSelection(let offset):
            moveSelection(by: offset)
            return nil
        case .confirm(let openImmediately):
            return selectedRow.map { .confirm(path: $0.path, openImmediately: openImmediately) }
        case .expandSelection:
            if let row = selectedRow {
                let directory = isDirectory?(row.path) ?? row.isDirectory
                let previousDirectory = expandedDirectory
                expandedDirectory = directory ? row.path : nil
                let expandedQuery = PaletteQueryExpansion.query(expanding: row.path, isDirectory: directory)
                if query == expandedQuery, previousDirectory != expandedDirectory {
                    onQueryChange?(query)
                } else {
                    query = expandedQuery
                }
            }
            return nil
        case .dismiss:
            // 検索語と選択は保ち、ホットキーで再表示したときに続きから操作できるようにする
            return .dismiss
        }
    }
}
