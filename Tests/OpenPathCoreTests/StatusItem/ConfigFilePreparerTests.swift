import Foundation
import Testing

import OpenPathCore

/// 「設定ファイルを開く…」の前に設定ファイルを用意する処理。実ユーザーの ~/.config に触れないよう一時ディレクトリで確かめる。
@Suite("ConfigFilePreparer: 設定ファイルを開く前の用意")
struct ConfigFilePreparerTests {
    private static let defaultContents = "# 既定の設定\ndepth = 3\n"
    private static let existingContents = "depth = 9\n"

    private let temporaryDirectory: StatusItemTemporaryDirectory

    init() throws {
        temporaryDirectory = try StatusItemTemporaryDirectory()
    }

    private var configDirectory: URL {
        temporaryDirectory.url.appending(path: "openpath", directoryHint: .isDirectory)
    }

    private var fileURL: URL {
        configDirectory.appending(path: "config.toml", directoryHint: .notDirectory)
    }

    @Test("ファイルがあれば何も書き込まず existing を返す")
    func keepsExistingFile() throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        try Data(Self.existingContents.utf8).write(to: fileURL)
        var didRequestDefaultContents = false

        let preparation = try ConfigFilePreparer.prepare(fileURL: fileURL) {
            didRequestDefaultContents = true
            return Self.defaultContents
        }

        #expect(preparation == .existing)
        #expect(!didRequestDefaultContents)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == Self.existingContents)
    }

    @Test("ファイルが無ければディレクトリごと作り、既定の内容で生成して created を返す")
    func createsMissingFile() throws {
        let preparation = try ConfigFilePreparer.prepare(fileURL: fileURL) { Self.defaultContents }

        #expect(preparation == .created)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == Self.defaultContents)
    }

    @Test("ディレクトリはあってファイルだけ無い場合も生成する")
    func createsFileInExistingDirectory() throws {
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)

        let preparation = try ConfigFilePreparer.prepare(fileURL: fileURL) { Self.defaultContents }

        #expect(preparation == .created)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == Self.defaultContents)
    }

    @Test("ディレクトリを作れなければ、パスと理由を含むエラーを投げる")
    func failsWhenDirectoryCannotBeCreated() throws {
        // ディレクトリを置くべき場所に通常のファイルがあるため、ディレクトリを作れない
        try Data().write(to: configDirectory)

        do throws(ConfigFilePreparationError) {
            let preparation = try ConfigFilePreparer.prepare(fileURL: fileURL) { Self.defaultContents }
            Issue.record("失敗するはずが \(preparation) を返した")
        } catch {
            switch error {
            case .creationFailed(let path, let reason):
                #expect(path == fileURL.path(percentEncoded: false))
                #expect(!reason.isEmpty)
            }
        }
    }

    @Test("生成の失敗の説明にはパスを含め、利用者が場所を確かめられるようにする")
    func creationFailedDescription() {
        let error = ConfigFilePreparationError.creationFailed(path: "/Users/tester/.config/openpath/config.toml", reason: "権限がありません")

        #expect(error.description == "設定ファイル /Users/tester/.config/openpath/config.toml を作成できません（権限がありません）")
    }
}

/// テストごとの一時ディレクトリ。
final class StatusItemTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "openpath-statusitem-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
