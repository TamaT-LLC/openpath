/// ホットキーを登録できなかった理由。
public enum HotkeyRegistrationError: Error, Equatable, Sendable {
    /// 同じ組み合わせがすでに登録されている（Carbon の eventHotKeyExistsErr）。
    /// 非排他の登録では他アプリとの重複はエラーにならないため、主にこのプロセス内での重複で起きる。
    case alreadyRegistered
    /// 押下イベントを受け取るハンドラを登録できなかった（InstallEventHandler の OSStatus）
    case eventHandlerInstallationFailed(status: Int32)
    /// その他の理由で OS が登録を拒否した（RegisterEventHotKey の OSStatus）
    case rejected(status: Int32)

    /// Carbon の eventHotKeyExistsErr。Core は Carbon を import しないため値で持ち、テストで Carbon の定数と突き合わせる
    private static let hotKeyExistsStatus: Int32 = -9878

    /// RegisterEventHotKey が返した noErr 以外の OSStatus から変換する。
    public init(registrationStatus status: Int32) {
        self = status == Self.hotKeyExistsStatus ? .alreadyRegistered : .rejected(status: status)
    }
}

extension HotkeyRegistrationError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .alreadyRegistered: "同じホットキーがすでに登録されています"
        case .eventHandlerInstallationFailed(let status): "ホットキーの押下を受け取るハンドラを登録できませんでした（OSStatus \(status)）"
        case .rejected(let status): "ホットキーを登録できませんでした（OSStatus \(status)）"
        }
    }
}
