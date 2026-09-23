import AppKit

/// パレット用のフローティング NSPanel。
///
/// NSOpenPanel を出しているアプリ（ホスト）をアクティブのまま保つため、`.nonactivatingPanel` により
/// openpath 自身をアクティブ化せずにキーウィンドウ（キー入力の受け先）になれるようにする。
final class PalettePanel: NSPanel {
    private enum Constants {
        /// `.nonactivatingPanel` は生成後に styleMask へ足しても WindowServer 側に反映されないため、初期化時に渡す
        static let styleMask: NSWindow.StyleMask = [.borderless, .nonactivatingPanel]
        /// NSOpenPanel はモーダル実行時に modalPanel レベルで表示されるため、その 1 つ上に置いて前面に出す
        static let level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
        /// フルスクリーンのホストアプリ上にも出せるようにし、Mission Control や Cmd+` の巡回からは外す
        static let collectionBehavior: NSWindow.CollectionBehavior = [
            .moveToActiveSpace,
            .fullScreenAuxiliary,
            .transient,
            .ignoresCycle,
        ]
    }

    convenience init() {
        self.init(contentRect: .zero, styleMask: Constants.styleMask, backing: .buffered, defer: true)
        isFloatingPanel = true
        // isFloatingPanel は level を .floating に設定するため、その後で上書きする
        level = Constants.level
        collectionBehavior = Constants.collectionBehavior
        // openpath は常駐アプリで常に非アクティブのため、非アクティブ時に隠す既定動作を止める
        hidesOnDeactivate = false
        // パレットのどこをクリックしてもキーにする。候補行のクリック後に押した Enter が
        // NSOpenPanel の「開く」に届いて誤って確定するのを防ぐ
        becomesKeyOnlyIfNeeded = false
        isReleasedWhenClosed = false
        isMovable = false
        // 注入前に hide() した直後からホストへキー入力が戻るよう、表示・非表示のアニメーションを行わない
        animationBehavior = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
    }

    /// ボーダーレスのウィンドウは既定ではキーになれないため、検索フィールドへの文字入力用に許可する。
    override var canBecomeKey: Bool { true }

    /// メインウィンドウにはならない（ドキュメントを持つウィンドウではないため）。
    override var canBecomeMain: Bool { false }
}
