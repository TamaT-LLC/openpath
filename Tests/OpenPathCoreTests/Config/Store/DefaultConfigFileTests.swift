import Testing

import OpenPathCore

@Suite("DefaultConfigFile: 既定の config.toml")
struct DefaultConfigFileTests {
    private static let homeDirectory = "/Users/tester"
    private static let decoder = ConfigDecoder(homeDirectory: homeDirectory)
    private static let commentPrefix = "#"
    private static let tableHeaderPrefix = "["

    private static func contents(ghqRoot: String?) -> String {
        DefaultConfigFile.contents(ghqRoot: ghqRoot, homeDirectory: homeDirectory)
    }

    /// 生成した TOML を ConfigStore と同じ手順（パース → デコード）で読み戻す
    private static func readBack(_ contents: String) throws -> ConfigDecodingResult {
        try decoder.decode(TOMLParser.parse(contents))
    }

    // MARK: - 読み戻し

    @Test("ghq root を roots に含み、読み戻すと roots 以外は既定値の Config になる（TST-001 §2.3）")
    func readsBackWithGhqRoot() throws {
        let result = try Self.readBack(Self.contents(ghqRoot: "/Users/tester/ghq"))

        #expect(result.config == Config(roots: ["/Users/tester/ghq"]))
        #expect(result.warnings.isEmpty)
    }

    @Test("ghq root が無ければ roots は空で、読み戻すと既定の Config になる")
    func readsBackWithoutGhqRoot() throws {
        let contents = Self.contents(ghqRoot: nil)
        let result = try Self.readBack(contents)

        #expect(contents.contains("\nroots = []\n"))
        #expect(result.config == .default)
        #expect(result.warnings.isEmpty)
    }

    // MARK: - roots の書き方

    @Test(
        "ホーム配下の ghq root は ~ を使って書く（dotfiles で共有しやすくするため）",
        arguments: [
            ("/Users/tester/ghq", "roots = [\"~/ghq\"]"),
            ("/Users/tester/src/ghq/", "roots = [\"~/src/ghq\"]"),
            ("/Users/tester", "roots = [\"~\"]"),
        ]
    )
    func abbreviatesHomeDirectory(ghqRoot: String, expectedLine: String) {
        #expect(Self.contents(ghqRoot: ghqRoot).contains("\n\(expectedLine)\n"))
    }

    @Test(
        "ホーム外の ghq root は正規化した絶対パスで書く",
        arguments: [
            ("/opt/ghq", "roots = [\"/opt/ghq\"]"),
            ("/Users/tester2/ghq", "roots = [\"/Users/tester2/ghq\"]"),
            ("/opt/./src/../ghq/", "roots = [\"/opt/ghq\"]"),
        ]
    )
    func writesAbsolutePathOutsideHome(ghqRoot: String, expectedLine: String) {
        #expect(Self.contents(ghqRoot: ghqRoot).contains("\n\(expectedLine)\n"))
    }

    @Test(
        "引用符・バックスラッシュ・制御文字を含むパスもエスケープして読み戻せる",
        arguments: [
            "/Users/tester/with \"quote\"",
            "/Users/tester/back\\slash",
            "/Users/tester/tab\tand\u{7F}del",
            "/Users/tester/改行\nあり",
            "/opt/日本語 フォルダ",
        ]
    )
    func escapesSpecialCharacters(ghqRoot: String) throws {
        let result = try Self.readBack(Self.contents(ghqRoot: ghqRoot))

        #expect(result.config.roots == [ghqRoot])
    }

    @Test(
        "絶対パスに解決できない ghq root は roots に含めない（生成したファイルが読めなくなるのを防ぐ）",
        arguments: ["", "relative/ghq", "~other/ghq"]
    )
    func omitsUnresolvableGhqRoot(ghqRoot: String) throws {
        let contents = Self.contents(ghqRoot: ghqRoot)

        #expect(contents.contains("\nroots = []\n"))
        #expect(try Self.readBack(contents).config == .default)
    }

    // MARK: - 人が編集しやすい形

    @Test("DSN-002 §6 のキーをすべて既定値で含む（disabled_apps は空）")
    func containsAllDesignKeys() {
        let lines = Self.contents(ghqRoot: nil).split(separator: "\n").map(String.init)

        for expectedLine in [
            "roots = []",
            "depth = 2",
            "include_files = false",
            "auto_confirm = false",
            "hotkey = \"ctrl+shift+o\"",
            "disabled_apps = []",
            "ignore = [\"node_modules\", \".git\", \"target\", \"DerivedData\", \".build\"]",
            "[ghq]",
            "enabled = true",
        ] {
            #expect(lines.contains(expectedLine), "\(expectedLine) が含まれていない")
        }
    }

    @Test("各キーの直前（空行を除く）にコメントがある")
    func everyKeyHasComment() {
        let lines = Self.contents(ghqRoot: "/Users/tester/ghq").split(separator: "\n").map(String.init)

        let settingIndices = lines.indices.filter { index in
            let line = lines[index]
            return !line.hasPrefix(Self.commentPrefix) && !line.hasPrefix(Self.tableHeaderPrefix)
        }
        #expect(!settingIndices.isEmpty)
        for index in settingIndices {
            let previousLine = index > lines.startIndex ? lines[index - 1] : ""
            #expect(previousLine.hasPrefix(Self.commentPrefix), "\(lines[index]) の前にコメントが無い")
        }
        #expect(lines.first?.hasPrefix(Self.commentPrefix) == true)
    }

    @Test("末尾は改行で終わる")
    func endsWithNewline() {
        #expect(Self.contents(ghqRoot: nil).hasSuffix("\n"))
    }
}
