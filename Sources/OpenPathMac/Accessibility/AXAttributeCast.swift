import ApplicationServices

/// AX 属性値（CFTypeRef）から Swift の型への安全な変換。
///
/// Swift の `as?` は CF 型（`AXUIElement` など）への変換を実行時に検査せず常に成功させるため、
/// 文字列が `AXUIElement` として返るといった取り違えが起こる。CF 型は CFTypeID を照合してから変換する。
enum AXAttributeCast {
    /// 対応する型:
    /// - `AXUIElement` / `[AXUIElement]` / `AXValue`: CFTypeID を照合する
    /// - `CGPoint` / `CGSize` / `CGRect`: `AXValue` の中身の種類を照合して取り出す
    /// - `String` / `Bool` / `Int` / `[String]` など Foundation からブリッジされる値型: 実行時に検査される `as?` で変換する
    /// 上記以外のクラス型（他の CF 型や `NSString` など）は安全に検査できないため nil を返す。
    static func cast<T>(_ value: CFTypeRef, to type: T.Type) -> T? {
        if type == AXUIElement.self {
            return castCFType(value, typeID: AXUIElementGetTypeID())
        }
        if type == [AXUIElement].self {
            return elements(from: value).flatMap { $0 as? T }
        }
        if type == AXValue.self {
            return castCFType(value, typeID: AXValueGetTypeID())
        }
        if type == CGPoint.self {
            return unwrap(value, as: .cgPoint, initial: CGPoint.zero).flatMap { $0 as? T }
        }
        if type == CGSize.self {
            return unwrap(value, as: .cgSize, initial: CGSize.zero).flatMap { $0 as? T }
        }
        if type == CGRect.self {
            return unwrap(value, as: .cgRect, initial: CGRect.zero).flatMap { $0 as? T }
        }
        if isUncheckableClassType(type) {
            return nil
        }
        return value as? T
    }

    private static func castCFType<U>(_ value: CFTypeRef, typeID: CFTypeID) -> U? {
        guard CFGetTypeID(value) == typeID else { return nil }
        return value as? U
    }

    /// 要素が 1 つでも AXUIElement でなければ配列全体を不一致とみなす。
    private static func elements(from value: CFTypeRef) -> [AXUIElement]? {
        guard CFGetTypeID(value) == CFArrayGetTypeID(), let items = value as? [AnyObject] else { return nil }
        var elements: [AXUIElement] = []
        elements.reserveCapacity(items.count)
        for item in items {
            guard let element: AXUIElement = castCFType(item, typeID: AXUIElementGetTypeID()) else { return nil }
            elements.append(element)
        }
        return elements
    }

    /// AXValueGetValue は中身をバイト列としてコピーするため、参照を含まない型に限定する。
    private static func unwrap<V: BitwiseCopyable>(_ value: CFTypeRef, as valueType: AXValueType, initial: V) -> V? {
        guard let axValue: AXValue = castCFType(value, typeID: AXValueGetTypeID()),
              AXValueGetType(axValue) == valueType else { return nil }
        var result = initial
        guard AXValueGetValue(axValue, valueType, &result) else { return nil }
        return result
    }

    /// CF 型は実行時に NSObject 派生のクラスとして見え ObjC のクラスと区別できないため、
    /// 明示的に対応したもの以外のクラス型はまとめて検査不能として扱う。
    private static func isUncheckableClassType<T>(_ type: T.Type) -> Bool {
        type is AnyObject.Type
    }
}
