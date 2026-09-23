import Foundation
import Testing

import OpenPathCore

/// ConfigDecoder のテストで共有する入力とヘルパー
enum ConfigTestSupport {
    static let homeDirectory = "/Users/tester"

    /// DSN-002 §6 に記載の config.toml サンプル（そのまま転記）
    static let designSampleTOML = """
        roots = ["~/repos", "~/Documents"]
        depth = 2
        include_files = false
        auto_confirm = false
        hotkey = "ctrl+shift+o"
        disabled_apps = ["com.apple.finder"]
        ignore = ["node_modules", ".git", "target", "DerivedData", ".build"]

        [ghq]
        enabled = true
        """

    static let decoder = ConfigDecoder(homeDirectory: homeDirectory)

    /// TOML 文字列をパースしてからデコードする
    static func decode(_ source: String) throws -> ConfigDecodingResult {
        try decoder.decode(TOMLParser.parse(source))
    }
}

@Suite("ConfigDecoder: 正常系")
struct ConfigDecoderTests {
    private typealias S = ConfigTestSupport

    @Test("DSN-002 §6 のサンプル TOML が期待する Config になる（TST-001 §2.3）")
    func decodesDesignSample() throws {
        let result = try S.decode(S.designSampleTOML)

        let expected = Config(
            roots: ["/Users/tester/repos", "/Users/tester/Documents"],
            depth: 2,
            includeFiles: false,
            autoConfirm: false,
            hotkey: Hotkey(key: .o, modifiers: [.control, .shift]),
            disabledApps: ["com.apple.finder"],
            ignore: ["node_modules", ".git", "target", "DerivedData", ".build"],
            ghq: GhqConfig(enabled: true)
        )
        #expect(result.config == expected)
        #expect(result.warnings.isEmpty)
    }

    @Test("既定値は DSN-002 §6 のサンプルに従う（記入例の roots と disabled_apps は空）")
    func defaultValues() {
        let config = Config.default

        #expect(config.roots.isEmpty)
        #expect(config.depth == 2)
        #expect(config.includeFiles == false)
        #expect(config.autoConfirm == false)
        #expect(config.hotkey == Hotkey(key: .o, modifiers: [.control, .shift]))
        #expect(config.disabledApps.isEmpty)
        #expect(config.ignore == ["node_modules", ".git", "target", "DerivedData", ".build"])
        #expect(config.ghq.enabled == true)
    }

    @Test("disabled_apps を省略すると全アプリで有効になる（REQ-001 FR-DETECT-04）")
    func allAppsEnabledByDefault() throws {
        let config = try S.decode("depth = 2").config

        #expect(config.disabledApps.isEmpty)
        #expect(!config.disabledApps.contains("com.apple.finder"))
    }

    @Test("空の TOML はすべて既定値になる")
    func emptySourceYieldsDefaults() throws {
        let result = try S.decode("")

        #expect(result.config == .default)
        #expect(result.warnings.isEmpty)
    }

    @Test("未指定のキーだけが既定値で補われる")
    func missingKeysFallBackToDefaults() throws {
        let result = try S.decode("depth = 3\nauto_confirm = true")

        #expect(result.config == Config(depth: 3, autoConfirm: true))
    }

    @Test("[ghq] テーブルに enabled が無ければ既定値になる")
    func emptyGhqTable() throws {
        #expect(try S.decode("[ghq]").config.ghq == .default)
    }

    @Test("すべてのキーに既定値と異なる値を指定できる")
    func decodesNonDefaultValues() throws {
        let source = """
            roots = ["/opt/src", "~/work/"]
            depth = 5
            include_files = true
            auto_confirm = true
            hotkey = "cmd+opt+p"
            disabled_apps = ["com.example.a", "com.example.b"]
            ignore = ["vendor"]

            [ghq]
            enabled = false
            """

        let expected = Config(
            roots: ["/opt/src", "/Users/tester/work"],
            depth: 5,
            includeFiles: true,
            autoConfirm: true,
            hotkey: Hotkey(key: .p, modifiers: [.command, .option]),
            disabledApps: ["com.example.a", "com.example.b"],
            ignore: ["vendor"],
            ghq: GhqConfig(enabled: false)
        )
        #expect(try S.decode(source).config == expected)
    }

    @Test("空の配列は既定値で補わず、空として扱う")
    func emptyArraysOverrideDefaults() throws {
        let config = try S.decode("roots = []\ndisabled_apps = []\nignore = []").config

        #expect(config.roots.isEmpty)
        #expect(config.disabledApps.isEmpty)
        #expect(config.ignore.isEmpty)
    }

    @Test("roots は ~ 展開・正規化した上で、重複を先勝ちで取り除く（TST-001 §2.3）")
    func rootsAreResolvedAndDeduplicated() throws {
        let source = #"roots = ["~/repos/", "/opt//src/", "~/repos", "/Users/tester/repos", "/opt/src"]"#

        #expect(try S.decode(source).config.roots == ["/Users/tester/repos", "/opt/src"])
    }

    @Test("depth は 0 を許容する")
    func depthZero() throws {
        #expect(try S.decode("depth = 0").config.depth == 0)
    }

    @Test("ホームディレクトリを省略すると実行ユーザーのホームで展開する")
    func defaultHomeDirectory() throws {
        let expectedHome = try #require(RootPathResolver(homeDirectory: NSHomeDirectory()).resolve("~"))

        let result = try ConfigDecoder().decode(["roots": .stringArray(["~"])])

        #expect(result.config.roots == [expectedHome])
    }
}

@Suite("ConfigDecoder: 未知キーの警告")
struct ConfigDecoderWarningTests {
    private typealias S = ConfigTestSupport

    @Test("未知のキーはエラーにせず、キーパスの昇順で警告として集める")
    func unknownKeysBecomeWarnings() throws {
        let source = """
            depth = 3
            unknown = 1
            [ghq]
            enabled = false
            extra = "x"
            [other]
            key = 1
            """

        let result = try S.decode(source)

        #expect(result.config == Config(depth: 3, ghq: GhqConfig(enabled: false)))
        #expect(result.warnings == [.unknownKey("ghq.extra"), .unknownKey("other"), .unknownKey("unknown")])
    }

    @Test("[ghq] の後に書いたトップレベルのキーは ghq.<key> として警告し、値は既定値のまま")
    func topLevelKeyInsideGhqTable() throws {
        let result = try S.decode("[ghq]\ndepth = 3")

        #expect(result.config.depth == Config.defaultDepth)
        #expect(result.warnings == [.unknownKey("ghq.depth")])
    }

    @Test("警告の description はキーパスを含む")
    func warningDescription() {
        #expect(ConfigWarning.unknownKey("ghq.extra").description == "未知のキー 'ghq.extra' を無視しました")
    }
}
