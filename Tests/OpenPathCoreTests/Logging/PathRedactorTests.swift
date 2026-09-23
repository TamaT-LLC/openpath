import Testing

@testable import OpenPathCore

/// パスの開始を検出したら、その位置からメッセージの末尾までを伏せる。
/// パスの終端は判別できないため、後続の文脈が失われることは許容する。
@Suite("PathRedactor")
struct PathRedactorTests {
    @Test(
        "パスの開始位置からメッセージの末尾までを <path> に置き換える",
        arguments: [
            ("/Users/alice/project", "<path>"),
            ("opened /Users/alice/project", "opened <path>"),
            ("opened /Users/alice/project in 12ms", "opened <path>"),
            ("url=file:///tmp/a", "url=<path>"),
            ("root:/Users/alice", "root:<path>"),
            ("パス/Users/alice を開いた", "パス<path>"),
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
        "引用符・括弧で囲まれたパスも閉じ記号で打ち切らず、末尾まで伏せる",
        arguments: [
            // 閉じ記号はファイル名の一部にもなり得るため、終端とみなさない
            ("opened \"/Users/alice/report\".secret\" in 12ms", "opened \"<path>"),
            ("\"/Users/alice\"", "\"<path>"),
            ("(/a)(/b)", "(<path>"),
            ("opened \"/Users/alice/My File.txt\" in 12ms", "opened \"<path>"),
            ("opened '/Users/alice/Bob's Notes.txt' in 12ms", "opened '<path>"),
            ("opened `~/My Projects/app` in 12ms", "opened `<path>"),
            ("opened (/Users/alice/My Docs) in 12ms", "opened (<path>"),
            ("opened [file:///Users/alice/My Docs] in 12ms", "opened [<path>"),
            ("opened “/Users/alice/My Docs” in 12ms", "opened “<path>"),
            ("「/Users/alice/My Docs」を開いた", "「<path>"),
        ]
    )
    func redactsQuotedPathsToEndOfMessage(message: String, expected: String) {
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
