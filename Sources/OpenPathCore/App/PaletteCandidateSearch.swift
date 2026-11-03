/// パレットの候補の引き方（`PaletteQuerySession.Search`）。
public enum PaletteCandidateSearch {
    /// CandidateIndex の結果をパレットの行にし、検索語がパスなら先頭に直接入力の行を加える。
    /// どちらも呼び出し元（MainActor）ではなく並行実行用のスレッドで動く。
    /// - Parameters:
    ///   - index: 候補の検索先。
    ///   - directPath: 検索語に打ったパスの扱い。
    public static func make(index: CandidateIndex, directPath: DirectPathEntry = DirectPathEntry()) -> PaletteQuerySession.Search {
        let contextual = makeContextual(index: index, directPath: directPath)
        return { text, directoriesOnly, limit in
            try await contextual(text, directoriesOnly, limit, nil)
        }
    }

    /// 呼び出し元アプリの履歴を加味して索引を検索する。直接入力の優先表示は通常検索と共通。
    public static func makeContextual(index: CandidateIndex, directPath: DirectPathEntry = DirectPathEntry()) -> PaletteQuerySession.ContextualSearch {
        { text, directoriesOnly, limit, applicationBundleID in
            let rows = try await index.query(
                text, directoriesOnly: directoriesOnly, limit: limit, applicationBundleID: applicationBundleID
            ).map(\.paletteRow)
            // 打鍵が続いて不要になった検索では、パスの存在確認（stat）まで進めない
            try Task.checkCancellation()
            var exactRow: PaletteRow?
            if let path = directPath.path(for: text) {
                exactRow = try await index.row(atPath: path)
            }
            try Task.checkCancellation()
            return directPath.merging(rows, query: text, directoriesOnly: directoriesOnly, limit: limit, exactRow: exactRow)
        }
    }
}
