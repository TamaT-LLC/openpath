import CoreGraphics
import Foundation

import OpenPathCore

/// AX 要素の代わり。id で同一性を表す（AXUIElement の CFEqual に相当）。
struct StubElement: Hashable, CustomStringConvertible {
    let id: String

    init(_ id: String) {
        self.id = id
    }

    var description: String {
        id
    }
}

/// AX ツリーを組み立てるための値。`StubPanelTree` に登録すると id で引ける要素になる。
struct StubNode {
    /// 省略すると親の id と並び順から決める（"window/0/2" など）
    var id: String?
    var role: String?
    var subrole: String?
    var title: String?
    var description: String?
    var frame: CGRect?
    var children: [StubNode] = []
    /// `AXURL`
    var url: URL?
    /// `AXEnabled`
    var isEnabled: Bool?
    /// 名前の文字色の不透明度
    var textOpacity: Double?
    /// `AXTitleUIElement` の要素の id
    var titleElementID: String?
    /// `AXColumns` の要素の id（AXBrowser の列）
    var columnIDs: [String] = []
    /// 表示中とみなす先頭の行・項目の数（`AXVisibleRows` は AXRow の子、`AXVisibleChildren` は子のうち）。nil ならすべて表示中
    var visibleItemCount: Int?
}

/// AX ツリーのスタブ。読み取りを記録し、AX の往復回数や読んだ要素を検証できるようにする。
/// ノードの差し替え（`replace`）で、描画途中のパネルが完成する・シートが閉じる等の変化を再現する。
final class StubPanelTree: PanelTreeReader {
    private static let rowRole = "AXRow"

    enum Attribute: Hashable {
        case role, subrole, title, description, children, frame
        case visibleRows, visibleChildren, columns, titleElement, url, isEnabled, textOpacity
        /// `itemCount(_:of:)`（AXUIElementGetAttributeValueCount）
        case itemCount(PanelTreeItemsAttribute)
        /// `items(_:of:in:)`（AXUIElementCopyAttributeValues）
        case items(PanelTreeItemsAttribute)
    }

    struct Read: Hashable {
        let element: StubElement
        let attribute: Attribute
    }

    private struct Attributes {
        var role: String?
        var subrole: String?
        var title: String?
        var description: String?
        var frame: CGRect?
        var children: [StubElement]
        var url: URL?
        var isEnabled: Bool?
        var textOpacity: Double?
        var titleElement: StubElement?
        var columns: [StubElement]
        var visibleItemCount: Int?
    }

    private var attributes: [StubElement: Attributes] = [:]
    private(set) var reads: [Read] = []
    /// 要素ごとに、読み取りで投げるエラー。
    var failures: [StubElement: PanelTreeReadError] = [:]

    /// ルートの要素を登録する。子孫も含めて登録し、ルートの要素を返す。
    @discardableResult
    func add(_ node: StubNode) -> StubElement {
        register(node, defaultID: "root")
    }

    /// 同じ id の要素を差し替える（子孫も登録し直す）。
    @discardableResult
    func replace(_ node: StubNode) -> StubElement {
        add(node)
    }

    /// 要素の読み取り回数（属性を問わない）。
    func readCount(of element: StubElement) -> Int {
        reads.count(where: { $0.element == element })
    }

    func readCount(of attribute: Attribute) -> Int {
        reads.count(where: { $0.attribute == attribute })
    }

    /// 記録を残さずにロールを返す（検証用）。
    func storedRole(of element: StubElement) -> String? {
        attributes[element]?.role
    }

    /// 子孫の要素（記録を残さない）。
    func descendants(of element: StubElement) -> Set<StubElement> {
        var result: Set<StubElement> = []
        var pending = attributes[element]?.children ?? []
        while let next = pending.popLast() {
            guard result.insert(next).inserted else { continue }
            pending += attributes[next]?.children ?? []
        }
        return result
    }

    /// 読み取りの記録を消す。キャッシュが効いた後の読み取りだけを数えるために使う。
    func resetReads() {
        reads = []
    }

    // MARK: - PanelTreeReader

    func role(of node: StubElement) throws -> String? {
        try read(node, .role).role
    }

    func subrole(of node: StubElement) throws -> String? {
        try read(node, .subrole).subrole
    }

    func title(of node: StubElement) throws -> String? {
        try read(node, .title).title
    }

    func accessibilityDescription(of node: StubElement) throws -> String? {
        try read(node, .description).description
    }

    func children(of node: StubElement) throws -> [StubElement] {
        try read(node, .children).children
    }

    func frame(of node: StubElement) throws -> CGRect? {
        try read(node, .frame).frame
    }

    /// 表示中の行。スタブでは子のうちロールが AXRow のものを、先頭から `visibleItemCount` 行（nil ならすべて）表示中とみなす。
    func visibleRows(of node: StubElement) throws -> [StubElement] {
        let found = try read(node, .visibleRows)
        return Array(rows(in: found).prefix(found.visibleItemCount ?? .max))
    }

    /// 表示中の項目。スタブでは子を、先頭から `visibleItemCount` 個（nil ならすべて）表示中とみなす。
    func visibleChildren(of node: StubElement) throws -> [StubElement] {
        let found = try read(node, .visibleChildren)
        return Array(found.children.prefix(found.visibleItemCount ?? .max))
    }

    func columns(of node: StubElement) throws -> [StubElement] {
        try read(node, .columns).columns
    }

    func titleElement(of node: StubElement) throws -> StubElement? {
        try read(node, .titleElement).titleElement
    }

    func url(of node: StubElement) throws -> URL? {
        try read(node, .url).url
    }

    func isEnabled(of node: StubElement) throws -> Bool? {
        try read(node, .isEnabled).isEnabled
    }

    func textOpacity(of node: StubElement) throws -> Double? {
        try read(node, .textOpacity).textOpacity
    }

    func itemCount(_ attribute: PanelTreeItemsAttribute, of node: StubElement) throws -> Int {
        items(attribute, in: try read(node, .itemCount(attribute))).count
    }

    /// 要素数を超える範囲は切り詰める（AXUIElementCopyAttributeValues と同じ）。
    func items(_ attribute: PanelTreeItemsAttribute, of node: StubElement, in range: Range<Int>) throws -> [StubElement] {
        let all = items(attribute, in: try read(node, .items(attribute)))
        return Array(all[range.clamped(to: all.indices)])
    }

    // MARK: - 内部

    /// 子のうちロールが AXRow のもの（`AXRows`）。
    private func rows(in found: Attributes) -> [StubElement] {
        found.children.filter { attributes[$0]?.role == Self.rowRole }
    }

    private func items(_ attribute: PanelTreeItemsAttribute, in found: Attributes) -> [StubElement] {
        switch attribute {
        case .rows:
            rows(in: found)
        case .children:
            found.children
        }
    }

    private func read(_ element: StubElement, _ attribute: Attribute) throws -> Attributes {
        reads.append(Read(element: element, attribute: attribute))
        if let failure = failures[element] {
            throw failure
        }
        // 登録されていない要素は破棄済みとして扱う
        guard let found = attributes[element] else {
            throw PanelTreeReadError.elementGone
        }
        return found
    }

    private func register(_ node: StubNode, defaultID: String) -> StubElement {
        let element = StubElement(node.id ?? defaultID)
        let children = node.children.enumerated().map { index, child in
            register(child, defaultID: "\(element.id)/\(index)")
        }
        attributes[element] = Attributes(
            role: node.role,
            subrole: node.subrole,
            title: node.title,
            description: node.description,
            frame: node.frame,
            children: children,
            url: node.url,
            isEnabled: node.isEnabled,
            textOpacity: node.textOpacity,
            titleElement: node.titleElementID.map(StubElement.init),
            columns: node.columnIDs.map(StubElement.init),
            visibleItemCount: node.visibleItemCount
        )
        return element
    }
}
