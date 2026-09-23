import Carbon.HIToolbox
import Testing

import OpenPathCore

/// OpenPathCore は Carbon を import しないため、RegisterEventHotKey の OSStatus の解釈を Carbon の定数と突き合わせて保証する。
@Suite("HotkeyRegistrationError: RegisterEventHotKey の OSStatus の解釈")
struct HotkeyRegistrationErrorTests {
    @Test("eventHotKeyExistsErr は登録済み（alreadyRegistered）として扱う")
    func hotKeyExistsIsAlreadyRegistered() {
        let error = HotkeyRegistrationError(registrationStatus: OSStatus(eventHotKeyExistsErr))

        #expect(error == .alreadyRegistered)
    }

    @Test(
        "それ以外の OSStatus は値を保持して rejected として扱う",
        arguments: [OSStatus(eventHotKeyInvalidErr), OSStatus(paramErr), OSStatus(eventInternalErr)]
    )
    func otherStatusIsRejected(status: OSStatus) {
        let error = HotkeyRegistrationError(registrationStatus: status)

        #expect(error == .rejected(status: status))
    }

    @Test(
        "description はログに出せる説明で、OSStatus を含む場合はその値を示す",
        arguments: [
            (HotkeyRegistrationError.alreadyRegistered, "同じホットキーがすでに登録されています"),
            (.eventHandlerInstallationFailed(status: OSStatus(paramErr)), "ホットキーの押下を受け取るハンドラを登録できませんでした（OSStatus -50）"),
            (.rejected(status: OSStatus(eventInternalErr)), "ホットキーを登録できませんでした（OSStatus -9868）"),
        ]
    )
    func description(error: HotkeyRegistrationError, expected: String) {
        #expect(error.description == expected)
    }
}
