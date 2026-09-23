import Testing

import OpenPathCore

@Suite("RootPathResolver: ~ 展開と正規化")
struct RootPathResolverTests {
    private static let homeDirectory = "/Users/tester"

    private let resolver = RootPathResolver(homeDirectory: homeDirectory)

    @Test(
        "~ と ~/... をホームディレクトリで展開する（TST-001 §2.3）",
        arguments: [
            ("~", "/Users/tester"),
            ("~/", "/Users/tester"),
            ("~/repos", "/Users/tester/repos"),
            ("~/repos/github.com", "/Users/tester/repos/github.com"),
            ("~/日本語 フォルダ", "/Users/tester/日本語 フォルダ"),
        ]
    )
    func expandsTilde(path: String, expected: String) {
        #expect(resolver.resolve(path) == expected)
    }

    @Test(
        "末尾の / と、空・. の要素を取り除く",
        arguments: [
            ("~/repos/", "/Users/tester/repos"),
            ("~/repos///", "/Users/tester/repos"),
            ("/opt/src/", "/opt/src"),
            ("//opt//src", "/opt/src"),
            ("/opt/./src/.", "/opt/src"),
            ("/", "/"),
            ("//", "/"),
        ]
    )
    func normalizesSeparators(path: String, expected: String) {
        #expect(resolver.resolve(path) == expected)
    }

    @Test(
        ".. はファイルシステムを参照せず字句的に 1 つ上へ解決する（ルートより上には出ない）",
        arguments: [
            ("/opt/work/../src", "/opt/src"),
            ("~/../shared", "/Users/shared"),
            ("/..", "/"),
            ("/opt/../../src", "/src"),
        ]
    )
    func resolvesParentReferences(path: String, expected: String) {
        #expect(resolver.resolve(path) == expected)
    }

    @Test("~ を途中に含むパスは展開しない")
    func tildeInMiddleIsLiteral() {
        #expect(resolver.resolve("/opt/with~tilde/~") == "/opt/with~tilde/~")
    }

    @Test(
        "絶対パスにならないものは nil（相対パス、他ユーザーの ~user、先頭の空白）",
        arguments: ["", "repos", "./repos", "../repos", "~other", "~other/repos", " ~/repos", " /opt"]
    )
    func rejectsNonAbsolutePaths(path: String) {
        #expect(resolver.resolve(path) == nil)
    }

    @Test("ホームディレクトリ自体の末尾の / も正規化する")
    func normalizesHomeDirectory() {
        let resolver = RootPathResolver(homeDirectory: "/Users/tester/")

        #expect(resolver.resolve("~") == "/Users/tester")
        #expect(resolver.resolve("~/repos") == "/Users/tester/repos")
    }
}
