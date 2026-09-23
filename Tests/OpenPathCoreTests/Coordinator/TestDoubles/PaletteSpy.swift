import OpenPathCore

/// PaletteDisplaying への呼び出しを順番どおりに記録する。
@MainActor
final class PaletteSpy: PaletteDisplaying {
    enum Call: Equatable {
        case show(PanelContext)
        case hide
        case setLocked(Bool)
        case showStatus(String)
        case showError(String)
    }

    private(set) var calls: [Call] = []

    func show(context: PanelContext) {
        calls.append(.show(context))
    }

    func hide() {
        calls.append(.hide)
    }

    func setLocked(_ isLocked: Bool) {
        calls.append(.setLocked(isLocked))
    }

    func showStatus(_ message: String) {
        calls.append(.showStatus(message))
    }

    func showError(_ message: String) {
        calls.append(.showError(message))
    }
}
