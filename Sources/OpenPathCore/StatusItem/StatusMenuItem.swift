/// メニューの 1 行。Mac 層はこの並びをそのまま NSMenu に反映する。
public enum StatusMenuEntry: Sendable, Equatable {
    /// 注意が必要な状態の説明。選ぶと原因の解消へ案内する
    case notice(StatusNotice)
    /// 操作の項目
    case command(StatusMenuItem)
    case separator
}

/// チェック項目の表示。
public enum StatusMenuCheckState: Sendable, Equatable {
    case off
    case on
    /// 途中の状態（ログイン時に起動の承認待ち）
    case mixed
}

/// 操作の項目の表示内容。
public struct StatusMenuItem: Sendable, Equatable {
    public let command: StatusMenuCommand
    public let title: String
    /// ⌘ と組み合わせるキー。無ければ空文字
    public let keyEquivalent: String
    /// チェック項目でなければ nil
    public let checkState: StatusMenuCheckState?
    /// 選べるか
    public let isEnabled: Bool
    /// 補足（選べない理由など）。無ければ nil
    public let toolTip: String?

    init(
        command: StatusMenuCommand,
        checkState: StatusMenuCheckState? = nil,
        isEnabled: Bool = true,
        toolTip: String? = nil
    ) {
        self.command = command
        title = command.title
        keyEquivalent = command.keyEquivalent
        self.checkState = checkState
        self.isEnabled = isEnabled
        self.toolTip = toolTip
    }
}
