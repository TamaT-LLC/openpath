import Foundation

/// 注入前のパスの正規化（DSN-001 §4）。
///
/// `~` / `~/...` をホームディレクトリで展開し、`.`・`..`・空要素・末尾の `/` を字句的に取り除く。
/// 結果は DSN-001 の `URL(fileURLWithPath:).standardizedFileURL.path` と正準等価になるが、次の理由で URL は使わない。
/// - URL は NFC のパスを NFD に変える。候補のパスは、ファイルシステムや ghq から得た表記のまま貼り付けたい
/// - URL は `~` を実行中のユーザーのホームで展開し、相対パスをカレントディレクトリで絶対パスにする（純粋関数にならない）
///
/// シンボリックリンクは解決しない（ghq のリンク運用を壊さないため）。末尾の `/` は付けない（⌘⇧G は無くても移動できる）。
/// ただし移動先シートの値・候補と比べるとき（`isSameLocation`）は、macOS が `/private` の下へのシンボリックリンクとして持つ
/// `/tmp`・`/var`・`/etc` を、その実体と同じ場所とみなす（Issue #95）。
public struct InjectionPathNormalizer: Sendable {
    /// `/private` の下に実体があり、ルートからシンボリックリンクで指される（macOS で固定の）ディレクトリ。
    static let privateAliasedDirectories = ["tmp", "var", "etc"]
    private static let privatePrefix = "/private"

    private let resolver: RootPathResolver

    /// - Parameter homeDirectory: `~` の展開先。テストでは任意のパスを注入する。
    public init(homeDirectory: String = NSHomeDirectory()) {
        resolver = RootPathResolver(homeDirectory: homeDirectory)
    }

    /// 絶対パスに解決できないもの（相対パス、`~user` 形式）は、推測で別の場所を指さないようそのまま返す。
    public func normalize(_ path: String) -> String {
        resolver.resolve(path) ?? path
    }

    /// 2 つのパスが同じ場所を指すか。正規化してから比べ（String の == は正準等価で比べる）、
    /// `/private/tmp`・`/private/var`・`/private/etc` の下は `/tmp`・`/var`・`/etc` の下と同じとみなす。
    /// 移動先シートの候補リストは、`/tmp/…` の入力に実体の `/private/tmp/…` を示すため（Issue #95 の QA）。
    /// ファイルシステムは読まない（他のシンボリックリンクは解決しない。比べるときだけ使い、注入するパスは変えない）。
    public func isSameLocation(_ lhs: String, _ rhs: String) -> Bool {
        Self.removingPrivatePrefix(normalize(lhs)) == Self.removingPrivatePrefix(normalize(rhs))
    }

    /// `/private/tmp`・`/private/var`・`/private/etc`（とその下）を `/tmp`・`/var`・`/etc` に置き換える。それ以外はそのまま。
    private static func removingPrivatePrefix(_ path: String) -> String {
        guard path.hasPrefix(privatePrefix + "/") else { return path }
        let aliased = String(path.dropFirst(privatePrefix.count))
        let isAliased = privateAliasedDirectories.contains { directory in
            aliased == "/" + directory || aliased.hasPrefix("/" + directory + "/")
        }
        return isAliased ? aliased : path
    }
}
