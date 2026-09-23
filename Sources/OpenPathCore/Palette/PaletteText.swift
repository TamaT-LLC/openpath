/// パレットに固定で出す文言（UX-001 §3, §5）。
/// 注入中・注入失敗の文言は AppCoordinator が渡すため `PaletteMessage` 側にある。
public enum PaletteText {
    /// フッターのキー操作ヒント（UX-001 §3）
    public static let keyHints: [PaletteKeyHint] = [
        PaletteKeyHint(key: "↑↓", action: "選択"),
        PaletteKeyHint(key: "⏎", action: "移動"),
        PaletteKeyHint(key: "⌘⏎", action: "移動して開く"),
        PaletteKeyHint(key: "esc", action: "閉じる"),
    ]
    /// 候補ソースの構築中にフッターへ出す文言（UX-001 §5）
    public static let buildingCandidates = "候補を構築中…"
    /// 候補が 0 件のときにリストへ出す案内（UX-001 §5）
    public static let noMatches = "一致する候補がありません。Tab でパスを直接入力"
}

/// フッターに並べるキーとその操作。キーと説明で見た目を変えるため分けて持つ。
public struct PaletteKeyHint: Equatable, Sendable {
    public let key: String
    public let action: String

    public init(key: String, action: String) {
        self.key = key
        self.action = action
    }
}

/// フッターの状態表示（AppCoordinator の showStatus / showError に対応）。
public enum PaletteStatus: Equatable, Sendable {
    /// 通常の状態表示（例: 「パネルへ移動中…」）
    case info(String)
    /// 赤字で出すエラー（例: 「移動できませんでした（⌘⇧G が開きません）」）
    case error(String)
}

/// フッターに実際に出す内容。
public enum PaletteFooterContent: Equatable, Sendable {
    /// キー操作ヒント（`PaletteText.keyHints`）
    case keyHints
    case status(String)
    /// 赤字で出す
    case error(String)
}
