import Testing

import OpenPathCore

@Suite("DefaultConfigFile: 既定の config.toml")
struct DefaultConfigFileTests {
    private static let homeDirectory = "/Users/tester"
    private static let decoder = ConfigDecoder(homeDirectory: homeDirectory)
    private static let commentPrefix = "#"
    private static let tableHeaderPrefix = "["
    private static let rootsKeyPrefix = "roots = "
    /// ghq root が無いときに書く roots の行（ホームディレクトリを `~` で書く）
    private static let homeRootsLine = "roots = [\"~\"]"

    private static func contents(ghqRoot: String?) -> String {
        DefaultConfigFile.contents(ghqRoot: ghqRoot, homeDirectory: homeDirectory)
    }

    /// 生成した TOML を ConfigStore と同じ手順（パース → デコード）で読み戻す
    private static func readBack(_ contents: String) throws -> ConfigDecodingResult {
        try decoder.decode(TOMLParser.parse(contents))
    }

    private static func lines(of contents: String) -> [String] {
        contents.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    /// roots の行の直前に続くコメント行をつないだもの（利用者が roots を編集するときに読む説明）
    private static func rootsComment(in contents: String) -> String {
        let contentLines = Self.lines(of: contents)
        guard let rootsIndex = contentLines.firstIndex(where: { $0.hasPrefix(rootsKeyPrefix) }) else { return "" }
        let commentLines = contentLines[..<rootsIndex].reversed().prefix { $0.hasPrefix(commentPrefix) }
        return commentLines.reversed().joined(separator: "\n")
    }

    // MARK: - 読み戻し

    @Test("ghq root を roots に含み、読み戻すと roots 以外は既定値の Config になる（TST-001 §2.3）")
    func readsBackWithGhqRoot() throws {
        let result = try Self.readBack(Self.contents(ghqRoot: "/Users/tester/ghq"))

        #expect(result.config == Config(roots: ["/Users/tester/ghq"]))
        #expect(result.warnings.isEmpty)
    }

    @Test("ghq root が無ければ roots はホーム（~）で、読み戻すとホームディレクトリに展開される")
    func readsBackWithoutGhqRoot() throws {
        let contents = Self.contents(ghqRoot: nil)
        let result = try Self.readBack(contents)

        #expect(contents.contains("\n\(Self.homeRootsLine)\n"))
        #expect(result.config == Config(roots: [Self.homeDirectory]))
        #expect(result.warnings.isEmpty)
    }

    @Test(
        "ホームを ~ で書くため、読み戻したときの展開先は読み込む側のホームディレクトリになる（dotfiles で共有しても使える）",
        arguments: ["/Users/another", "/Users/another/", "/Volumes/Home/me"]
    )
    func homeFallbackExpandsToReadersHome(readerHomeDirectory: String) throws {
        let contents = DefaultConfigFile.contents(ghqRoot: nil, homeDirectory: Self.homeDirectory)
        let resolvedHome = try #require(RootPathResolver(homeDirectory: readerHomeDirectory).resolve(readerHomeDirectory))

        let result = try ConfigDecoder(homeDirectory: readerHomeDirectory).decode(TOMLParser.parse(contents))

        #expect(result.config.roots == [resolvedHome])
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
        "絶対パスに解決できない ghq root は使わず、ghq root が無いときと同じくホーム（~）にする",
        arguments: ["", "relative/ghq", "~other/ghq"]
    )
    func fallsBackToHomeForUnresolvableGhqRoot(ghqRoot: String) throws {
        let contents = Self.contents(ghqRoot: ghqRoot)

        #expect(contents == Self.contents(ghqRoot: nil))
        #expect(try Self.readBack(contents).config == Config(roots: [Self.homeDirectory]))
    }

    @Test(
        "~ を絶対パスに展開できないホームでは、生成したファイルが読めなくならないよう roots を空にする",
        arguments: ["", "relative/home"]
    )
    func writesEmptyRootsWhenHomeIsUnresolvable(homeDirectory: String) throws {
        let contents = DefaultConfigFile.contents(ghqRoot: nil, homeDirectory: homeDirectory)

        let result = try ConfigDecoder(homeDirectory: homeDirectory).decode(TOMLParser.parse(contents))

        #expect(contents.contains("\nroots = []\n"))
        #expect(result.config == .default)
        #expect(!Self.rootsComment(in: contents).contains("見つからなかった"))
    }

    // MARK: - roots のコメント

    @Test("ghq root が無いときは、ホームを検索対象にした理由と、絞り込むには roots を書き換えることをコメントで伝える")
    func explainsHomeFallbackInRootsComment() {
        let comment = Self.rootsComment(in: Self.contents(ghqRoot: nil))

        #expect(comment.contains("ghq の root が見つからなかったため、ホームディレクトリ（~）を検索対象にしています"))
        #expect(comment.contains("絞り込みたいときは、roots をよく使うディレクトリに書き換えてください"))
    }

    @Test("ghq root があるときは、ghq の root を検索対象にしたことをコメントで伝え、ホームにした旨は書かない")
    func explainsGhqRootInRootsComment() {
        let comment = Self.rootsComment(in: Self.contents(ghqRoot: "/Users/tester/ghq"))

        #expect(comment.contains("ghq の root を検索対象にしています"))
        #expect(!comment.contains("見つからなかった"))
    }

    // MARK: - 人が編集しやすい形

    @Test("DSN-002 §6 のキーをすべて既定値で含む（disabled_apps は空）")
    func containsAllDesignKeys() {
        let lines = Self.lines(of: Self.contents(ghqRoot: nil))

        for expectedLine in [
            Self.homeRootsLine,
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

    @Test("各キーの直前（空行を除く）にコメントがある", arguments: [nil, "/Users/tester/ghq"])
    func everyKeyHasComment(ghqRoot: String?) {
        let lines = Self.contents(ghqRoot: ghqRoot).split(separator: "\n").map(String.init)

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
