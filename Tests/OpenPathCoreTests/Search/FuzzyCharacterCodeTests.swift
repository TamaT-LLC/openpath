import Foundation
import Testing

import OpenPathCore

/// 前処理済みの対象を文字コードで持つようにしても、一致の判定が Character の一致（正準等価）と変わらないこと。
/// 既定の正規化（NFC 合成済み）を通らない場合も確かめるため、大文字小文字だけを揃える正規化を使う。
@Suite("FuzzyMatcher: 文字コードによる比較")
struct FuzzyCharacterCodeTests {
    private let matcher = FuzzyMatcher(normalizer: LowercaseNormalizer())

    @Test(
        "正準等価な文字どうしは、合成済みか分解済みかに関わらず一致する",
        arguments: [
            ("\u{00E9}", "e\u{0301}"),
            ("e\u{0301}", "\u{00E9}"),
            // U+212B ANGSTROM SIGN と U+00C5（単独の文字どうしの正準等価）
            ("\u{212B}", "\u{00C5}"),
            // U+037E GREEK QUESTION MARK と ASCII のセミコロン
            ("\u{037E}", ";"),
            (";", "\u{037E}"),
        ]
    )
    func canonicallyEquivalentCharactersMatch(query: String, text: String) throws {
        #expect(Character(query) == Character(text))

        let match = try #require(matcher.score(query: query, in: text))

        #expect(match.positions == [0])
    }

    @Test("正準等価でない文字は一致しない", arguments: [("\u{00E9}", "e"), ("が", "か"), ("👍🏻", "👍")])
    func distinctCharactersDoNotMatch(query: String, text: String) {
        #expect(Character(query) != Character(text))
        #expect(matcher.score(query: query, in: text) == nil)
    }

    @Test("複数のスカラーからなる文字（絵文字の結合・合成済みの無い濁点付きかな）も 1 文字として一致する")
    func multiScalarCharactersMatchAsOneCharacter() throws {
        let text = "a👨‍👩‍👧か\u{309A}b"

        let match = try #require(matcher.score(query: "👨‍👩‍👧か\u{309A}", in: text))

        #expect(match.positions == [1, 2])
    }

    /// 他のテストで使わない文字（CJK 統合漢字拡張 A）を、多数のタスクで同時に初めて前処理させる
    @Test("別々のタスクで同時に前処理しても、同じ文字には同じコードが付く")
    func preparesConcurrently() async throws {
        let firstScalar: UInt32 = 0x3440
        let characterCount: UInt32 = 32
        let taskCount = 64
        let text = String(String.UnicodeScalarView((firstScalar..<firstScalar + characterCount).compactMap(Unicode.Scalar.init)))
        let defaultMatcher = FuzzyMatcher()

        let targets = await withTaskGroup(of: FuzzyTarget.self) { group in
            for _ in 0..<taskCount {
                group.addTask { defaultMatcher.prepareTarget(text) }
            }
            return await group.reduce(into: []) { $0.append($1) }
        }

        let query = defaultMatcher.prepareQuery(text)
        #expect(targets.count == taskCount)
        for target in targets {
            #expect(defaultMatcher.score(query: query, in: target)?.positions == Array(0..<Int(characterCount)))
        }
    }
}
