import Carbon.HIToolbox
import Testing

import OpenPathCore

/// OpenPathCore は Carbon を import せずに仮想キーコードと修飾キーのビットを純データで持つため、
/// Mac 層が RegisterEventHotKey にそのまま渡せることを Carbon の定数と突き合わせて保証する。
@Suite("Hotkey: Carbon との互換性")
struct HotkeyCarbonCompatibilityTests {
    static let carbonKeyCodes: [(VirtualKey, Int)] = [
        (.a, kVK_ANSI_A), (.b, kVK_ANSI_B), (.c, kVK_ANSI_C), (.d, kVK_ANSI_D), (.e, kVK_ANSI_E),
        (.f, kVK_ANSI_F), (.g, kVK_ANSI_G), (.h, kVK_ANSI_H), (.i, kVK_ANSI_I), (.j, kVK_ANSI_J),
        (.k, kVK_ANSI_K), (.l, kVK_ANSI_L), (.m, kVK_ANSI_M), (.n, kVK_ANSI_N), (.o, kVK_ANSI_O),
        (.p, kVK_ANSI_P), (.q, kVK_ANSI_Q), (.r, kVK_ANSI_R), (.s, kVK_ANSI_S), (.t, kVK_ANSI_T),
        (.u, kVK_ANSI_U), (.v, kVK_ANSI_V), (.w, kVK_ANSI_W), (.x, kVK_ANSI_X), (.y, kVK_ANSI_Y),
        (.z, kVK_ANSI_Z),
        (.digit0, kVK_ANSI_0), (.digit1, kVK_ANSI_1), (.digit2, kVK_ANSI_2), (.digit3, kVK_ANSI_3),
        (.digit4, kVK_ANSI_4), (.digit5, kVK_ANSI_5), (.digit6, kVK_ANSI_6), (.digit7, kVK_ANSI_7),
        (.digit8, kVK_ANSI_8), (.digit9, kVK_ANSI_9),
        (.minus, kVK_ANSI_Minus), (.equal, kVK_ANSI_Equal), (.leftBracket, kVK_ANSI_LeftBracket),
        (.rightBracket, kVK_ANSI_RightBracket), (.backslash, kVK_ANSI_Backslash),
        (.semicolon, kVK_ANSI_Semicolon), (.quote, kVK_ANSI_Quote), (.comma, kVK_ANSI_Comma),
        (.period, kVK_ANSI_Period), (.slash, kVK_ANSI_Slash), (.grave, kVK_ANSI_Grave),
        (.space, kVK_Space), (.return, kVK_Return), (.tab, kVK_Tab), (.delete, kVK_Delete),
        (.escape, kVK_Escape),
        (.leftArrow, kVK_LeftArrow), (.rightArrow, kVK_RightArrow), (.upArrow, kVK_UpArrow),
        (.downArrow, kVK_DownArrow),
        (.f1, kVK_F1), (.f2, kVK_F2), (.f3, kVK_F3), (.f4, kVK_F4), (.f5, kVK_F5), (.f6, kVK_F6),
        (.f7, kVK_F7), (.f8, kVK_F8), (.f9, kVK_F9), (.f10, kVK_F10), (.f11, kVK_F11), (.f12, kVK_F12),
    ]

    @Test("\"ctrl+shift+o\" は kVK_ANSI_O と controlKey | shiftKey になる（TST-001 §2.3）")
    func defaultHotkeyMatchesCarbon() throws {
        let hotkey = try HotkeyParser.parse("ctrl+shift+o")

        #expect(hotkey.keyCode == UInt32(kVK_ANSI_O))
        #expect(hotkey.modifiers == [.control, .shift])
        #expect(hotkey.modifiers.rawValue == UInt32(controlKey | shiftKey))
    }

    @Test(
        "修飾キーのビットは Carbon の EventModifiers と一致する",
        arguments: [
            (HotkeyModifiers.control, controlKey),
            (.shift, shiftKey),
            (.option, optionKey),
            (.command, cmdKey),
        ]
    )
    func modifierBitsMatchCarbon(modifier: HotkeyModifiers, carbonFlag: Int) {
        #expect(modifier.rawValue == UInt32(carbonFlag))
    }

    @Test("仮想キーコードは Carbon の kVK_* と一致する", arguments: carbonKeyCodes)
    func keyCodesMatchCarbon(key: VirtualKey, carbonKeyCode: Int) {
        #expect(key.rawValue == UInt32(carbonKeyCode))
    }

    @Test("すべての VirtualKey を Carbon と突き合わせている")
    func everyKeyIsCompared() {
        #expect(Set(Self.carbonKeyCodes.map(\.0)) == Set(VirtualKey.allCases))
    }
}
