/// メニューバーのアイコンの見た目。
public struct StatusIconState: Sendable, Equatable {
    /// 注意が必要な状態（権限なし・設定エラー）を知らせるバッジを付けるか（UX-001 §5）
    public let hasBadge: Bool
    /// 無効にしている間は薄く表示する
    public let isDimmed: Bool
    /// VoiceOver で読み上げるアイコンの説明。見た目の違い（バッジ・薄い表示）を言葉でも伝える
    public let accessibilityLabel: String

    init(hasBadge: Bool, isDimmed: Bool) {
        self.hasBadge = hasBadge
        self.isDimmed = isDimmed
        accessibilityLabel = Self.label(hasBadge: hasBadge, isDimmed: isDimmed)
    }

    private static func label(hasBadge: Bool, isDimmed: Bool) -> String {
        var qualifiers: [String] = []
        if isDimmed {
            qualifiers.append(StatusMenuText.disabledSuffix)
        }
        if hasBadge {
            qualifiers.append(StatusMenuText.attentionSuffix)
        }
        guard !qualifiers.isEmpty else { return AppInfo.name }
        return "\(AppInfo.name)（\(qualifiers.joined(separator: StatusMenuText.labelSeparator))）"
    }
}
