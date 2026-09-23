extension PaletteRow {
    /// 候補とマッチ結果から行を作る。一致位置は、name にマッチした場合は表示名、path にマッチした場合はパスのハイライトにする。
    /// - Parameter match: 空クエリなどマッチを行っていない場合は nil（ハイライトなし）
    public init(candidate: Candidate, match: FuzzyCandidateMatch?) {
        let positions = match?.positions ?? []
        self.init(
            name: candidate.name,
            path: candidate.path,
            lastUsed: candidate.lastUsed,
            nameHighlights: match?.field == .name ? positions : [],
            pathHighlights: match?.field == .path ? positions : []
        )
    }
}
