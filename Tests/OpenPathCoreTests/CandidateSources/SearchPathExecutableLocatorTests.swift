import Foundation
import Testing

import OpenPathCore

@Suite("SearchPathExecutableLocator")
struct SearchPathExecutableLocatorTests {
    private static let executableName = "openpath-test-tool"
    private static let executablePermissions = 0o755
    private static let nonExecutablePermissions = 0o644

    /// テストごとに作る一時ディレクトリ。`first` と `second` の 2 つの検索ディレクトリを持つ。
    private struct Sandbox {
        let root: URL
        let first: URL
        let second: URL

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appending(path: "openpath-locator-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
            first = root.appending(path: "first", directoryHint: .isDirectory)
            second = root.appending(path: "second", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        }

        var searchPath: String {
            "\(first.path):\(second.path)"
        }

        func placeFile(in directory: URL, permissions: Int) throws -> String {
            let path = directory.appending(path: SearchPathExecutableLocatorTests.executableName).path
            try Data().write(to: URL(fileURLWithPath: path))
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: path)
            return path
        }

        func placeDirectory(in directory: URL) throws {
            let path = directory.appending(path: SearchPathExecutableLocatorTests.executableName, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private let locator = SearchPathExecutableLocator()

    @Test("検索パスの先頭から探し、最初に見つかった実行可能ファイルのパスを返す")
    func returnsFirstExecutable() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        let expected = try sandbox.placeFile(in: sandbox.first, permissions: Self.executablePermissions)
        _ = try sandbox.placeFile(in: sandbox.second, permissions: Self.executablePermissions)

        #expect(locator.locateExecutable(named: Self.executableName, inSearchPath: sandbox.searchPath) == expected)
    }

    @Test("実行権限の無いファイルは飛ばして次のディレクトリを探す")
    func skipsNonExecutableFile() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        _ = try sandbox.placeFile(in: sandbox.first, permissions: Self.nonExecutablePermissions)
        let expected = try sandbox.placeFile(in: sandbox.second, permissions: Self.executablePermissions)

        #expect(locator.locateExecutable(named: Self.executableName, inSearchPath: sandbox.searchPath) == expected)
    }

    @Test("同名のディレクトリは実行ファイルとみなさない")
    func skipsDirectory() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        try sandbox.placeDirectory(in: sandbox.first)
        let expected = try sandbox.placeFile(in: sandbox.second, permissions: Self.executablePermissions)

        #expect(locator.locateExecutable(named: Self.executableName, inSearchPath: sandbox.searchPath) == expected)
    }

    @Test("どのディレクトリにも無ければ nil を返す")
    func returnsNilWhenMissing() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }

        #expect(locator.locateExecutable(named: Self.executableName, inSearchPath: sandbox.searchPath) == nil)
    }

    @Test("相対パスのエントリはカレントディレクトリ次第で解決先が変わるため探さない")
    func ignoresRelativeEntries() throws {
        let sandbox = try Sandbox()
        defer { sandbox.remove() }
        _ = try sandbox.placeFile(in: sandbox.first, permissions: Self.executablePermissions)
        // カレントディレクトリから sandbox.first を指す相対パスを作り、それでも見つけないことを確かめる
        let currentDepth = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).pathComponents.count - 1
        let relativeToFirst = String(repeating: "../", count: currentDepth) + sandbox.first.path.dropFirst()
        #expect(FileManager.default.isExecutableFile(atPath: "\(relativeToFirst)/\(Self.executableName)"))

        #expect(locator.locateExecutable(named: Self.executableName, inSearchPath: "\(relativeToFirst)::") == nil)
    }
}
