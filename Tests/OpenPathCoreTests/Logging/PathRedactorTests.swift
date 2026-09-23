import Testing

@testable import OpenPathCore

@Suite("PathRedactor")
struct PathRedactorTests {
    @Test(
        "パスの開始位置からメッセージの末尾までを <path> に置き換える",
        arguments: [
            ("/Users/alice/project", "<path>"),
            ("opened /Users/alice/project", "opened <path>"),
            ("url=file:///tmp/a", "url=<path>"),
            ("root:/Users/alice", "root:<path>"),
            ("パス/Users/alice を開いた", "パス<path>"),
            // 後続がパスの続きか通常の文かは判別できないため、2 つ目のパスも含めて末尾まで伏せる
            ("/a, /b", "<path>"),
        ]
    )
    func redactsToEndOfMessage(message: String, expected: String) {
        #expect(PathRedactor.redact(message) == expected)
    }

    @Test(
        "空白を含むパスは断片を残さずに伏せる",
        arguments: [
            ("opened /Users/alice/My Documents/secret.txt", "opened <path>"),
            // 連続する空白
            ("opened /Users/alice/My  Project   Files/notes.md", "opened <path>"),
            // 最後の断片に "/" が無いファイル名・ディレクトリ名
            ("opened /Users/alice/My File.txt", "opened <path>"),
            ("opened /Users/alice/My Documents", "opened <path>"),
            ("opened ~/My Projects/app name", "opened <path>"),
            ("url=file:///Users/alice/My Docs/a b.txt", "url=<path>"),
            // エラーの説明文がファイル名を繰り返すケース
            ("failed /Users/alice/My File.txt: The file “My File.txt” couldn’t be opened.", "failed <path>"),
        ]
    )
    func redactsPathsContainingSpaces(message: String, expected: String) {
        #expect(PathRedactor.redact(message) == expected)
    }

    @Test(
        "引用符・括弧で囲まれたパスは閉じ記号の直前までを伏せ、後続の文を残す",
        arguments: [
            ("\"/Users/alice\"", "\"<path>\""),
            ("(/a)(/b)", "(<path>)(<path>)"),
            ("opened \"/Users/alice/My File.txt\" in 12ms", "opened \"<path>\" in 12ms"),
            // 英数字が続くアポストロフィは閉じ記号とみなさない
            ("opened '/Users/alice/Bob's Notes.txt' in 12ms", "opened '<path>' in 12ms"),
            ("opened `~/My Projects/app` in 12ms", "opened `<path>` in 12ms"),
            ("opened (/Users/alice/My Docs) in 12ms", "opened (<path>) in 12ms"),
            ("opened [file:///Users/alice/My Docs] in 12ms", "opened [<path>] in 12ms"),
            ("opened “/Users/alice/My Docs” in 12ms", "opened “<path>” in 12ms"),
            ("「/Users/alice/My Docs」を開いた", "「<path>」を開いた"),
            // 閉じ記号が無ければ末尾まで伏せる
            ("opened \"/Users/alice/My File.txt", "opened \"<path>"),
        ]
    )
    func redactsQuotedPaths(message: String, expected: String) {
        #expect(PathRedactor.redact(message) == expected)
    }

    @Test(
        "パスを含まない通常の文は変更しない",
        arguments: [
            "",
            "panel detected",
            "palette shown in 12 ms",
            "AXDialog/AXSheet",
            "1/2",
            "a / b",
            "~",
            "https://example.com/x",
            "read/write and/or TCP/IP",
            "I/O error (errno 5)",
            "hotkey ⌘/ pressed",
            "2026/09/23 12:00, depth 3/6",
            "status \"ok/ng\" (1/2)",
        ]
    )
    func keepsNonPaths(message: String) {
        #expect(PathRedactor.redact(message) == message)
    }
}
