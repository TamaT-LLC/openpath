/// 設定したパス自身だけを候補にする。配下を走査せず、種別は既存のパネル用判定に合わせる。
public struct FavoriteCandidateSource: CandidateSource {
    public let kind = CandidateSourceKind.favorites
    private let favorites: [Favorite]

    public init(favorites: [Favorite]) {
        self.favorites = favorites
    }

    /// 不存在のパスを飛ばし、通常ファイル・パッケージをファイルとして返す。MainActor の外で呼ぶ。
    public func snapshot() async throws -> CandidateSourceSnapshot {
        var items: [SourceItem] = []
        for favorite in favorites {
            try Task.checkCancellation()
            guard let kind = FileSystemItemKind.ofItem(atPath: favorite.path) else { continue }
            items.append(SourceItem(path: favorite.path, isDirectory: kind == .directory, displayName: favorite.name))
        }
        return CandidateSourceSnapshot(items: items)
    }
}
