import Carbon.HIToolbox

import OpenPathCore

/// パレット再表示用のグローバルホットキー（FR-PALETTE-05, UX-001 §4）。
///
/// Carbon の RegisterEventHotKey で登録する。キー入力の監視（CGEventTap や NSEvent のグローバルモニタ）とは違い、
/// アクセシビリティ権限や入力監視の権限は不要。
/// 差し替えの方針（同じ値なら何もしない、新しい方を先に登録し、失敗したら以前のホットキーを維持する）は
/// OpenPathCore の `HotkeyRegistrationController` が持ち、そちらでテストしている。
@MainActor
public final class GlobalHotkey {
    /// 押下イベントの ID に入れる 4 文字コード（openpath）。同じイベントディスパッチャに届く他のホットキーと区別する
    private static let signatureCode = "OPth"
    private static let signature: OSType = signatureCode.utf8.reduce(0) { code, byte in
        code << UInt8.bitWidth | OSType(byte)
    }
    /// インスタンスごとに ID を変え、複数のインスタンスがあっても互いの押下を取り違えないようにする
    private static var nextInstanceID: UInt32 = 1

    /// 現在登録中のホットキー。未登録、または初回の登録に失敗した場合は nil。
    public var activeHotkey: Hotkey? {
        registrations.activeHotkey
    }

    private let onPress: @MainActor () -> Void
    private let hotKeyID: EventHotKeyID
    private let registrations: HotkeyRegistrationController<CarbonHotkeyRegistrar>
    private var eventHandler: CarbonHotkeyEventHandler?

    /// 生成時点では何も登録しない。`update(_:)` で登録する。
    /// - Parameter onPress: 登録中のホットキーが押されたときに main スレッドで呼ばれる。
    public init(onPress: @escaping @MainActor () -> Void) {
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: Self.nextInstanceID)
        Self.nextInstanceID &+= 1
        self.onPress = onPress
        self.hotKeyID = hotKeyID
        registrations = HotkeyRegistrationController(registrar: CarbonHotkeyRegistrar(hotKeyID: hotKeyID))
    }

    deinit {
        // ホットキーを先に解除する。押下イベントのハンドラは eventHandler の解放時に外れる
        registrations.unregister()
    }

    /// ホットキーを登録する。登録中と同じなら何もせず、違えば新しい方を登録してから以前の登録を解除する。
    /// - Returns: 何もしなかった場合は `.unchanged`、新たに登録した場合は `.registered`。
    /// - Throws: 登録に失敗した場合。以前のホットキーは有効なまま（`activeHotkey` で確認できる）。
    @discardableResult
    public func update(_ hotkey: Hotkey) throws(HotkeyRegistrationError) -> HotkeyUpdateOutcome {
        try installEventHandlerIfNeeded()
        return try registrations.update(hotkey)
    }

    /// 登録中のホットキーを解除する。未登録なら何もしない。
    public func unregister() {
        registrations.unregister()
    }

    private func installEventHandlerIfNeeded() throws(HotkeyRegistrationError) {
        guard eventHandler == nil else { return }
        eventHandler = try CarbonHotkeyEventHandler { [weak self] hotKeyID in
            self?.handlePress(of: hotKeyID) ?? false
        }
    }

    private func handlePress(of receivedID: EventHotKeyID) -> Bool {
        guard receivedID.signature == hotKeyID.signature, receivedID.id == hotKeyID.id else { return false }
        // 解除前にキューへ入った押下が解除後に配送されても反応しない
        guard activeHotkey != nil else { return false }
        onPress()
        return true
    }
}
