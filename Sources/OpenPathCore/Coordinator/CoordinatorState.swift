/// AppCoordinator の状態（ARCH-001 §5: Idle → PanelShown → Injecting → Idle）。
public enum CoordinatorState: Equatable, Sendable {
    /// パネルを追跡していない。
    case idle
    /// パネル検知済み。isPaletteVisible が false なのは Esc でパレットのみ閉じた状態で、ホットキーで再表示できる。
    case panelShown(PanelContext, isPaletteVisible: Bool)
    /// パネルへパスを注入中。パレットの入力はロックする。
    case injecting(PanelContext, path: String)
}
