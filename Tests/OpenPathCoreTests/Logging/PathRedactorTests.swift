import Testing

@testable import OpenPathCore

@Suite("PathRedactor")
struct PathRedactorTests {
    @Test(
        "パスとみなせる部分を <path> に置き換える",
        arguments: [
            ("/Users/alice/project", "<path>"),
            ("opened /Users/alice/project", "opened <path>"),
            ("opened ~/repo now", "opened <path> now"),
            ("url=file:///tmp/a", "url=<path>"),
            ("\"/Users/alice\"", "\"<path>\""),
            ("(/a)(/b)", "(<path>)(<path>)"),
            ("root:/Users/alice", "root:<path>"),
            ("/a, /b", "<path>, <path>"),
            ("パス/Users/alice を開いた", "パス<path> を開いた"),
        ]
    )
    func redactsPaths(message: String, expected: String) {
        #expect(PathRedactor.redact(message) == expected)
    }

    @Test(
        "パスでない文字列は変更しない",
        arguments: [
            "",
            "panel detected",
            "AXDialog/AXSheet",
            "1/2",
            "a / b",
            "~",
            "https://example.com/x",
        ]
    )
    func keepsNonPaths(message: String) {
        #expect(PathRedactor.redact(message) == message)
    }
}
