/// AppCoordinator がパレットのフッターに出す文言（UX-001 §5）。
public enum PaletteMessage {
    public static let injecting = "パネルへ移動中…"
    /// 失敗理由が分からないときの文言
    public static let injectionFailed = "移動できませんでした"
    /// AppCoordinator の全体タイムアウト（InjectionError.timeout(step: .overall)）の文言
    static let injectionTimedOut = injectionFailed(reason: "タイムアウト")

    static func injectionFailed(reason: String) -> String {
        "\(injectionFailed)（\(reason)）"
    }
}
