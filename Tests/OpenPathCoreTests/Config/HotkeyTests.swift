import Testing

import OpenPathCore

@Suite("Hotkey: 表記とキー名テーブル")
struct HotkeyTests {
    @Test(
        "description は修飾キーを ctrl → opt → shift → cmd の順に並べた正規の表記になる",
        arguments: [
            ("ctrl+shift+o", "ctrl+shift+o"),
            ("cmd+shift+opt+ctrl+O", "ctrl+opt+shift+cmd+o"),
            ("alt+enter", "opt+return"),
            ("command+backspace", "cmd+delete"),
            ("ctrl+minus", "ctrl+-"),
        ]
    )
    func canonicalDescription(source: String, expected: String) throws {
        #expect(try HotkeyParser.parse(source).description == expected)
    }

    @Test("テーブルに無いキーコードは 16 進で表記する")
    func descriptionOfUnknownKeyCode() {
        let unknownKeyCode: UInt32 = 0x7F

        #expect(Hotkey(keyCode: unknownKeyCode, modifiers: .command).description == "cmd+keycode(0x7F)")
    }

    @Test("すべてのキーで description をパースし直すと元に戻る", arguments: VirtualKey.allCases)
    func descriptionRoundTrips(key: VirtualKey) throws {
        let hotkey = Hotkey(key: key, modifiers: [.control, .option, .shift, .command])

        #expect(try HotkeyParser.parse(hotkey.description) == hotkey)
    }

    @Test("キー名はすべて小文字で、キー間・修飾キー名と重複しない")
    func keyNamesAreUniqueAndLowercase() {
        let modifierNames: Set<String> = ["ctrl", "control", "shift", "opt", "option", "alt", "cmd", "command"]
        let allNames = VirtualKey.allCases.flatMap(\.names)

        #expect(allNames.allSatisfy { $0 == $0.lowercased() && !$0.isEmpty })
        #expect(Set(allNames).count == allNames.count)
        #expect(modifierNames.isDisjoint(with: allNames))
    }

    @Test("仮想キーコードに重複が無い")
    func keyCodesAreUnique() {
        let keyCodes = VirtualKey.allCases.map(\.rawValue)

        #expect(Set(keyCodes).count == keyCodes.count)
    }

    @Test("パースエラーの description は種類ごとに異なり、名前を含む")
    func parseErrorDescriptions() {
        let errors: [HotkeyParseError] = [
            .empty, .emptyComponent, .unknownKey("foo"), .duplicateModifier("ctrl"),
            .multipleKeys("a", "b"), .missingKey, .missingModifier, .shiftOnlyModifier,
        ]
        let descriptions = errors.map(\.description)

        #expect(Set(descriptions).count == errors.count)
        #expect(HotkeyParseError.unknownKey("foo").description.contains("'foo'"))
        #expect(HotkeyParseError.multipleKeys("a", "b").description.contains("'a' と 'b'"))
    }

    @Test("名前からキーを引ける（大文字小文字は区別しない）")
    func lookupByName() {
        #expect(VirtualKey(name: "O") == .o)
        #expect(VirtualKey(name: "esc") == .escape)
        #expect(VirtualKey(name: "F5") == .f5)
        #expect(VirtualKey(name: "unknown") == nil)
    }
}
