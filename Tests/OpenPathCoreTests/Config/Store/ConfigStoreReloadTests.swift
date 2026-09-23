import Foundation
import Testing

import OpenPathCore

/// `reload()` を直接呼び、読み込み結果の反映を実時間の監視に依存せず確かめる。
@Suite("ConfigStore: 読み込みと失敗時の維持")
@MainActor
struct ConfigStoreReloadTests {
    private typealias F = ConfigStoreFixtures

    private static let validContents = "depth = 5\nhotkey = \"cmd+shift+p\"\n"
    private static let validConfig = Config(depth: 5, hotkey: Hotkey(key: .p, modifiers: [.command, .shift]))
    /// 2 行目の値が無い不正な TOML
    private static let invalidTOML = "depth = 3\nhotkey = \n"
    private static let invalidTOMLLine = 2
    /// TOML としては正しいがデコードできない値
    private static let undecodableContents = "depth = -1\n"

    private let temporaryDirectory: ConfigStoreTemporaryDirectory
    private let store: ConfigStore

    init() throws {
        temporaryDirectory = try ConfigStoreTemporaryDirectory()
        store = F.makeStore(directory: temporaryDirectory.url).store
    }

    private var fileURL: URL {
        store.fileURL
    }

    private var filePath: String {
        fileURL.path(percentEncoded: false)
    }

    /// 有効な設定を読み込んだ状態にする
    private func startWithValidFile() async throws {
        try ConfigFileWriter.create(fileURL, with: Self.validContents)
        await store.start()
        #expect(store.config == Self.validConfig)
        #expect(store.lastError == nil)
    }

    private func rewrite(_ contents: String) throws {
        try ConfigFileWriter.overwriteInPlace(fileURL, with: contents)
    }

    // MARK: - 失敗時の維持（TST-001 §2.3）

    @Test("不正 TOML: 直前の設定が維持され、lastError が非 nil（TST-001 §2.3）")
    func keepsPreviousConfigOnParseError() async throws {
        try await startWithValidFile()
        defer { store.stop() }

        try rewrite(Self.invalidTOML)
        store.reload()

        #expect(store.config == Self.validConfig)
        let error = try #require(store.lastError)
        guard case .parseFailed(let path, let parseError) = error else {
            Issue.record("lastError が parseFailed ではない: \(error)")
            return
        }
        #expect(path == filePath)
        #expect(parseError.line == Self.invalidTOMLLine)
        #expect(parseError.kind == .missingValue)
    }

    @Test("デコードできない値: 直前の設定が維持され、lastError に decodeFailed を公開する")
    func keepsPreviousConfigOnDecodingError() async throws {
        try await startWithValidFile()
        defer { store.stop() }

        try rewrite(Self.undecodableContents)
        store.reload()

        #expect(store.config == Self.validConfig)
        #expect(store.lastError == .decodeFailed(
            path: filePath,
            ConfigDecodingError(key: "depth", kind: .belowMinimum(value: -1, minimum: Config.minimumDepth))
        ))
    }

    @Test("ファイルが消えていたら直前の設定を維持し、lastError に fileNotFound を公開する")
    func keepsPreviousConfigWhenFileIsMissing() async throws {
        try await startWithValidFile()
        defer { store.stop() }

        try FileManager.default.removeItem(at: fileURL)
        store.reload()

        #expect(store.config == Self.validConfig)
        #expect(store.lastError == .fileNotFound(path: filePath))
    }

    @Test("UTF-8 として読めないファイルは直前の設定を維持し、lastError に readFailed を公開する")
    func keepsPreviousConfigWhenFileIsNotUTF8() async throws {
        try await startWithValidFile()
        defer { store.stop() }

        let invalidUTF8: [UInt8] = [0xFF, 0xFE, 0xFD]
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(invalidUTF8))
        try handle.close()
        store.reload()

        #expect(store.config == Self.validConfig)
        guard case .readFailed(let path, _) = store.lastError else {
            Issue.record("lastError が readFailed ではない: \(String(describing: store.lastError))")
            return
        }
        #expect(path == filePath)
    }

    @Test("読み込みに成功すると新しい設定を反映し、lastError は nil に戻る")
    func clearsLastErrorAfterSuccessfulReload() async throws {
        try await startWithValidFile()
        defer { store.stop() }
        try rewrite(Self.invalidTOML)
        store.reload()
        #expect(store.lastError != nil)

        try rewrite("depth = 7\n")
        store.reload()

        #expect(store.config == Config(depth: 7))
        #expect(store.lastError == nil)
    }

    // MARK: - 警告

    @Test("未知のキーは warnings に公開し、既知のキーは反映する")
    func exposesUnknownKeyWarnings() async throws {
        try await startWithValidFile()
        defer { store.stop() }

        try rewrite("depth = 3\nunknown_key = 1\n\n[ghq]\nenabeld = false\n")
        store.reload()

        #expect(store.config == Config(depth: 3))
        #expect(store.warnings == [.unknownKey("ghq.enabeld"), .unknownKey("unknown_key")])
        #expect(store.lastError == nil)
    }

    @Test("未知のキーを消して読み込み直すと warnings は空に戻る")
    func clearsWarningsAfterFix() async throws {
        try await startWithValidFile()
        defer { store.stop() }
        try rewrite("depth = 3\nunknown_key = 1\n")
        store.reload()
        #expect(!store.warnings.isEmpty)

        try rewrite("depth = 3\n")
        store.reload()

        #expect(store.warnings.isEmpty)
    }

    @Test("読み込みに失敗しても warnings は有効な設定のものを維持する")
    func keepsWarningsOnFailure() async throws {
        try await startWithValidFile()
        defer { store.stop() }
        try rewrite("depth = 3\nunknown_key = 1\n")
        store.reload()

        try rewrite(Self.invalidTOML)
        store.reload()

        #expect(store.config == Config(depth: 3))
        #expect(store.warnings == [.unknownKey("unknown_key")])
    }
}
