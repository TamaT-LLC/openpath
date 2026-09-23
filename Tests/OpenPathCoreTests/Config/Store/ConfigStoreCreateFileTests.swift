import Foundation
import Testing

import OpenPathCore

@Suite("ConfigStore: 起動後の既定値の生成（初回起動の案内で権限を付与した後、UX-001 §7）")
@MainActor
struct ConfigStoreCreateFileTests {
    private typealias F = ConfigStoreFixtures

    private let temporaryDirectory: ConfigStoreTemporaryDirectory
    private let directory: URL

    init() throws {
        temporaryDirectory = try ConfigStoreTemporaryDirectory()
        directory = temporaryDirectory.url.appending(path: F.configDirectoryName, directoryHint: .isDirectory)
    }

    private var fileURL: URL {
        directory.appending(path: F.fileName)
    }

    private var filePath: String {
        fileURL.path(percentEncoded: false)
    }

    @Test("起動後に消された設定ファイルを、ghq root を含む既定値で作り直して読み込む")
    func recreatesDeletedFile() async throws {
        let (store, ghq) = F.makeStore(directory: directory, ghqRoot: F.ghqRoot)
        defer { store.stop() }
        await store.start()
        try FileManager.default.removeItem(at: fileURL)

        await store.createFileIfMissing()

        #expect(try ConfigFileWriter.read(fileURL) == DefaultConfigFile.contents(ghqRoot: F.ghqRoot, homeDirectory: F.homeDirectory))
        #expect(store.config == Config(roots: [F.ghqRoot]))
        #expect(store.lastError == nil)
        #expect(await ghq.callCount == 2)
    }

    @Test("設定ファイルがあれば上書きせず、ghq root も問い合わせない")
    func keepsExistingFile() async throws {
        let (store, ghq) = F.makeStore(directory: directory)
        defer { store.stop() }
        await store.start()
        let editedContents = "# 手で書いた設定\ndepth = 4\n"
        try ConfigFileWriter.overwriteInPlace(fileURL, with: editedContents)

        await store.createFileIfMissing()

        #expect(try ConfigFileWriter.read(fileURL) == editedContents)
        #expect(await ghq.callCount == 1)
    }

    @Test("作り直せなければ lastError に generationFailed を公開する")
    func exposesGenerationFailure() async throws {
        let (store, _) = F.makeStore(directory: directory)
        defer { store.stop() }
        await store.start()
        // 設定ディレクトリの位置に通常ファイルを置き、ディレクトリを作れなくする
        try FileManager.default.removeItem(at: directory)
        try Data().write(to: temporaryDirectory.url.appending(path: F.configDirectoryName, directoryHint: .notDirectory))

        await store.createFileIfMissing()

        guard case .generationFailed(let path, _) = store.lastError else {
            Issue.record("lastError が generationFailed ではない: \(String(describing: store.lastError))")
            return
        }
        #expect(path == filePath)
    }

    @Test("start 前は何もしない（生成と読み込みは start に任せる）")
    func doesNothingBeforeStart() async {
        let (store, ghq) = F.makeStore(directory: directory)

        await store.createFileIfMissing()

        #expect(!FileManager.default.fileExists(atPath: filePath))
        #expect(await ghq.callCount == 0)
    }

    @Test("stop 後は何もしない")
    func doesNothingAfterStop() async throws {
        let (store, ghq) = F.makeStore(directory: directory)
        await store.start()
        store.stop()
        try FileManager.default.removeItem(at: fileURL)

        await store.createFileIfMissing()

        #expect(!FileManager.default.fileExists(atPath: filePath))
        #expect(await ghq.callCount == 1)
    }
}
