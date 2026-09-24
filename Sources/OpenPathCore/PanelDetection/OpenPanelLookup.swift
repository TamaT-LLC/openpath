/// ウィンドウの中で見つけた NSOpenPanel。
public struct LocatedOpenPanel<Node> {
    /// パネルの要素（ダイアログのウィンドウ、またはウィンドウの子のシート）。
    public let element: Node
    /// `frame` は AX の座標系（左上原点）のまま。NSScreen の座標系への変換は PanelWatcher 側（OpenPathMac の PanelScanner）で行う。
    public let context: PanelContext
    /// 選択モードの推定結果と、推定に使った行の内訳。`context.isDirectoriesOnly` の元になった値で、
    /// 推定できなかった（`.undetermined`）かファイルも選べる（`.filesSelectable`）か、推定できなかった理由を
    /// ログで見分けるために持つ。
    public let selectionEstimate: PanelSelectionEstimate
    /// この呼び出しで判定した（キャッシュを使わなかった）か。判定のコストをログに残すために使う。
    public let isNewlyClassified: Bool

    /// 選択モードの推定結果。
    public var selectionMode: PanelSelectionMode {
        selectionEstimate.mode
    }

    public init(element: Node, context: PanelContext, selectionEstimate: PanelSelectionEstimate, isNewlyClassified: Bool) {
        self.element = element
        self.context = context
        self.selectionEstimate = selectionEstimate
        self.isNewlyClassified = isNewlyClassified
    }
}

extension LocatedOpenPanel: Equatable where Node: Equatable {}

/// `OpenPanelLocator.locate(in:reader:now:)` の結果。
public enum OpenPanelLookup<Node> {
    /// NSOpenPanel を見つけた。
    case found(LocatedOpenPanel<Node>)
    /// ウィンドウとそのシートを読み切り、NSOpenPanel はなかった。
    case notFound
    /// AX の読み取りに失敗して判定できなかった。
    /// 一時的な失敗でパネルを消えたとみなさないよう、このウィンドウで直前に見つけたパネル（なければ nil）を引き継ぐ。
    case undetermined(lastKnown: LocatedOpenPanel<Node>?)

    /// PanelWatcher に渡すパネル。判定できなかった場合は直前の結果を使う。
    public var panel: LocatedOpenPanel<Node>? {
        switch self {
        case .found(let panel):
            panel
        case .notFound:
            nil
        case .undetermined(let lastKnown):
            lastKnown
        }
    }
}

extension OpenPanelLookup: Equatable where Node: Equatable {}
