import Testing
import OpenPathCore

@Suite("ConfigDecoder: zoxide")
struct ZoxideConfigTests {
    @Test("既存設定と生成された既定設定では zoxide を有効にしない")
    func defaultsToDisabled() throws {
        let decoder = ConfigDecoder(homeDirectory: "/Users/example")
        #expect(try decoder.decode(TOMLParser.parse("")).config.zoxide == ZoxideConfig(enabled: false))
        let generated = DefaultConfigFile.contents(ghqRoot: nil, homeDirectory: "/Users/example")
        #expect(try decoder.decode(TOMLParser.parse(generated)).config.zoxide == .default)
        #expect(try decoder.decode(TOMLParser.parse("[zoxide]")).config.zoxide == .default)
    }

    @Test("有効化と未知キーの警告を読み取る")
    func decodesEnabledAndWarnings() throws {
        let result = try ConfigDecoder().decode(TOMLParser.parse("[zoxide]\nenabled = true\nextra = 1"))
        #expect(result.config.zoxide.enabled)
        #expect(result.warnings == [.unknownKey("zoxide.extra")])
    }

    @Test("お気に入りと zoxide を同じ設定から読み、別名を未知キーにしない")
    func decodesAlongsideFavorites() throws {
        let source = """
            [zoxide]
            enabled = true
            extra = 1
            [favorites]
            "仕事" = "~/repos/project"
            "zoxide" = "~/Documents"
            """
        let result = try ConfigDecoder(homeDirectory: "/Users/example").decode(TOMLParser.parse(source))
        #expect(result.config.zoxide.enabled)
        #expect(result.config.favorites == [
            Favorite(name: "zoxide", path: "/Users/example/Documents"),
            Favorite(name: "仕事", path: "/Users/example/repos/project")
        ])
        #expect(result.warnings == [.unknownKey("zoxide.extra")])
    }

    @Test("不正な型を zoxide のキーパス付きで報告する")
    func reportsInvalidTypes() throws {
        try ConfigErrorCase("zoxide = true", key: "zoxide", .typeMismatch(expected: .table, actual: .bool)).verify()
        try ConfigErrorCase("[zoxide]\nenabled = 1", key: "zoxide.enabled", .typeMismatch(expected: .bool, actual: .integer)).verify()
    }
}
