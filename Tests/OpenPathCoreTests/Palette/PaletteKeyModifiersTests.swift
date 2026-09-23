import Testing

import OpenPathCore

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
