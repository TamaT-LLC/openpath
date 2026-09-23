import Carbon.HIToolbox
import Testing

import OpenPathCore

/// Core は Carbon を import しないため、仮想キーコードの値を Carbon の定数と突き合わせる。
@Suite("PaletteKeyCode")
struct PaletteKeyCodeTests {
    @Test(
        "仮想キーコードは Carbon の kVK_* と一致する",
        arguments: [
            (PaletteKeyCode.return, kVK_Return),
            (.keypadEnter, kVK_ANSI_KeypadEnter),
            (.tab, kVK_Tab),
            (.escape, kVK_Escape),
            (.upArrow, kVK_UpArrow),
            (.downArrow, kVK_DownArrow),
            (.ansiA, kVK_ANSI_A),
            (.ansiC, kVK_ANSI_C),
            (.ansiN, kVK_ANSI_N),
            (.ansiP, kVK_ANSI_P),
            (.ansiV, kVK_ANSI_V),
            (.ansiX, kVK_ANSI_X),
            (.ansiZ, kVK_ANSI_Z),
        ]
    )
    func matchesCarbon(keyCode: PaletteKeyCode, carbonValue: Int) {
        #expect(Int(keyCode.rawValue) == carbonValue)
    }

    @Test("すべてのキーコードを Carbon と照合している")
    func everyCaseIsVerified() {
        let verifiedCaseCount = 13
        #expect(PaletteKeyCode.allCases.count == verifiedCaseCount)
    }

    @Test("文字キーは US 配列での文字を持ち、特殊キーは持たない")
    func ansiLetters() {
        #expect(PaletteKeyCode.ansiN.ansiLetter == "n")
        #expect(PaletteKeyCode.ansiZ.ansiLetter == "z")
        #expect(PaletteKeyCode.return.ansiLetter == nil)
        #expect(PaletteKeyCode.upArrow.ansiLetter == nil)
    }
}

@Suite("PaletteKeyModifiers")
struct PaletteKeyModifiersTests {
    @Test("表示は macOS のメニューと同じ ⌃⌥⇧⌘ の順で、修飾なしは空文字列")
    func descriptionUsesMenuOrder() {
        #expect(PaletteKeyModifiers([.command, .shift, .option, .control]).description == "⌃⌥⇧⌘")
        #expect(PaletteKeyModifiers.command.description == "⌘")
        #expect(PaletteKeyModifiers().description.isEmpty)
    }

    @Test("すべての組み合わせを区別できる")
    func combinationsAreDistinct() {
        let expectedCombinationCount = 16

        #expect(Set(PaletteKeyModifiers.allCombinations).count == expectedCombinationCount)
    }
}
