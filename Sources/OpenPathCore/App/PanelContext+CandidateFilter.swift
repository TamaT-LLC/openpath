extension PanelContext {
    /// このパネルのパレットでディレクトリだけを候補にするか（FR-SOURCE-05、DSN-001 §2.3）。
    ///
    /// フォルダのみ選べると推定したパネルでは、ファイルを選んでも「開く」で確定できないため設定に関わらず除く。
    /// それ以外（ファイルも選べる・推定できない）は設定 include_files に従う。
    /// - Parameter includeFiles: 設定 include_files。設定ファイルの変更を反映するため、候補を引くたびに読んだ値を渡す。
    public func showsDirectoriesOnly(includeFiles: Bool) -> Bool {
        isDirectoriesOnly || !includeFiles
    }
}
