import ApplicationServices

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
}
