import Carbon.HIToolbox

import OpenPathCore

/// Carbon の RegisterEventHotKey / UnregisterEventHotKey の薄いアダプタ。
/// 差し替えの方針は `HotkeyRegistrationController` が持ち、ここでは OS の呼び出しと OSStatus の変換だけを行う。
struct CarbonHotkeyRegistrar: HotkeyRegistering {
    /// 押下イベントの direct object として届く ID。自分のホットキーかの判定に使う
    let hotKeyID: EventHotKeyID

    /// 排他登録（kEventHotKeyExclusive）は同じホットキーを登録した他アプリへの通知を止めてしまうため、非排他で登録する
    private static let registrationOptions = OptionBits(kEventHotKeyNoOptions)

    func register(_ hotkey: Hotkey) throws(HotkeyRegistrationError) -> EventHotKeyRef {
        var hotKeyRef: EventHotKeyRef?
        // Hotkey の keyCode / modifiers は Carbon の kVK_* / 修飾キーのビットと同じ値なので変換せずに渡す
        let status = RegisterEventHotKey(
            hotkey.keyCode,
            hotkey.modifiers.rawValue,
            hotKeyID,
            GetEventDispatcherTarget(),
            Self.registrationOptions,
            &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw HotkeyRegistrationError(registrationStatus: status)
        }
        return hotKeyRef
    }

    func unregister(_ registration: EventHotKeyRef) {
        // 失敗するのは不正な参照を渡した場合のみで、Controller は登録済みの参照しか渡さない
        // TODO(#3): Log が main に入ったら、noErr 以外を警告ログに出す
        _ = UnregisterEventHotKey(registration)
    }
}
