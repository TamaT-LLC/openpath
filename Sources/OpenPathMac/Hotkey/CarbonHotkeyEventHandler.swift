import Carbon.HIToolbox

import OpenPathCore

/// Carbon のホットキー押下イベント（kEventClassKeyboard / kEventHotKeyPressed）を受け取るハンドラ。
///
/// インスタンスが生きている間だけハンドラを登録し、deinit で RemoveEventHandler する。
/// C コールバックへは self を `Unmanaged.passUnretained` で渡す。passRetained だと RemoveEventHandler まで
/// 解放されず、所有者から手動で解除しない限り残り続けるため。解除後はコールバックが呼ばれないので、
/// 保持していない参照でも解放済みの self に触れることはない。
final class CarbonHotkeyEventHandler {
    /// 押下されたホットキーの ID を受け取り、自分のホットキーとして処理したら true を返す
    typealias PressHandler = @MainActor (EventHotKeyID) -> Bool

    /// InstallEventHandler に渡すイベント種別の数（kEventHotKeyPressed のみ）
    private static let eventTypeCount = 1

    private let onPress: PressHandler
    private var handlerRef: EventHandlerRef?

    /// main スレッドのイベントディスパッチャにハンドラを登録する。押下イベントは main スレッドで配送される。
    @MainActor
    init(onPress: @escaping PressHandler) throws(HotkeyRegistrationError) {
        self.onPress = onPress
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyPressedCallback,
            Self.eventTypeCount,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard status == noErr else {
            throw .eventHandlerInstallationFailed(status: status)
        }
    }

    deinit {
        guard let handlerRef else { return }
        RemoveEventHandler(handlerRef)
    }

    @MainActor
    fileprivate func handlePress(of hotKeyID: EventHotKeyID) -> Bool {
        onPress(hotKeyID)
    }
}

/// InstallEventHandler に渡す C コールバック。自分のホットキーでなければ eventNotHandledErr を返し、他のハンドラへ回す。
private func hotKeyPressedCallback(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }

    let handler = Unmanaged<CarbonHotkeyEventHandler>.fromOpaque(userData).takeUnretainedValue()
    // ハンドラは main スレッドのイベントディスパッチャに登録しているため、ここは main スレッドで呼ばれる
    let isHandled = MainActor.assumeIsolated {
        handler.handlePress(of: hotKeyID)
    }
    return isHandled ? noErr : OSStatus(eventNotHandledErr)
}
