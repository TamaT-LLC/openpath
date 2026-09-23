extension PaletteViewModel {
    /// キー操作（`PaletteKeyBinding` の結果）を適用し、外（AppCoordinator）へ伝えるイベントがあれば返す。
    ///
    /// ロック中（注入中）はどの操作も適用しない。キー処理側でも捨てているが、
    /// ロックの切り替わりとキー入力が前後した場合に注入中のパスや検索語を変えないよう、ここでも守る。
    /// - Parameter isDirectory: Tab の展開で、選択中の候補がディレクトリかを判定する。テストで差し替える。
    public func perform(
        _ action: PaletteAction,
        isDirectory: (String) -> Bool = PaletteQueryExpansion.isExistingDirectory
    ) -> PaletteEvent? {
        guard !isLocked else { return nil }
        switch action {
        case .moveSelection(let offset):
            moveSelection(by: offset)
            return nil
        case .confirm(let openImmediately):
            return selectedRow.map { .confirm(path: $0.path, openImmediately: openImmediately) }
        case .expandSelection:
            if let path = selectedRow?.path {
                query = PaletteQueryExpansion.query(expanding: path, isDirectory: isDirectory(path))
            }
            return nil
        case .dismiss:
            // 検索語と選択は保ち、ホットキーで再表示したときに続きから操作できるようにする
            return .dismiss
        }
    }
}
