import ApplicationServices
import Foundation

import OpenPathCore

/// `PanelTreeReader` の AX 実装。AX のプロセス間呼び出しを伴うため axQueue 上で使うこと。
///
/// AX のエラーを判定に必要な 3 つに分ける:
/// - 属性を持たない（`noValue` / `attributeUnsupported`）: nil
/// - 要素が破棄された（`invalidUIElement`）: `PanelTreeReadError.elementGone`
/// - それ以外（応答のタイムアウトの `cannotComplete` など）: `PanelTreeReadError.unavailable`
final class AXPanelTreeReader: PanelTreeReader {
    /// 1 回の AX 呼び出しを待つ上限（秒）。
    /// 応答しないアプリで既定（約 6 秒）まで axQueue を止めると、注入の AX 呼び出しまで待たされるため短くする。
    /// タイムアウトは要素の参照ごとの設定で子要素には引き継がれないため、読み取った子要素にもそれぞれ設定する。
    private static let messagingTimeoutSeconds: Float = 0.25
    /// 文字色を読む範囲の長さ。先頭の 1 文字だけ読む
    private static let textStyleSampleLength = 1
    private static let foregroundColorKey = NSAttributedString.Key(
        kAXForegroundColorTextAttribute.takeUnretainedValue() as String
    )

    /// この読み手で行った AX 呼び出しの回数。DSN-001 §5 の上限（1 パネルあたり 50 回）を確かめるためにログへ出す。
    private(set) var callCount = 0

    /// 設定はプロセス内で完結し AX の往復を伴わないため、要素ごとに設定しても呼び出し回数は増えない。
    static func limitingMessagingTimeout(_ element: AXUIElement) -> AXUIElement {
        _ = AXUIElementSetMessagingTimeout(element, messagingTimeoutSeconds)
        return element
    }

    func role(of node: AXUIElement) throws -> String? {
        try value(kAXRoleAttribute, of: node, as: String.self)
    }

    func subrole(of node: AXUIElement) throws -> String? {
        try value(kAXSubroleAttribute, of: node, as: String.self)
    }

    func title(of node: AXUIElement) throws -> String? {
        try value(kAXTitleAttribute, of: node, as: String.self)
    }

    func accessibilityDescription(of node: AXUIElement) throws -> String? {
        try value(kAXDescriptionAttribute, of: node, as: String.self)
    }

    func identifier(of node: AXUIElement) throws -> String? {
        try value(kAXIdentifierAttribute, of: node, as: String.self)
    }

    func children(of node: AXUIElement) throws -> [AXUIElement] {
        let children = try value(kAXChildrenAttribute, of: node, as: [AXUIElement].self) ?? []
        return children.map(Self.limitingMessagingTimeout)
    }

    func frame(of node: AXUIElement) throws -> CGRect? {
        guard let origin = try value(kAXPositionAttribute, of: node, as: CGPoint.self),
              let size = try value(kAXSizeAttribute, of: node, as: CGSize.self) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    func visibleRows(of node: AXUIElement) throws -> [AXUIElement] {
        try elements(kAXVisibleRowsAttribute, of: node)
    }

    func visibleChildren(of node: AXUIElement) throws -> [AXUIElement] {
        try elements(kAXVisibleChildrenAttribute, of: node)
    }

    func columns(of node: AXUIElement) throws -> [AXUIElement] {
        try elements(kAXColumnsAttribute, of: node)
    }

    func titleElement(of node: AXUIElement) throws -> AXUIElement? {
        try value(kAXTitleUIElementAttribute, of: node, as: AXUIElement.self).map(Self.limitingMessagingTimeout)
    }

    func url(of node: AXUIElement) throws -> URL? {
        try value(kAXURLAttribute, of: node, as: URL.self)
    }

    func isEnabled(of node: AXUIElement) throws -> Bool? {
        try value(kAXEnabledAttribute, of: node, as: Bool.self)
    }

    /// 先頭の 1 文字の属性付き文字列から文字色を読む。色は文字列全体で同じため、1 文字で足りる。
    func textOpacity(of node: AXUIElement) throws -> Double? {
        var range = CFRange(location: 0, length: Self.textStyleSampleLength)
        guard let rangeValue = AXValueCreate(.cfRange, &range),
              let attributed = try parameterizedValue(
                  kAXAttributedStringForRangeParameterizedAttribute,
                  parameter: rangeValue,
                  of: node
              ),
              let string: NSAttributedString = Self.castCFType(attributed, typeID: CFAttributedStringGetTypeID()),
              string.length > 0,
              let colorValue = string.attribute(Self.foregroundColorKey, at: 0, effectiveRange: nil),
              let color: CGColor = Self.castCFType(colorValue as CFTypeRef, typeID: CGColor.typeID) else {
            return nil
        }
        return Double(color.alpha)
    }

    func itemCount(_ attribute: PanelTreeItemsAttribute, of node: AXUIElement) throws -> Int {
        callCount += 1
        var count: CFIndex = 0
        let result = AXUIElementGetAttributeValueCount(node, Self.name(of: attribute) as CFString, &count)
        switch result {
        case .success:
            return max(0, count)
        case .noValue, .attributeUnsupported:
            return 0
        case .invalidUIElement:
            throw PanelTreeReadError.elementGone
        default:
            throw PanelTreeReadError.unavailable
        }
    }

    /// フォルダの項目がすべて返る属性でも、range の分だけをプロセス間で受け渡す。
    /// 要素数を超える範囲（読んでいる間に項目が減った場合など）は、AX が切り詰めるか `illegalArgument` を返すため、空にする。
    func items(_ attribute: PanelTreeItemsAttribute, of node: AXUIElement, in range: Range<Int>) throws -> [AXUIElement] {
        guard !range.isEmpty, range.lowerBound >= 0 else { return [] }
        callCount += 1
        var values: CFArray?
        let result = AXUIElementCopyAttributeValues(
            node,
            Self.name(of: attribute) as CFString,
            range.lowerBound,
            range.count,
            &values
        )
        switch result {
        case .success:
            let elements = values.flatMap { AXAttributeCast.cast($0, to: [AXUIElement].self) } ?? []
            return elements.map(Self.limitingMessagingTimeout)
        case .noValue, .attributeUnsupported, .illegalArgument:
            return []
        case .invalidUIElement:
            throw PanelTreeReadError.elementGone
        default:
            throw PanelTreeReadError.unavailable
        }
    }

    private static func name(of attribute: PanelTreeItemsAttribute) -> String {
        switch attribute {
        case .rows:
            kAXRowsAttribute
        case .children:
            kAXChildrenAttribute
        }
    }

    /// 要素の配列の属性。読み取った要素にもメッセージングのタイムアウトを設定する。
    private func elements(_ attribute: String, of node: AXUIElement) throws -> [AXUIElement] {
        let elements = try value(attribute, of: node, as: [AXUIElement].self) ?? []
        return elements.map(Self.limitingMessagingTimeout)
    }

    /// 型が一致しない値は、属性を持たないものとして nil にする。
    private func value<T>(_ attribute: String, of node: AXUIElement, as type: T.Type) throws -> T? {
        callCount += 1
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(node, attribute as CFString, &value)
        switch result {
        case .success:
            return value.flatMap { AXAttributeCast.cast($0, to: type) }
        case .noValue, .attributeUnsupported:
            return nil
        case .invalidUIElement:
            throw PanelTreeReadError.elementGone
        default:
            throw PanelTreeReadError.unavailable
        }
    }

    /// パラメータ付きの属性。属性を持たない場合と、範囲が文字列の外の場合（空の文字列）は nil にする。
    private func parameterizedValue(_ attribute: String, parameter: CFTypeRef, of node: AXUIElement) throws -> CFTypeRef? {
        callCount += 1
        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(node, attribute as CFString, parameter, &value)
        switch result {
        case .success:
            return value
        case .noValue, .attributeUnsupported, .parameterizedAttributeUnsupported, .illegalArgument:
            return nil
        case .invalidUIElement:
            throw PanelTreeReadError.elementGone
        default:
            throw PanelTreeReadError.unavailable
        }
    }

    /// CF 型は `as?` が実行時に型を検査しないため、CFTypeID を照合してから変換する。
    private static func castCFType<T>(_ value: CFTypeRef, typeID: CFTypeID) -> T? {
        guard CFGetTypeID(value) == typeID else { return nil }
        return value as? T
    }
}
