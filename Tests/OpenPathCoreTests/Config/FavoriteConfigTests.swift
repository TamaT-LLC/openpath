import Testing
import OpenPathCore

@Suite("Config: お気に入り")
struct FavoriteConfigTests {
    @Test("引用符付きの別名とパスをデコードし、~ とパス表記を正規化する")
    func decodesAliasesAndPaths() throws {
        let result = try ConfigTestSupport.decode("""
            [favorites]
            "仕事" = "~/repos//work/"
            "請求書" = "/opt/docs/../invoices"
            "with spaces" = "~/my files"
            """)
        #expect(result.warnings.isEmpty)
        #expect(result.config.favorites == [
            Favorite(name: "with spaces", path: "/Users/tester/my files"),
            Favorite(name: "仕事", path: "/Users/tester/repos/work"),
            Favorite(name: "請求書", path: "/opt/invoices"),
        ])
        #expect(try ConfigTestSupport.decode("").config.favorites.isEmpty)
        #expect(try ConfigTestSupport.decode("[favorites]").config.favorites.isEmpty)
    }

    /// 別名マップの誤りを個別に検証し、不正な登録を黙って捨てないことを確かめる。
    @Test("値の型・空の別名・相対パス・同じパスの二重登録を設定エラーにする")
    func rejectsInvalidFavorites() throws {
        let cases: [(String, ConfigDecodingError)] = [
            ("favorites = []", .init(key: "favorites", kind: .typeMismatch(expected: .table, actual: .stringArray))),
            ("[favorites]\nwork = true", .init(key: "favorites.work", kind: .typeMismatch(expected: .string, actual: .bool))),
            ("[favorites]\n\" \" = \"/opt/work\"", .init(key: "favorites. ", kind: .emptyFavoriteName)),
            ("[favorites]\nwork = \"relative\"", .init(key: "favorites.work", kind: .invalidRootPath("relative"))),
            ("[favorites]\na = \"~/work\"\nb = \"/Users/tester/work/\"", .init(key: "favorites.b", kind: .duplicateFavoritePath("/Users/tester/work"))),
        ]
        for (source, error) in cases {
            #expect(throws: error) { try ConfigTestSupport.decode(source) }
        }
    }

    @Test("初回生成した設定は空のお気に入りテーブルを含み、既定値で読める")
    func generatedConfigRoundTrips() throws {
        let source = DefaultConfigFile.contents(ghqRoot: nil, homeDirectory: "/Users/tester")
        let result = try ConfigTestSupport.decode(source)
        #expect(source.contains("[favorites]"))
        #expect(result.config.favorites.isEmpty)
        #expect(result.warnings.isEmpty)
    }
}
