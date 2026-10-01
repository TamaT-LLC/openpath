import Carbon.HIToolbox
import Testing

import OpenPathCore

@Suite("InjectionKeyCodeResolver: 入力ソースのキー配列から、キー操作の文字を入力する仮想キーコードを求める（Issue #68）")
struct InjectionKeyCodeResolverTests {
    /// キー配列の一部（仮想キーコード → Shift なし・Shift ありの文字）。載っていないキーは文字を入力しない。
    private struct LayoutTable {
        var plain: [Int: String]
        var shifted: [Int: String] = [:]
        /// ⌘ を押している間だけ別の配列になるキー（「Dvorak - QWERTY ⌘」）。⌘ 付きで引いたときはこちらを優先する。
        var withCommand: [Int: String] = [:]
        /// 引いた修飾キーを記録する。
        let lookups = LookupRecorder()

        var translate: InjectionKeyCodeResolver.Translate {
            { keyCode, modifiers in
                lookups.record(keyCode: keyCode, modifiers: modifiers)
                let code = Int(keyCode)
                if modifiers.contains(.command), let character = withCommand[code] {
                    return modifiers.contains(.shift) ? character.uppercased() : character
                }
                return modifiers.contains(.shift) ? shifted[code] : plain[code]
            }
        }
    }

    private final class LookupRecorder: @unchecked Sendable {
        private(set) var modifiers: Set<InjectionKeyModifiers> = []

        func record(keyCode: UInt16, modifiers: InjectionKeyModifiers) {
            self.modifiers.insert(modifiers)
        }
    }

    // キー配列はアクセスのたびに作る（引いた修飾キーの記録をテスト間で共有しないため）

    /// US（QWERTY）。JIS も文字キーの位置は同じ。
    private static var qwerty: LayoutTable {
        LayoutTable(
            plain: [kVK_ANSI_A: "a", kVK_ANSI_G: "g", kVK_ANSI_V: "v", kVK_ANSI_Slash: "/", kVK_ANSI_U: "u", kVK_ANSI_Period: "."],
            shifted: [kVK_ANSI_A: "A", kVK_ANSI_G: "G", kVK_ANSI_V: "V", kVK_ANSI_Slash: "?"]
        )
    }

    /// Dvorak。g は QWERTY の U、v は QWERTY の .（ピリオド）、/ は QWERTY の [ の位置。a は同じ位置。
    private static var dvorak: LayoutTable {
        LayoutTable(
            plain: [
                kVK_ANSI_A: "a", kVK_ANSI_U: "g", kVK_ANSI_Period: "v", kVK_ANSI_LeftBracket: "/",
                kVK_ANSI_G: "i", kVK_ANSI_V: "k", kVK_ANSI_Slash: "z",
            ]
        )
    }

    /// Colemak。g は QWERTY の T、a と v は同じ位置、/ も同じ位置。
    private static var colemak: LayoutTable {
        LayoutTable(plain: [kVK_ANSI_A: "a", kVK_ANSI_T: "g", kVK_ANSI_V: "v", kVK_ANSI_Slash: "/", kVK_ANSI_G: "d"])
    }

    /// ドイツ語（QWERTZ）風。/ は Shift+7 でしか入力できない。
    private static var qwertz: LayoutTable {
        LayoutTable(
            plain: [kVK_ANSI_A: "a", kVK_ANSI_G: "g", kVK_ANSI_V: "v", kVK_ANSI_7: "7", kVK_ANSI_Slash: "-"],
            shifted: [kVK_ANSI_7: "/", kVK_ANSI_Slash: "_"]
        )
    }

    private static func resolve(_ keyStroke: InjectionKeyStroke, in layout: LayoutTable) -> InjectionResolvedKey {
        InjectionKeyCodeResolver.resolve(keyStroke.spec, translate: layout.translate)
    }

    @Test("キー操作の物理位置と修飾キーは、HIToolbox の仮想キーコードと従来の組み合わせのとおり")
    func specsMatchPhysicalKeys() {
        #expect(InjectionKeyStroke.goToFolder.spec == InjectionKeySpec(character: "g", physicalKeyCode: UInt16(kVK_ANSI_G), modifiers: [.command, .shift]))
        #expect(InjectionKeyStroke.selectAll.spec == InjectionKeySpec(character: "a", physicalKeyCode: UInt16(kVK_ANSI_A), modifiers: .command))
        #expect(InjectionKeyStroke.paste.spec == InjectionKeySpec(character: "v", physicalKeyCode: UInt16(kVK_ANSI_V), modifiers: .command))
        #expect(InjectionKeyStroke.returnKey.spec == InjectionKeySpec(character: nil, physicalKeyCode: UInt16(kVK_Return), modifiers: []))
        #expect(
            InjectionKeyStroke.slash.spec
                == InjectionKeySpec(character: "/", physicalKeyCode: UInt16(kVK_ANSI_Slash), modifiers: [], allowsShiftedCharacter: true)
        )
    }

    @Test("US / JIS（QWERTY）では従来どおり物理位置のキーで送る", arguments: [InjectionKeyStroke.goToFolder, .selectAll, .paste, .slash])
    func qwertyKeepsPhysicalKeys(keyStroke: InjectionKeyStroke) {
        let resolved = Self.resolve(keyStroke, in: Self.qwerty)

        #expect(resolved == InjectionResolvedKey(keyCode: keyStroke.spec.physicalKeyCode, modifiers: keyStroke.spec.modifiers, source: .layout))
    }

    @Test("Dvorak では ⌘⇧G を「g」の位置（QWERTY の U）で送る")
    func dvorakGoToFolderUsesGPosition() {
        let resolved = Self.resolve(.goToFolder, in: Self.dvorak)

        #expect(resolved == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_U), modifiers: [.command, .shift], source: .layout))
    }

    @Test("Dvorak では ⌘V を「v」の位置（QWERTY の .）で、⌘A は同じ位置で、/ は QWERTY の [ の位置で送る")
    func dvorakOtherKeys() {
        #expect(Self.resolve(.paste, in: Self.dvorak) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_Period), modifiers: .command, source: .layout))
        #expect(Self.resolve(.selectAll, in: Self.dvorak) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_A), modifiers: .command, source: .layout))
        #expect(Self.resolve(.slash, in: Self.dvorak) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_LeftBracket), modifiers: [], source: .layout))
    }

    @Test("Colemak では ⌘⇧G を「g」の位置（QWERTY の T）で送る")
    func colemakGoToFolderUsesGPosition() {
        let resolved = Self.resolve(.goToFolder, in: Self.colemak)

        #expect(resolved == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_T), modifiers: [.command, .shift], source: .layout))
    }

    @Test("ショートカットの文字は ⌘ を押したときのキー配列で引く（「Dvorak - QWERTY ⌘」は ⌘ の間 QWERTY になる）")
    func shortcutsAreLookedUpWithCommand() {
        var layout = Self.dvorak
        layout.withCommand = [kVK_ANSI_G: "g", kVK_ANSI_A: "a", kVK_ANSI_V: "v", kVK_ANSI_U: "u", kVK_ANSI_Period: "."]

        #expect(Self.resolve(.goToFolder, in: layout).keyCode == UInt16(kVK_ANSI_G))
        #expect(Self.resolve(.paste, in: layout).keyCode == UInt16(kVK_ANSI_V))
        // Shift は送るときに足すだけで、文字を引くときには付けない（⌘ だけで引く）
        #expect(layout.lookups.modifiers.allSatisfy { $0 == .command })
    }

    @Test("/ が Shift 付きでしか入力できない配列では、Shift を足して送る")
    func slashWithShift() {
        let resolved = Self.resolve(.slash, in: Self.qwertz)

        #expect(resolved == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_7), modifiers: .shift, source: .layout))
    }

    @Test("Shift なしで入力できるキーがあれば、Shift 付きのキーより優先する")
    func prefersUnshiftedKey() {
        var layout = Self.qwertz
        layout.shifted[kVK_ANSI_Slash] = "/"
        layout.plain[kVK_ANSI_LeftBracket] = "/"

        #expect(Self.resolve(.slash, in: layout) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_LeftBracket), modifiers: [], source: .layout))
    }

    @Test("ショートカットは、文字が Shift 付きでしか入力できなくても Shift を足さず、物理位置で送る")
    func shortcutsNeverAddShift() {
        let layout = LayoutTable(plain: [kVK_ANSI_G: "x"], shifted: [kVK_ANSI_U: "g"])

        #expect(Self.resolve(.goToFolder, in: layout) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_G), modifiers: [.command, .shift], source: .physicalPosition))
    }

    @Test("物理位置のキーが目的の文字を入力するなら、ほかに同じ文字のキーがあっても物理位置を使う")
    func prefersPhysicalKeyWhenItMatches() {
        var layout = Self.qwerty
        // 物理位置（kVK_ANSI_G = 0x05）より小さい仮想キーコード（kVK_ANSI_S = 0x01）にも「g」を置く
        layout.plain[kVK_ANSI_S] = "g"

        #expect(Self.resolve(.goToFolder, in: layout).keyCode == UInt16(kVK_ANSI_G))
    }

    @Test("テンキーのキーは使わない（テンキーの / しか無ければ物理位置で送る）")
    func ignoresKeypad() {
        let layout = LayoutTable(plain: [kVK_ANSI_KeypadDivide: "/", kVK_ANSI_Slash: "-"])

        #expect(Self.resolve(.slash, in: layout) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_Slash), modifiers: [], source: .physicalPosition))
    }

    @Test("JIS 配列の ¥ や _ のキーにある文字も探す")
    func searchesJISKeys() {
        let layout = LayoutTable(plain: [kVK_JIS_Underscore: "/"])

        #expect(Self.resolve(.slash, in: layout) == InjectionResolvedKey(keyCode: UInt16(kVK_JIS_Underscore), modifiers: [], source: .layout))
    }

    @Test("キー配列に文字のキーが無ければ、物理位置で送る（従来の送り方）")
    func fallsBackToPhysicalKeyWhenCharacterIsMissing() {
        let layout = LayoutTable(plain: [kVK_ANSI_G: "п"])

        #expect(Self.resolve(.goToFolder, in: layout) == InjectionResolvedKey(keyCode: UInt16(kVK_ANSI_G), modifiers: [.command, .shift], source: .physicalPosition))
    }

    @Test("キー配列を読めなければ、物理位置で送る（従来の送り方）", arguments: [InjectionKeyStroke.goToFolder, .selectAll, .paste, .slash])
    func fallsBackToPhysicalKeyWithoutLayout(keyStroke: InjectionKeyStroke) {
        let resolved = InjectionKeyCodeResolver.resolve(keyStroke.spec, translate: nil)

        #expect(resolved == InjectionResolvedKey(keyCode: keyStroke.spec.physicalKeyCode, modifiers: keyStroke.spec.modifiers, source: .physicalPosition))
    }

    @Test("Return は文字に依らないため、キー配列を引かずに kVK_Return で送る")
    func returnKeyIsFixed() {
        let layout = Self.dvorak

        let resolved = Self.resolve(.returnKey, in: layout)

        #expect(resolved == InjectionResolvedKey(keyCode: UInt16(kVK_Return), modifiers: [], source: .fixed))
        #expect(layout.lookups.modifiers.isEmpty)
    }
}
