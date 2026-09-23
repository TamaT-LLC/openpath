import CoreGraphics

/// 検知した NSOpenPanel の情報。
/// Core をテスト可能な純 Swift に保つため、AX の型は持ち込まず値だけを持つ。
public struct PanelContext: Identifiable, Equatable, Sendable {
    /// パネルの識別子。同じパネルの再検知（AXObserver とポーリングの重複等）を見分けるために使う。
    /// 値の作り方は PanelWatcher 側で決める。
    public struct ID: Hashable, Sendable, RawRepresentable {
        public let rawValue: String

        public init(rawValue: String) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    /// フォルダのみ選択できるパネルと推定されたか（DSN-001 §2.3）。
    /// false（推定できない場合を含む）のときは設定 include_files に従う。
    public let isDirectoriesOnly: Bool
    /// パネルの矩形。パレットの配置に使う。
    /// NSScreen の座標系（プライマリ画面の左下原点、y 上向き）で持ち、`PalettePlacement` / `PaletteWindow.show(near:)` に
    /// そのまま渡せる。AX の座標系（左上原点）からの変換は PanelWatcher 側で済ませておく（DSN-001 §2.4）。
    public let frame: CGRect
    /// 選択モードの推定を後で推定し直す予定か（一覧の行をまだ読めなかった。DSN-001 §2.3）。
    /// true の間は、PanelWatcher がパレットの表示中も走査を続け、推定し直した結果を `panelContextChanged` で知らせる。
    public let isSelectionModeProvisional: Bool

    public init(id: ID, isDirectoriesOnly: Bool, frame: CGRect, isSelectionModeProvisional: Bool = false) {
        self.id = id
        self.isDirectoriesOnly = isDirectoriesOnly
        self.frame = frame
        self.isSelectionModeProvisional = isSelectionModeProvisional
    }

    /// 矩形だけを差し替えたもの（AX 座標から NSScreen 座標への変換に使う）。
    public func withFrame(_ frame: CGRect) -> PanelContext {
        PanelContext(
            id: id,
            isDirectoriesOnly: isDirectoriesOnly,
            frame: frame,
            isSelectionModeProvisional: isSelectionModeProvisional
        )
    }
}
