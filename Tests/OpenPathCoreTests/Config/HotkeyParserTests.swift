import Testing

import OpenPathCore

@Suite("HotkeyParser: 正常系")
struct HotkeyParserTests {
    private static let controlShiftO = Hotkey(key: .o, modifiers: [.control, .shift])

    @Test("既定のホットキー \"ctrl+shift+o\" をパースできる")
    func parsesDefaultHotkey() throws {
        #expect(try HotkeyParser.parse("ctrl+shift+o") == Self.controlShiftO)
    }

    @Test(
        "大文字小文字・順序・前後の空白は区別しない",
        arguments: [
            "CTRL+SHIFT+O",
            "Ctrl+Shift+o",
            "shift+ctrl+o",
            "o+shift+ctrl",
            "ctrl + shift + o",
            "  ctrl+shift+o  ",
            "\tctrl\t+\tshift\t+\to\t",
        ]
    )
    func ignoresCaseOrderAndWhitespace(source: String) throws {
        #expect(try HotkeyParser.parse(source) == Self.controlShiftO)
    }

    static let modifierAliasCases: [(String, HotkeyModifiers)] = [
        ("ctrl+o", .control),
        ("control+o", .control),
        ("opt+o", .option),
        ("option+o", .option),
        ("alt+o", .option),
        ("cmd+o", .command),
        ("command+o", .command),
        ("ctrl+opt+shift+cmd+o", [.control, .option, .shift, .command]),
    ]

    @Test("修飾キーの別名を受け付ける", arguments: modifierAliasCases)
    func modifierAliases(source: String, expected: HotkeyModifiers) throws {
        #expect(try HotkeyParser.parse(source) == Hotkey(key: .o, modifiers: expected))
    }

    @Test(
        "文字以外のキーを名前で指定できる",
        arguments: [
            ("cmd+0", VirtualKey.digit0),
            ("cmd+9", .digit9),
            ("cmd+-", .minus),
            ("cmd+minus", .minus),
            ("cmd+=", .equal),
            ("cmd+[", .leftBracket),
            ("cmd+]", .rightBracket),
            ("cmd+\\", .backslash),
            ("cmd+;", .semicolon),
            ("cmd+'", .quote),
            ("cmd+,", .comma),
            ("cmd+.", .period),
            ("cmd+/", .slash),
            ("cmd+`", .grave),
            ("cmd+space", .space),
            ("cmd+return", .return),
            ("cmd+enter", .return),
            ("cmd+tab", .tab),
            ("cmd+delete", .delete),
            ("cmd+backspace", .delete),
            ("cmd+escape", .escape),
            ("cmd+esc", .escape),
            ("cmd+left", .leftArrow),
            ("cmd+right", .rightArrow),
            ("cmd+up", .upArrow),
            ("cmd+down", .downArrow),
            ("cmd+f1", .f1),
            ("cmd+F12", .f12),
        ]
    )
    func namedKeys(source: String, expected: VirtualKey) throws {
        #expect(try HotkeyParser.parse(source) == Hotkey(key: expected, modifiers: .command))
    }

    @Test("shift は他の修飾キーと組み合わせれば使える")
    func shiftWithAnotherModifier() throws {
        #expect(try HotkeyParser.parse("shift+cmd+p") == Hotkey(key: .p, modifiers: [.shift, .command]))
    }

    @Test("Hotkey(key:modifiers:) は仮想キーコードを keyCode に持つ")
    func keyCodeFromVirtualKey() {
        #expect(Hotkey(key: .o, modifiers: .control) == Hotkey(keyCode: VirtualKey.o.rawValue, modifiers: .control))
    }
}

@Suite("HotkeyParser: エラー")
struct HotkeyParserErrorTests {
    @Test("空文字列・空白のみはエラー", arguments: ["", "   ", "\t"])
    func empty(source: String) {
        #expect(throws: HotkeyParseError.empty) { try HotkeyParser.parse(source) }
    }

    @Test("+ で区切った要素が空だとエラー", arguments: ["ctrl+", "+o", "ctrl++o", "ctrl+ +o", "+"])
    func emptyComponent(source: String) {
        #expect(throws: HotkeyParseError.emptyComponent) { try HotkeyParser.parse(source) }
    }

    @Test("修飾キーが無いとエラー", arguments: ["o", "f1", "space"])
    func missingModifier(source: String) {
        #expect(throws: HotkeyParseError.missingModifier) { try HotkeyParser.parse(source) }
    }

    @Test("修飾キーが shift だけだと通常の文字入力を奪うためエラー", arguments: ["shift+o", "shift+1"])
    func shiftOnlyModifier(source: String) {
        #expect(throws: HotkeyParseError.shiftOnlyModifier) { try HotkeyParser.parse(source) }
    }

    @Test("キーが無いとエラー", arguments: ["ctrl", "ctrl+shift", "shift"])
    func missingKey(source: String) {
        #expect(throws: HotkeyParseError.missingKey) { try HotkeyParser.parse(source) }
    }

    @Test(
        "未知の名前はエラー（書いたままの表記で報告する）",
        arguments: [
            ("ctrl+foo", "foo"),
            ("Ctrl+Foo", "Foo"),
            ("hyper+o", "hyper"),
            ("ctrl+f13", "f13"),
            ("ctrl+ｏ", "ｏ"),
            ("ctrl shift o", "ctrl shift o"),
        ]
    )
    func unknownKey(source: String, unknownName: String) {
        #expect(throws: HotkeyParseError.unknownKey(unknownName)) { try HotkeyParser.parse(source) }
    }

    @Test(
        "同じ修飾キーの重複はエラー（別名どうしも重複とみなす）",
        arguments: [
            ("ctrl+ctrl+o", "ctrl"),
            ("ctrl+control+o", "control"),
            ("alt+opt+o", "opt"),
            ("cmd+shift+SHIFT+o", "SHIFT"),
        ]
    )
    func duplicateModifier(source: String, duplicated: String) {
        #expect(throws: HotkeyParseError.duplicateModifier(duplicated)) { try HotkeyParser.parse(source) }
    }

    @Test(
        "キーが 2 つ以上あるとエラー",
        arguments: [
            ("ctrl+a+b", "a", "b"),
            ("ctrl+o+O", "o", "O"),
            ("ctrl+return+enter", "return", "enter"),
        ]
    )
    func multipleKeys(source: String, first: String, second: String) {
        #expect(throws: HotkeyParseError.multipleKeys(first, second)) { try HotkeyParser.parse(source) }
    }
}
