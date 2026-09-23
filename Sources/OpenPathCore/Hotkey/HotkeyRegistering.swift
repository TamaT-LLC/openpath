/// ホットキーを OS に登録・解除する処理の抽象。
/// Mac 層の Carbon アダプタが実装し、テストでは OS に触れない偽物に差し替える。
public protocol HotkeyRegistering {
    /// 登録の解除に使うハンドル（Carbon では EventHotKeyRef）
    associatedtype Registration

    /// ホットキーを登録する。登録済みの他のホットキーには影響しないこと。
    func register(_ hotkey: Hotkey) throws(HotkeyRegistrationError) -> Registration

    /// `register(_:)` で得た登録を解除する。
    func unregister(_ registration: Registration)
}
