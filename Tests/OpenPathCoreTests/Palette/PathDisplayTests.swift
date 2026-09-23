import Testing

import OpenPathCore

@Suite("PathDisplay")
struct PathDisplayTests {
    private static let home = "/Users/example"

    // MARK: - 親ディレクトリと末尾要素への分割

    @Test("パスを親ディレクトリと末尾要素に分け、ハイライトもそれぞれへ振り分ける")
    func splitsParentAndLastComponent() {
        // "/Users/example/repos/" は 21 文字なので "fern" は 21 文字目から始まる
        let path = HighlightedText("/Users/example/repos/fern", highlightedOffsets: [1, 21, 22])

        let (parent, lastComponent) = PathDisplay.splitParent(path)

        #expect(parent == HighlightedText("/Users/example/repos", highlightedOffsets: [1]))
        #expect(lastComponent == HighlightedText("fern", highlightedOffsets: [0, 1]))
    }

    @Test(
        "親ディレクトリと末尾要素の境界",
        arguments: [
            (path: "/Users", parent: "/", last: "Users"),
            (path: "/Users/example/", parent: "/Users", last: "example"),
            (path: "fern", parent: "", last: "fern"),
            (path: "/", parent: "/", last: ""),
            (path: "", parent: "", last: ""),
        ]
    )
    func splitBoundaries(path: String, parent: String, last: String) {
        let (actualParent, actualLast) = PathDisplay.splitParent(HighlightedText(path))

        #expect(actualParent.text == parent)
        #expect(actualLast.text == last)
    }

    // MARK: - ホームディレクトリの ~ 表記

    @Test(
        "ホームディレクトリ配下は ~ に置き換える",
        arguments: [
            (path: "/Users/example/repos", expected: "~/repos"),
            (path: "/Users/example", expected: "~"),
            (path: "/Users/example/書類/プロジェクト", expected: "~/書類/プロジェクト"),
        ]
    )
    func abbreviatesHomeDirectory(path: String, expected: String) {
        let result = PathDisplay.abbreviatingHome(HighlightedText(path), homeDirectory: Self.home)

        #expect(result.text == expected)
    }

    @Test(
        "ホームディレクトリ配下でなければそのまま",
        arguments: ["/Users/examples/repos", "/Users/exam", "/opt/homebrew", "/", ""]
    )
    func leavesOtherPathsUntouched(path: String) {
        let result = PathDisplay.abbreviatingHome(HighlightedText(path), homeDirectory: Self.home)

        #expect(result.text == path)
    }

    @Test("ホームディレクトリの末尾スラッシュは無視する")
    func ignoresTrailingSlashOfHomeDirectory() {
        let result = PathDisplay.abbreviatingHome(
            HighlightedText("/Users/example/repos"),
            homeDirectory: Self.home + "/"
        )

        #expect(result.text == "~/repos")
    }

    @Test("ホームディレクトリが空やルートのときは置き換えない", arguments: ["", "/"])
    func doesNotAbbreviateWithDegenerateHome(home: String) {
        let result = PathDisplay.abbreviatingHome(HighlightedText("/Users/example"), homeDirectory: home)

        #expect(result.text == "/Users/example")
    }

    @Test("ホームより後ろのハイライトは ~ に詰めた分だけ前にずらし、ホーム内のハイライトは ~ に集約する")
    func remapsHighlightsWhenAbbreviatingHome() {
        // "/Users/example" は 14 文字なので "repos" の r は 15 文字目
        let path = HighlightedText("/Users/example/repos", highlightedOffsets: [7, 8, 15])

        let result = PathDisplay.abbreviatingHome(path, homeDirectory: Self.home)

        #expect(result == HighlightedText("~/repos", highlightedOffsets: [0, 2]))
    }

    @Test("日本語のホームディレクトリは正規化形式（NFC / NFD）が違っても同じとみなす")
    func abbreviatesHomeRegardlessOfNormalization() {
        // 「ユーザー」の NFC と、「ザ」を NFD（サ + 結合用濁点）で表したもの
        let composedHome = "/Users/\u{30E6}\u{30FC}\u{30B6}\u{30FC}"
        let decomposedPath = "/Users/\u{30E6}\u{30FC}\u{30B5}\u{3099}\u{30FC}/書類"

        let result = PathDisplay.abbreviatingHome(HighlightedText(decomposedPath), homeDirectory: composedHome)

        #expect(result.text == "~/書類")
    }

    // MARK: - 中央省略

    @Test("中央のディレクトリから … に置き換えた候補を、省略の少ない順に返す")
    func middleTruncationsOfHomePath() {
        let variants = PathDisplay.middleTruncations(HighlightedText("~/repos/github.com/TamaT-LLC"))

        #expect(variants.map(\.text) == [
            "~/repos/github.com/TamaT-LLC",
            "~/repos/…/TamaT-LLC",
            "~/…/TamaT-LLC",
        ])
    }

    @Test("絶対パスは先頭のルートと末尾のディレクトリを残す")
    func middleTruncationsOfAbsolutePath() {
        let variants = PathDisplay.middleTruncations(HighlightedText("/Volumes/data/a/b"))

        #expect(variants.map(\.text) == [
            "/Volumes/data/a/b",
            "/Volumes/…/a/b",
            "/Volumes/…/b",
            "/…/b",
        ])
    }

    @Test("省略できる中間のディレクトリがなければ元のパスだけを返す", arguments: ["~/repos", "~", "/Users", "/", ""])
    func shortPathsAreNotTruncated(path: String) {
        let variants = PathDisplay.middleTruncations(HighlightedText(path))

        #expect(variants.map(\.text) == [path])
    }

    @Test("残したディレクトリのハイライトは位置を詰め、省略したディレクトリのハイライトは … に集約する")
    func remapsHighlightsWhenTruncating() {
        // ~:0 /:1 repos:2-6 /:7 github.com:8-17 /:18 TamaT-LLC:19-27
        let path = HighlightedText("~/repos/github.com/TamaT-LLC", highlightedOffsets: [2, 10, 19])

        let variants = PathDisplay.middleTruncations(path)

        #expect(variants == [
            path,
            HighlightedText("~/repos/…/TamaT-LLC", highlightedOffsets: [2, 8, 10]),
            HighlightedText("~/…/TamaT-LLC", highlightedOffsets: [2, 4]),
        ])
    }

    @Test("省略したディレクトリにハイライトがなければ … はハイライトしない")
    func ellipsisIsPlainWithoutElidedHighlights() {
        let path = HighlightedText("~/repos/github.com/TamaT-LLC", highlightedOffsets: [19])

        let variants = PathDisplay.middleTruncations(path)

        #expect(variants.map(\.highlightedOffsets) == [[19], [10], [4]])
    }
}
