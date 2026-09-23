import Testing

import OpenPathCore

@Suite("ConfigStoreError: 利用者向けの説明")
struct ConfigStoreErrorTests {
    private static let path = "/Users/tester/.config/openpath/config.toml"
    private static let reason = "Permission denied"

    @Test("ファイルが無いときは場所を示す")
    func describesFileNotFound() {
        let error = ConfigStoreError.fileNotFound(path: Self.path)

        #expect(error.description == "設定ファイル \(Self.path) が見つかりません")
    }

    @Test("読めないときは理由を添える")
    func describesReadFailure() {
        let error = ConfigStoreError.readFailed(path: Self.path, reason: Self.reason)

        #expect(error.description == "設定ファイル \(Self.path) を読めません（\(Self.reason)）")
    }

    @Test("TOML の誤りは行と列を含む")
    func describesParseFailure() {
        let parseError = TOMLParseError(line: 2, column: 9, kind: .missingValue)
        let error = ConfigStoreError.parseFailed(path: Self.path, parseError)

        #expect(error.description == "設定ファイル \(Self.path) の書式が誤っているため反映していません（2 行 9 列: 値がありません）")
    }

    @Test("値の誤りはキーを含む")
    func describesDecodeFailure() {
        let decodingError = ConfigDecodingError(key: "depth", kind: .belowMinimum(value: -1, minimum: 0))
        let error = ConfigStoreError.decodeFailed(path: Self.path, decodingError)

        #expect(error.description == "設定ファイル \(Self.path) の値が誤っているため反映していません（\(decodingError.description)）")
    }

    @Test("生成に失敗したときは既定の設定で動くことを示す")
    func describesGenerationFailure() {
        let error = ConfigStoreError.generationFailed(path: Self.path, reason: Self.reason)

        #expect(error.description == "設定ファイル \(Self.path) を作成できません（\(Self.reason)）。既定の設定で動作します")
    }
}
