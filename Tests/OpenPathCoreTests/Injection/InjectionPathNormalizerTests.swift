import Foundation
import Testing

import OpenPathCore

@Suite("InjectionPathNormalizer: 注入前のパス正規化（DSN-001 §4）")
struct InjectionPathNormalizerTests {
    private static let home = "/Users/me"
    private let normalizer = InjectionPathNormalizer(homeDirectory: home)

    @Test(
        "`~` を展開し、`.`・`..`・空要素・末尾の `/` を取り除く",
        arguments: [
            ("/Users/me/repos", "/Users/me/repos"),
            ("/Users/me/repos/", "/Users/me/repos"),
            ("/Users/me/repos//", "/Users/me/repos"),
            ("/", "/"),
            ("~", "/Users/me"),
            ("~/", "/Users/me"),
            ("~/repos/github.com", "/Users/me/repos/github.com"),
            ("/Users/me/repos/../Documents", "/Users/me/Documents"),
            ("/Users/./me//repos/.", "/Users/me/repos"),
            ("/../Users", "/Users"),
            // `~` の展開後に `..` を解く
            ("~/a/../../b", "/Users/b"),
        ]
    )
    func normalizes(input: String, expected: String) {
        #expect(normalizer.normalize(input) == expected)
    }

    @Test(
        "スペース・URL の予約文字・日本語はそのまま残す",
        arguments: [
            ("/Users/me/My Folder/", "/Users/me/My Folder"),
            ("/Users/me/a#b?c%20d", "/Users/me/a#b?c%20d"),
            ("/Users/me/Documents/資料/", "/Users/me/Documents/資料"),
            ("~/書類/../資料", "/Users/me/資料"),
        ]
    )
    func keepsSpecialCharacters(input: String, expected: String) {
        #expect(normalizer.normalize(input) == expected)
    }

    @Test("Unicode の正規化形（NFC / NFD）を変えない。ファイルシステムから得た表記のまま貼り付けるため")
    func preservesUnicodeNormalizationForm() {
        let nfc = "/Users/me/資料/がぱ"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        #expect(Array(nfc.utf8) != Array(nfd.utf8))

        #expect(Array(normalizer.normalize(nfc + "/").utf8) == Array(nfc.utf8))
        #expect(Array(normalizer.normalize(nfd + "/").utf8) == Array(nfd.utf8))
    }

    @Test("シンボリックリンクは解決しない（ghq のリンク運用を壊さないため）")
    func doesNotResolveSymbolicLinks() throws {
        // macOS の /tmp は /private/tmp へのシンボリックリンク
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: "/tmp") == "private/tmp")

        #expect(normalizer.normalize("/tmp/openpath/") == "/tmp/openpath")
        #expect(normalizer.normalize("/tmp/openpath/..") == "/tmp")
    }

    @Test(
        "絶対パスに解決できないもの（相対パス、`~user` 形式）はそのまま返す",
        arguments: ["relative/path", "./x", "~other/repos", ""]
    )
    func leavesUnresolvablePathUnchanged(input: String) {
        #expect(normalizer.normalize(input) == input)
    }

    @Test(
        "DSN-001 §4 の URL(fileURLWithPath:).standardizedFileURL.path と正準等価な結果になる",
        arguments: [
            "/Users/me/repos/",
            "/",
            "/Users/./me//repos/../Documents/",
            "/../Users",
            "/Users/me/My Folder/a#b?c%20d",
            "/Users/me/Documents/資料/",
            "/tmp/openpath/..",
        ]
    )
    func matchesStandardizedFileURL(input: String) {
        let standardized = URL(fileURLWithPath: input, isDirectory: false).standardizedFileURL.path

        // String の == は正準等価で比べる（URL は NFC を NFD に変えるため、バイト列は一致しない場合がある）
        #expect(normalizer.normalize(input) == standardized)
    }

    @Test("ホームディレクトリの末尾に `/` があっても二重にしない")
    func homeDirectoryWithTrailingSlash() {
        let normalizer = InjectionPathNormalizer(homeDirectory: "/Users/me/")

        #expect(normalizer.normalize("~/repos") == "/Users/me/repos")
    }

    @Test("既定のホームディレクトリは実行中のユーザーのもの")
    func defaultHomeDirectory() {
        #expect(InjectionPathNormalizer().normalize("~") == NSHomeDirectory())
    }
}
