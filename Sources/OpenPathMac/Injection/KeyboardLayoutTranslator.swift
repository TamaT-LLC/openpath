import Carbon.HIToolbox

import OpenPathCore

/// 現在の入力ソースのキー配列（UCKeyTranslate）で、仮想キーコードが入力する文字を調べる（Issue #68）。
///
/// どのキーを選ぶかは OpenPathCore の `InjectionKeyCodeResolver` が持つ。ここではキー配列を読むだけにする。
/// TIS の関数はメインスレッドで呼ぶ必要があるため MainActor に置く。
@MainActor
enum KeyboardLayoutTranslator {
    /// UCKeyTranslate が返す文字の最大長。1 キーの文字を調べるだけなので短くてよい。
    nonisolated private static let maxCharacters = 4

    /// 現在の入力ソースのキー配列。キー配列のデータを持たない入力ソース（一部の入力メソッド）では、
    /// ASCII を入力できるキー配列（日本語入力なら英字のキー配列）で代える。
    /// - Returns: 読めなければ nil（呼び出し側は QWERTY の物理位置で送る）。
    static func current() -> InjectionKeyCodeResolver.Translate? {
        let copySources: [() -> Unmanaged<TISInputSource>?] = [
            { TISCopyCurrentKeyboardLayoutInputSource() },
            { TISCopyCurrentASCIICapableKeyboardLayoutInputSource() },
        ]
        for copySource in copySources {
            if let inputSource = copySource()?.takeRetainedValue(), let translate = translator(for: inputSource) {
                return translate
            }
        }
        return nil
    }

    /// 入力ソースのキー配列。キー配列のデータを持たない入力ソースでは nil。
    static func translator(for inputSource: TISInputSource) -> InjectionKeyCodeResolver.Translate? {
        guard let property = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        // 入力ソースを手放した後も読めるよう、キー配列のデータを保持する
        let layoutData = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue()
        let keyboardType = UInt32(LMGetKbdType())
        return { keyCode, modifiers in
            translate(keyCode: keyCode, modifiers: modifiers, layoutData: layoutData, keyboardType: keyboardType)
        }
    }

    /// keyCode を modifiers 付きで押したときに入力される文字。デッドキー（アクセント記号の入力待ち）にはしない。
    /// UCKeyTranslate は TIS と違いメインスレッドに縛られないため、隔離しない。
    nonisolated private static func translate(
        keyCode: UInt16,
        modifiers: InjectionKeyModifiers,
        layoutData: CFData,
        keyboardType: UInt32
    ) -> String? {
        guard let bytes = CFDataGetBytePtr(layoutData) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        var carbonModifiers = 0
        if modifiers.contains(.command) {
            carbonModifiers |= cmdKey
        }
        if modifiers.contains(.shift) {
            carbonModifiers |= shiftKey
        }
        // UCKeyTranslate の修飾キーは、Carbon の修飾キーのビットを 8 ビット右へずらした値
        let modifierKeyState = UInt32((carbonModifiers >> 8) & 0xFF)
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: maxCharacters)
        var length = 0
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierKeyState,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            maxCharacters,
            &length,
            &characters
        )
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
