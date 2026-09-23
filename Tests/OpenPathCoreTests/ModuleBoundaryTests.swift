import Foundation
import Testing

@Suite("モジュール境界")
struct ModuleBoundaryTests {
    /// OpenPathCore をユニットテスト可能な純 Swift に保つため、UI フレームワークへの依存を禁止する。
    /// SwiftUI は AppKit を再エクスポートするため同様に禁止する。
    private static let forbiddenModules: Set<String> = ["AppKit", "Cocoa", "SwiftUI"]
    private static let coreSourcesPath = "Sources/OpenPathCore"
    private static let swiftFileExtension = "swift"

    @Test("OpenPathCore は AppKit / Cocoa / SwiftUI を import しない")
    func coreDoesNotImportUIFrameworks() throws {
        let sourceDirectory = PackageLayout.url(Self.coreSourcesPath)
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceDirectory.path)
            .filter { $0.hasSuffix(".\(Self.swiftFileExtension)") }
            .map { sourceDirectory.appending(path: $0) }

        #expect(!sourceFiles.isEmpty)
        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            let violations = Self.importedModules(in: source).intersection(Self.forbiddenModules)
            #expect(violations.isEmpty, "\(sourceFile.lastPathComponent) が \(violations.sorted()) を import している")
        }
    }

    /// 属性（`@preconcurrency` 等）、アクセス修飾子、個別宣言の import（`import class M.T`）を考慮して
    /// 行頭の import 文からトップレベルのモジュール名を取り出す。
    private static func importedModules(in source: String) -> Set<String> {
        let importPattern = /^\s*(?:@\w+\s+)*(?:(?:public|package|internal|fileprivate|private)\s+)?import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(\w+)/
        let modules = source.split(whereSeparator: \.isNewline).compactMap { line in
            line.firstMatch(of: importPattern).map { String($0.output.1) }
        }
        return Set(modules)
    }
}
