import ApplicationServices

/// 属性の読み取り。いずれも AX のプロセス間呼び出しを伴うため `axQueue` 上で呼ぶこと。
extension AXUIElement {
    /// 属性値を CFTypeRef のまま取得する。
    /// - Throws: `AXElementError`。属性を持たない場合は `.attributeUnsupported` や `.noValue` など。
    public func copyAttributeValue(_ attribute: String) throws -> CFTypeRef {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else {
            throw AXElementError(code: result, target: attribute)
        }
        guard let value else {
            throw AXElementError(code: .noValue, target: attribute)
        }
        return value
    }

    /// 属性値を型付きで取得する。取得できない場合と型が一致しない場合は nil。
    ///
    /// 対応する型は `AXUIElement` / `[AXUIElement]` / `AXValue` / `CGPoint` / `CGSize` / `CGRect` と、
    /// `String` / `Bool` / `Int` / `[String]` など Foundation からブリッジされる値型。
    /// それ以外のクラス型（他の CF 型や `NSString` など）は型を安全に検査できないため常に nil。
    /// ```swift
    /// let subrole: String? = window.attr(kAXSubroleAttribute)
    /// ```
    public func attr<T>(_ attribute: String) -> T? {
        guard let value = try? copyAttributeValue(attribute) else { return nil }
        return AXAttributeCast.cast(value, to: T.self)
    }

    /// `AXRole`（例: `AXButton`）。
    public var role: String? {
        attr(kAXRoleAttribute)
    }

    /// `AXSubrole`（例: `AXDialog`, `AXSheet`）。
    public var subrole: String? {
        attr(kAXSubroleAttribute)
    }

    /// `AXTitle`。ボタンのラベルやウィンドウタイトル。
    public var title: String? {
        attr(kAXTitleAttribute)
    }

    /// 直下の子要素。取得できない場合は空。
    public var children: [AXUIElement] {
        attr(kAXChildrenAttribute) ?? []
    }
}
