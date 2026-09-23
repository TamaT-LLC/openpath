import Testing

import OpenPathCore

@Suite("HotkeyRegistrationController: 登録の差分判定とロールバック")
struct HotkeyRegistrationControllerTests {
    /// 既定のホットキー ctrl+shift+o
    static let defaultHotkey = Hotkey(key: .o, modifiers: [.control, .shift])
    static let otherHotkey = Hotkey(key: .p, modifiers: [.control, .option])
    static let conflict = HotkeyRegistrationError.alreadyRegistered

    let registrar = HotkeyRegistrarSpy()

    // MARK: - 初回の登録

    @Test("生成直後は何も登録しない")
    func startsUnregistered() {
        let controller = HotkeyRegistrationController(registrar: registrar)

        #expect(controller.activeHotkey == nil)
        #expect(registrar.calls.isEmpty)
    }

    @Test("初回の update で登録し、registered を返す")
    func registersOnFirstUpdate() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)

        let outcome = try controller.update(Self.defaultHotkey)

        #expect(outcome == .registered)
        #expect(controller.activeHotkey == Self.defaultHotkey)
        #expect(registrar.calls == [.register(Self.defaultHotkey)])
    }

    @Test("初回の登録に失敗したらエラーを投げ、未登録のままにする")
    func firstRegistrationFailureLeavesUnregistered() {
        registrar.failures[Self.defaultHotkey] = Self.conflict
        let controller = HotkeyRegistrationController(registrar: registrar)

        #expect(throws: Self.conflict) {
            try controller.update(Self.defaultHotkey)
        }
        #expect(controller.activeHotkey == nil)
        #expect(registrar.calls == [.register(Self.defaultHotkey)])
    }

    // MARK: - 変更への追従

    @Test("登録中と同じホットキーなら再登録せず、unchanged を返す")
    func ignoresSameHotkey() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        registrar.resetCalls()

        let outcome = try controller.update(Self.defaultHotkey)

        #expect(outcome == .unchanged)
        #expect(controller.activeHotkey == Self.defaultHotkey)
        #expect(registrar.calls.isEmpty)
    }

    @Test("別のホットキーは新しい方を先に登録し、成功してから以前の登録を解除する")
    func replacesWithNewHotkeyBeforeUnregisteringPrevious() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        registrar.resetCalls()

        let outcome = try controller.update(Self.otherHotkey)

        #expect(outcome == .registered)
        #expect(controller.activeHotkey == Self.otherHotkey)
        // 1 番目のハンドルが既定のホットキーの登録
        #expect(registrar.calls == [.register(Self.otherHotkey), .unregister(handle: 1)])
    }

    @Test("変更後にさらに変更すると、直前に登録したものを解除する")
    func unregistersLatestRegistrationOnSecondChange() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        try controller.update(Self.otherHotkey)
        registrar.resetCalls()

        try controller.update(Self.defaultHotkey)

        #expect(controller.activeHotkey == Self.defaultHotkey)
        // 2 番目のハンドルが otherHotkey の登録
        #expect(registrar.calls == [.register(Self.defaultHotkey), .unregister(handle: 2)])
    }

    // MARK: - 変更時の登録失敗

    @Test("変更先の登録に失敗したらエラーを投げ、以前のホットキーを維持する")
    func keepsPreviousHotkeyWhenRegistrationFails() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        registrar.failures[Self.otherHotkey] = Self.conflict
        registrar.resetCalls()

        #expect(throws: Self.conflict) {
            try controller.update(Self.otherHotkey)
        }
        #expect(controller.activeHotkey == Self.defaultHotkey)
        #expect(registrar.calls == [.register(Self.otherHotkey)])
    }

    @Test("登録に失敗したホットキーは、同じ値の update でも登録を再試行する")
    func retriesFailedHotkeyOnNextUpdate() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        registrar.failures[Self.otherHotkey] = Self.conflict
        _ = try? controller.update(Self.otherHotkey)
        registrar.failures[Self.otherHotkey] = nil
        registrar.resetCalls()

        let outcome = try controller.update(Self.otherHotkey)

        #expect(outcome == .registered)
        #expect(controller.activeHotkey == Self.otherHotkey)
        #expect(registrar.calls == [.register(Self.otherHotkey), .unregister(handle: 1)])
    }

    @Test("登録失敗の後に維持中のホットキーへ戻す update は unchanged になる")
    func revertingToRetainedHotkeyIsUnchanged() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        registrar.failures[Self.otherHotkey] = Self.conflict
        _ = try? controller.update(Self.otherHotkey)
        registrar.resetCalls()

        let outcome = try controller.update(Self.defaultHotkey)

        #expect(outcome == .unchanged)
        #expect(registrar.calls.isEmpty)
    }

    // MARK: - 解除

    @Test("unregister で登録中のホットキーを解除する")
    func unregistersActiveHotkey() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        registrar.resetCalls()

        controller.unregister()

        #expect(controller.activeHotkey == nil)
        #expect(registrar.calls == [.unregister(handle: 1)])
    }

    @Test("未登録での unregister は何もしない")
    func unregisterWithoutRegistrationDoesNothing() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        controller.unregister()
        registrar.resetCalls()

        controller.unregister()

        #expect(registrar.calls.isEmpty)
    }

    @Test("unregister の後は、以前と同じホットキーでも登録し直す")
    func registersAgainAfterUnregister() throws {
        let controller = HotkeyRegistrationController(registrar: registrar)
        try controller.update(Self.defaultHotkey)
        controller.unregister()
        registrar.resetCalls()

        let outcome = try controller.update(Self.defaultHotkey)

        #expect(outcome == .registered)
        #expect(controller.activeHotkey == Self.defaultHotkey)
        #expect(registrar.calls == [.register(Self.defaultHotkey)])
    }
}
