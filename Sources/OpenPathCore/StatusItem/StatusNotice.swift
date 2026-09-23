/// アイコンにバッジを付ける原因と、その説明（UX-001 §5）。
/// メニューの先頭とツールチップに出し、メニューで選ぶと原因の解消へ案内する。
public struct StatusNotice: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// アクセシビリティ権限が未付与で、パネルの検知と注入が動かない
        case accessibilityPermissionMissing
        /// 設定ファイルを読み込めず、直前の有効な設定（または既定値）で動いている
        case configError
    }

    public let kind: Kind
    public let title: String
    public let detail: String
    /// 選んだときに行う操作
    public let command: StatusMenuCommand

    static let accessibilityPermissionMissing = StatusNotice(
        kind: .accessibilityPermissionMissing,
        title: StatusMenuText.permissionMissingTitle,
        detail: StatusMenuText.permissionMissingDetail,
        command: .openAccessibilitySettings
    )

    static func configError(_ error: ConfigStoreError) -> StatusNotice {
        StatusNotice(
            kind: .configError,
            title: StatusMenuText.configErrorTitle,
            detail: error.description,
            command: .openConfigFile
        )
    }
}
