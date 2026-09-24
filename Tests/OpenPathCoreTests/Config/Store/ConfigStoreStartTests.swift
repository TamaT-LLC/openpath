import Foundation
import Testing

import OpenPathCore

@Suite("ConfigStore: 起動と既定値の生成")
@MainActor
struct ConfigStoreStartTests {
    private typealias F = ConfigStoreFixtures

    private let temporaryDirectory: ConfigStoreTemporaryDirectory
    /// 設定ファイルを置くディレクトリ。未作成の状態から始める
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

    private func writeExistingFile(_ contents: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ConfigFileWriter.create(fileURL, with: contents)
    }

    // MARK: - 設定ファイルの場所

    @Test("既定の設定ファイルは ~/.config/openpath/config.toml")
    func defaultLocationIsDotConfig() {
        let directory = ConfigStore.defaultDirectory(homeDirectory: F.homeDirectory)

        #expect(directory.path(percentEncoded: false) == "/Users/tester/.config/openpath/")
        #expect(ConfigStore.fileName == "config.toml")
    }

    @Test("設定ファイルは指定したディレクトリの config.toml")
    func fileURLIsInDirectory() {
        let (store, _) = F.makeStore(directory: directory)

        #expect(store.fileURL == fileURL)
    }

    @Test("起動前は既定の設定で、エラーも警告も無い")
    func initialStateIsDefault() {
        let (store, _) = F.makeStore(directory: directory)

        #expect(store.config == .default)
        #expect(store.lastError == nil)
        #expect(store.warnings.isEmpty)
    }

    // MARK: - 既定値の生成（UX-001 §7）

    @Test("既定値生成: ファイルが無ければ ghq root（モック）を roots に含む config.toml を生成して読み込む（TST-001 §2.3）")
    func generatesDefaultFileWithGhqRoot() async throws {
        let (store, ghq) = F.makeStore(directory: directory, ghqRoot: F.ghqRoot)
        defer { store.stop() }

        await store.start()

        let contents = try ConfigFileWriter.read(fileURL)
        #expect(contents == DefaultConfigFile.contents(ghqRoot: F.ghqRoot, homeDirectory: F.homeDirectory))
        #expect(store.config == Config(roots: [F.ghqRoot]))
        #expect(store.lastError == nil)
        #expect(store.warnings.isEmpty)
        #expect(await ghq.callCount == 1)
    }

    @Test("生成したファイルは ConfigDecoder で読み戻せ、ストアの設定と一致する")
    func generatedFileReadsBackWithDecoder() async throws {
        let (store, _) = F.makeStore(directory: directory, ghqRoot: F.ghqRoot)
        defer { store.stop() }

        await store.start()

        let table = try TOMLParser.parse(ConfigFileWriter.read(fileURL))
        let result = try ConfigDecoder(homeDirectory: F.homeDirectory).decode(table)
        #expect(result.config == store.config)
        #expect(result.warnings.isEmpty)
    }

    @Test("ghq root が取れなければ roots をホーム（~）にして生成し、ホームディレクトリを走査する設定で読み込む")
    func generatesDefaultFileWithoutGhqRoot() async throws {
        let (store, _) = F.makeStore(directory: directory, ghqRoot: nil)
        defer { store.stop() }

        await store.start()

        let contents = try ConfigFileWriter.read(fileURL)
        #expect(contents == DefaultConfigFile.contents(ghqRoot: nil, homeDirectory: F.homeDirectory))
        #expect(contents.contains("\nroots = [\"~\"]\n"))
        #expect(store.config == Config(roots: [F.homeDirectory]))
        #expect(store.lastError == nil)
        #expect(store.warnings.isEmpty)
    }

    @Test(
        "ghq が無効・未インストール・失敗のときは roots をホーム（~）にして生成する（実際の GhqRepositoryLister で確かめる）",
        arguments: GhqUnavailability.allCases
    )
    func generatesHomeRootsWhenGhqIsUnavailable(unavailability: GhqUnavailability) async throws {
        let store = ConfigStore(
            directory: directory,
            homeDirectory: F.homeDirectory,
            ghqRootProvider: unavailability.makeLister()
        )
        defer { store.stop() }

        await store.start()

        #expect(try ConfigFileWriter.read(fileURL).contains("\nroots = [\"~\"]\n"))
        #expect(store.config == Config(roots: [F.homeDirectory]))
        #expect(store.lastError == nil)
    }

    @Test("設定ディレクトリが無ければ中間ディレクトリも含めて作る")
    func createsIntermediateDirectories() async {
        let nestedDirectory = directory.appending(path: "nested/deeper", directoryHint: .isDirectory)
        let (store, _) = F.makeStore(directory: nestedDirectory)
        defer { store.stop() }

        await store.start()

        #expect(FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
    }

    @Test("既存のファイルは上書きせず、ghq root も問い合わせない")
    func doesNotOverwriteExistingFile() async throws {
        let existingContents = "# 手で書いた設定\ndepth = 5\n"
        try writeExistingFile(existingContents)
        let (store, ghq) = F.makeStore(directory: directory)
        defer { store.stop() }

        await store.start()

        #expect(try ConfigFileWriter.read(fileURL) == existingContents)
        #expect(store.config == Config(depth: 5))
        #expect(await ghq.callCount == 0)
    }

    @Test("既存のファイルが不正でも上書きしない（直前の有効な設定が無いので既定値で動く）")
    func doesNotOverwriteInvalidExistingFile() async throws {
        let invalidContents = "depth = \n"
        try writeExistingFile(invalidContents)
        let (store, ghq) = F.makeStore(directory: directory)
        defer { store.stop() }

        await store.start()

        #expect(try ConfigFileWriter.read(fileURL) == invalidContents)
        #expect(store.config == .default)
        guard case .parseFailed(let path, _) = store.lastError else {
            Issue.record("lastError が parseFailed ではない: \(String(describing: store.lastError))")
            return
        }
        #expect(path == filePath)
        #expect(await ghq.callCount == 0)
    }

    @Test("リンク先の無いシンボリックリンクは上書きもリンク先の作成もしない")
    func doesNotWriteThroughDanglingSymlink() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let missingTarget = temporaryDirectory.url.appending(path: "dotfiles/config.toml")
        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: missingTarget)
        let (store, _) = F.makeStore(directory: directory)
        defer { store.stop() }

        await store.start()

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: filePath) == missingTarget.path(percentEncoded: false))
        #expect(!FileManager.default.fileExists(atPath: missingTarget.path(percentEncoded: false)))
        #expect(store.config == .default)
        #expect(store.lastError == .fileNotFound(path: filePath))
    }

    @Test("生成に失敗したら既定の設定で動き、lastError に generationFailed を公開する")
    func exposesGenerationFailure() async throws {
        // 設定ディレクトリの位置に通常ファイルを置き、ディレクトリを作れなくする
        try Data().write(to: temporaryDirectory.url.appending(path: F.configDirectoryName, directoryHint: .notDirectory))
        let (store, _) = F.makeStore(directory: directory)
        defer { store.stop() }

        await store.start()

        #expect(store.config == .default)
        guard case .generationFailed(let path, _) = store.lastError else {
            Issue.record("lastError が generationFailed ではない: \(String(describing: store.lastError))")
            return
        }
        #expect(path == filePath)
    }

    @Test("start を 2 回呼んでも生成と ghq root の問い合わせは 1 回だけ")
    func startIsIdempotent() async {
        let (store, ghq) = F.makeStore(directory: directory)
        defer { store.stop() }

        await store.start()
        await store.start()

        #expect(await ghq.callCount == 1)
        #expect(store.config == Config(roots: [F.ghqRoot]))
    }

    @Test("stop 後に start しても何もしない（終了処理後の再開は想定しない）")
    func startAfterStopDoesNothing() async {
        let (store, ghq) = F.makeStore(directory: directory)

        store.stop()
        await store.start()

        #expect(await ghq.callCount == 0)
        #expect(!FileManager.default.fileExists(atPath: filePath))
        #expect(store.config == .default)
    }
}
