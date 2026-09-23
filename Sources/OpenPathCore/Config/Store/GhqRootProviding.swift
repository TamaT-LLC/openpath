/// 既定の config.toml を生成するときに roots へ含める ghq root の取得元（UX-001 §7）。
/// テストで ghq を実行せずに済むよう抽象化する。
public protocol GhqRootProviding: Sendable {
    /// `ghq root` の結果。ghq が無効・未インストール・失敗のときは nil
    func root() async -> String?
}

extension GhqRepositoryLister: GhqRootProviding {}
