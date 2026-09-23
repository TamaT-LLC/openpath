/// 登録中のホットキーを 1 つ保持し、設定の変更に合わせて差し替える。
///
/// 変更時は新しいホットキーを先に登録し、成功してから以前の登録を解除する。
/// 登録に失敗したら以前のホットキーを維持し、パレットを再表示する手段を失わないようにする。
/// 同じ値かどうかは登録中のホットキーと比べるため、失敗したホットキーは次の `update(_:)` で再試行される。
///
/// スレッド安全ではない。呼び出し元でスレッドを揃えること（Mac 層では MainActor から呼ぶ）。
public final class HotkeyRegistrationController<Registrar: HotkeyRegistering> {
    /// 現在登録中のホットキー。未登録なら nil。
    public var activeHotkey: Hotkey? {
        active?.hotkey
    }

    private let registrar: Registrar
    private var active: (hotkey: Hotkey, registration: Registrar.Registration)?

    public init(registrar: Registrar) {
        self.registrar = registrar
    }

    /// ホットキーを登録中のものと差し替える。
    /// - Returns: 登録中と同じで何もしなかった場合は `.unchanged`、新たに登録した場合は `.registered`。
    /// - Throws: 登録に失敗した場合。以前のホットキーは有効なまま（`activeHotkey` で確認できる）。
    @discardableResult
    public func update(_ hotkey: Hotkey) throws(HotkeyRegistrationError) -> HotkeyUpdateOutcome {
        guard hotkey != activeHotkey else { return .unchanged }

        let registration = try registrar.register(hotkey)
        if let previous = active {
            registrar.unregister(previous.registration)
        }
        active = (hotkey, registration)
        return .registered
    }

    /// 登録中のホットキーを解除する。未登録なら何もしない。
    public func unregister() {
        guard let previous = active else { return }
        active = nil
        registrar.unregister(previous.registration)
    }
}

/// `HotkeyRegistrationController.update(_:)` の結果。
public enum HotkeyUpdateOutcome: Equatable, Sendable {
    /// 登録中のホットキーと同じだったため、何もしなかった
    case unchanged
    /// 新たに登録した（以前の登録は解除済み）
    case registered
}
