import CoreGraphics
import Foundation

/// パネル判定が AX ツリーを読むための窓口（DSN-001 §2.2、§2.3）。
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

    // MARK: ファイル一覧の行（選択モードの推定、DSN-001 §2.3）

    /// `AXVisibleRows`。AXOutline / AXTable の表示中の行（上から順）。
    func visibleRows(of node: Node) throws -> [Node]
    /// `AXVisibleChildren`。AXList の表示中の項目（並び順どおり）。
    func visibleChildren(of node: Node) throws -> [Node]
    /// `AXColumns`。AXBrowser の列（左から順）。
    func columns(of node: Node) throws -> [Node]
    /// `AXTitleUIElement`。ファイル一覧の項目・セルから、名前の要素を引くのに使う。
    func titleElement(of node: Node) throws -> Node?
    /// `AXURL`。ファイル一覧の名前の要素が持つ、項目の URL。
    func url(of node: Node) throws -> URL?
    /// `AXEnabled`。
    func isEnabled(of node: Node) throws -> Bool?
    /// 文字列の先頭の文字色の不透明度（0〜1）。`AXAttributedStringForRange` の `AXForegroundColor` から読む。
    /// 文字列を持たない要素や、色の指定がない場合は nil。
    func textOpacity(of node: Node) throws -> Double?
    /// 配列の属性の要素数（`AXUIElementGetAttributeValueCount`）。属性を持たなければ 0。
    func itemCount(_ attribute: PanelTreeItemsAttribute, of node: Node) throws -> Int
    /// 配列の属性のうち range の範囲の要素（`AXUIElementCopyAttributeValues`）。要素数を超える分は切り詰める。
    /// フォルダの項目がすべて返る属性（`AXRows` / `AXChildren`）を、表示範囲の外の数件だけ読むのに使う。
    func items(_ attribute: PanelTreeItemsAttribute, of node: Node, in range: Range<Int>) throws -> [Node]
}

/// 表示範囲の外の要素も含む、行・項目の配列の属性（DSN-001 §2.3）。
public enum PanelTreeItemsAttribute: Hashable, Sendable {
    /// `AXRows`。AXOutline / AXTable の行（上から順）。
    case rows
    /// `AXChildren`。カラム表示の列の AXList の項目（並び順どおり）。
    case children
}

/// AX ツリーを読めなかった理由。
public enum PanelTreeReadError: Error, Equatable, Sendable {
    /// 要素が破棄された（AX の `invalidUIElement`）。
    case elementGone
    /// 一時的に読めなかった（応答のタイムアウトなど）。パネルかどうかは分からない。
    case unavailable
}
