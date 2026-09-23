import Foundation

/// 注入前のパスの正規化（DSN-001 §4）。
///
/// `~` / `~/...` をホームディレクトリで展開し、`.`・`..`・空要素・末尾の `/` を字句的に取り除く。
/// 結果は DSN-001 の `URL(fileURLWithPath:).standardizedFileURL.path` と正準等価になるが、次の理由で URL は使わない。
/// - URL は NFC のパスを NFD に変える。候補のパスは、ファイルシステムや ghq から得た表記のまま貼り付けたい
/// - URL は `~` を実行中のユーザーのホームで展開し、相対パスをカレントディレクトリで絶対パスにする（純粋関数にならない）
///
/// シンボリックリンクは解決しない（ghq のリンク運用を壊さないため）。末尾の `/` は付けない（⌘⇧G は無くても移動できる）。
public struct InjectionPathNormalizer: Sendable {
    private let resolver: RootPathResolver

    /// - Parameter homeDirectory: `~` の展開先。テストでは任意のパスを注入する。
    public init(homeDirectory: String = NSHomeDirectory()) {
        resolver = RootPathResolver(homeDirectory: homeDirectory)
    }

    /// 絶対パスに解決できないもの（相対パス、`~user` 形式）は、推測で別の場所を指さないようそのまま返す。
    public func normalize(_ path: String) -> String {
        resolver.resolve(path) ?? path
    }
}
