import ApplicationServices

/// AX API の呼び出し失敗。
/// `AXError` をそのまま保持し、呼び出し側が種類ごとに扱えるようにする（例: `.apiDisabled` は権限なし）。
public struct AXElementError: Error, Equatable, CustomStringConvertible {
    /// AX API が返したエラーコード。
    public let code: AXError
    /// 失敗した操作の対象（属性名やアクション名）。
    public let target: String?

    public init(code: AXError, target: String? = nil) {
        self.code = code
        self.target = target
    }

    public var description: String {
        let targetDescription = target.map { ", target: \($0)" } ?? ""
        return "AX 呼び出しに失敗しました (\(Self.name(of: code)): \(code.rawValue)\(targetDescription))"
    }

    /// ログで原因を追えるよう、コードを `kAXError` 定数の名前に対応させる。
    private static func name(of code: AXError) -> String {
        switch code {
        case .success: "success"
        case .failure: "failure"
        case .illegalArgument: "illegalArgument"
        case .invalidUIElement: "invalidUIElement"
        case .invalidUIElementObserver: "invalidUIElementObserver"
        case .cannotComplete: "cannotComplete"
        case .attributeUnsupported: "attributeUnsupported"
        case .actionUnsupported: "actionUnsupported"
        case .notificationUnsupported: "notificationUnsupported"
        case .notImplemented: "notImplemented"
        case .notificationAlreadyRegistered: "notificationAlreadyRegistered"
        case .notificationNotRegistered: "notificationNotRegistered"
        case .apiDisabled: "apiDisabled"
        case .noValue: "noValue"
        case .parameterizedAttributeUnsupported: "parameterizedAttributeUnsupported"
        case .notEnoughPrecision: "notEnoughPrecision"
        @unknown default: "unknown"
        }
    }
}
