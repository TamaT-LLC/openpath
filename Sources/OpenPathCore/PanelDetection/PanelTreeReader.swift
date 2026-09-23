import CoreGraphics

/// パネル判定が AX ツリーを読むための窓口（DSN-001 §2.2）。
///
/// 判定条件を AX から切り離し、ノードの型と属性の読み方を差し替えてユニットテストできるようにする。
/// OpenPathMac が `AXUIElement` で実装する。
///
/// 属性を持たない（AX の `noValue` / `attributeUnsupported`）場合は nil（子は空配列）を返す。
/// それ以外の失敗は `PanelTreeReadError` を投げ、「パネルではない」と「判定できなかった」を区別できるようにする。
public protocol PanelTreeReader {
    associatedtype Node

    /// `AXRole`（例: `AXButton`）。
    func role(of node: Node) throws -> String?
    /// `AXSubrole`（例: `AXDialog`）。
    func subrole(of node: Node) throws -> String?
    /// `AXTitle`。ボタンのラベルなど。
    func title(of node: Node) throws -> String?
    /// `AXDescription`。
    func accessibilityDescription(of node: Node) throws -> String?
    /// 直下の子要素（並び順どおり）。
    func children(of node: Node) throws -> [Node]
    /// 要素の矩形（`AXPosition` / `AXSize`）。AX の座標系（左上原点）のまま返す。
    func frame(of node: Node) throws -> CGRect?
}

/// AX ツリーを読めなかった理由。
public enum PanelTreeReadError: Error, Equatable, Sendable {
    /// 要素が破棄された（AX の `invalidUIElement`）。
    case elementGone
    /// 一時的に読めなかった（応答のタイムアウトなど）。パネルかどうかは分からない。
    case unavailable
}
