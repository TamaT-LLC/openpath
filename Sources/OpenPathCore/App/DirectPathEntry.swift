import Foundation

/// 検索語に打ったパスを、候補の先頭の行として出す（UX-001 §5「Tab でパスを直接入力」）。
///
/// roots・ghq・履歴のどれにも無い場所へも移動できるようにする。Tab でその行を展開すれば（末尾に `/`）、
/// 続けて配下の名前で絞り込める（PaletteQueryExpansion）。
/// - 対象は `/` か `~/` で始まり、末尾が `/` でない検索語。末尾が `/` の検索語は配下を掘っている途中とみなし、
///   選んだディレクトリ自身を候補から外す Tab の展開（#22）と揃えて行を出さない。
/// - パスは RootPathResolver で字句的に正規化する（シンボリックリンクは解決しない。候補の統合キーと同じ規則）。
/// - 存在し、ディレクトリに絞るときはディレクトリ（パッケージを除く）であるときだけ行にする。
///   存在の確認はファイルシステムを引くため、MainActor の外（候補の検索の中）で呼ぶこと。
public struct DirectPathEntry: Sendable {
    private static let absolutePathPrefix = "/"
    private static let homeRelativePathPrefix = "~/"
    private static let separator: Character = "/"

    private let resolver: RootPathResolver

    /// - Parameter homeDirectory: `~` の展開先。テストでは任意のパスを注入する。
    public init(homeDirectory: String = NSHomeDirectory()) {
        resolver = RootPathResolver(homeDirectory: homeDirectory)
    }

    /// 検索語が移動先として存在するパスなら、その行を返す。
    /// - Parameters:
    ///   - directoriesOnly: true ならファイル（パッケージを含む）では行を作らない。
    ///   - lastUsed: 行に出す最終使用日時（同じパスの候補が履歴にあれば、その値）。
    public func row(for query: String, directoriesOnly: Bool, lastUsed: Date? = nil) -> PaletteRow? {
        guard let path = path(for: query), let kind = FileSystemItemKind.ofItem(atPath: path) else { return nil }
        guard !directoriesOnly || kind == .directory else { return nil }
        return PaletteRow(name: CandidatePath.name(of: path), path: path, lastUsed: lastUsed)
    }

    /// 候補の先頭に直接入力の行を加える。同じパスの候補は除き（最終使用日時は引き継ぐ）、`limit` 件に収める。
    /// 検索語がパスでなければ、ファイルシステムを引かずに候補をそのまま返す。
    public func merging(_ rows: [PaletteRow], query: String, directoriesOnly: Bool, limit: Int) -> [PaletteRow] {
        guard let path = path(for: query) else { return rows }
        let lastUsed = rows.first { $0.path == path }?.lastUsed
        guard let directRow = row(for: query, directoriesOnly: directoriesOnly, lastUsed: lastUsed) else { return rows }
        return Array(([directRow] + rows.filter { $0.path != path }).prefix(limit))
    }

    /// 検索語を移動先のパスとして読めるときの、正規化した絶対パス。存在は確かめない。
    private func path(for query: String) -> String? {
        guard query.hasPrefix(Self.absolutePathPrefix) || query.hasPrefix(Self.homeRelativePathPrefix),
              query.last != Self.separator
        else {
            return nil
        }
        return resolver.resolve(query)
    }
}
