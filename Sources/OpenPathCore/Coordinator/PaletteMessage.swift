/// AppCoordinator がパレットのフッターに出す文言（UX-001 §5）。
public enum PaletteMessage {
    public static let injecting = "パネルへ移動中…"
    /// 失敗理由が分からないときの文言
    public static let injectionFailed = "移動できませんでした"
    /// AppCoordinator の全体タイムアウト（InjectionError.timeout(step: .overall)）の文言
    static let injectionTimedOut = injectionFailed(reason: "タイムアウト")
    /// ペーストボードを戻せなかった（InjectionError.pasteboardRestoreFailed）ときの文言。
    /// パネルの移動は済んでいる場合があるため「移動できませんでした」とは言わず、ユーザーが気づくべきことだけを伝える。
    /// ユーザー向けには macOS の表示に合わせて「クリップボード」と呼ぶ。
    static let pasteboardRestoreFailed = "クリップボードを元に戻せませんでした"

    static func injectionFailed(reason: String) -> String {
        "\(injectionFailed)（\(reason)）"
    }
}
