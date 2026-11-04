import CoreGraphics

public enum PanelKind: Equatable, Sendable {
    case open
    case save
}

/// 検知したファイルパネルの情報。
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

    public let kind: PanelKind
    public let id: ID
    /// パネルを呼び出したアプリ。AX 要素の所属する XPC サービスではなく、観測していたアプリの ID。
    public let callingApplicationBundleID: String?
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

    public init(
        id: ID, isDirectoriesOnly: Bool, frame: CGRect, isSelectionModeProvisional: Bool = false,
        kind: PanelKind = .open, callingApplicationBundleID: String? = nil
    ) {
        self.kind = kind
        self.id = id
        self.callingApplicationBundleID = Self.historyApplicationID(callingApplicationBundleID)
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
            isSelectionModeProvisional: isSelectionModeProvisional,
            kind: kind,
            callingApplicationBundleID: callingApplicationBundleID
        )
    }

    /// 走査対象のアプリを呼び出し元として付ける。検知した AX 要素の PID に依存しない。
    public func withCallingApplication(_ bundleID: String?) -> PanelContext {
        PanelContext(
            id: id, isDirectoriesOnly: isDirectoriesOnly, frame: frame,
            isSelectionModeProvisional: isSelectionModeProvisional, kind: kind,
            callingApplicationBundleID: bundleID
        )
    }

    /// 不明な ID と AppKit のパネルサービスは、アプリ別ではなく全体履歴だけに記録する。
    public static func historyApplicationID(_ bundleID: String?) -> String? {
        guard let bundleID, !bundleID.isEmpty, bundleID.utf8.count <= 255,
              !bundleID.contains(where: \.isWhitespace),
              !bundleID.hasPrefix("com.apple.appkit.xpc.openAndSavePanelService") else { return nil }
        return bundleID
    }
}
