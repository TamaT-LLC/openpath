import Foundation
import Testing

@Suite("モジュール境界")
struct ModuleBoundaryTests {
    /// OpenPathCore をユニットテスト可能な純 Swift に保つため、UI フレームワークへの依存を禁止する。
    /// SwiftUI は AppKit を再エクスポートするため同様に禁止する。
    /// Carbon（ホットキー登録）は Mac 層の責務で、Core は仮想キーコードを純データで持つ方針のため禁止する。
    /// 検査対象は Sources/OpenPathCore のみで、テストターゲットが Carbon の定数と突き合わせるための import は対象外。
    private static let forbiddenModules: Set<String> = ["AppKit", "Cocoa", "SwiftUI", "Carbon"]
    private static let coreSourcesPath = "Sources/OpenPathCore"
    private static let swiftFileExtension = "swift"

    @Test("OpenPathCore は AppKit / Cocoa / SwiftUI / Carbon を import しない")
    func coreDoesNotImportUIFrameworks() throws {
        let sourceDirectory = PackageLayout.url(Self.coreSourcesPath)
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceDirectory.path)
            .filter { $0.hasSuffix(".\(Self.swiftFileExtension)") }
            .map { sourceDirectory.appending(path: $0) }

        #expect(!sourceFiles.isEmpty)
        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            let violations = Self.violations(in: source)
            #expect(violations.isEmpty, "\(sourceFile.lastPathComponent) が \(violations.sorted()) を import している")
        }
    }

    @Test(
        "禁止モジュールはサブモジュールや個別宣言の import でも違反として検出する",
        arguments: [
            "import Carbon",
            "import Carbon.HIToolbox",
            "@preconcurrency import Carbon.HIToolbox",
            "import struct Carbon.HIToolbox.EventHotKeyID",
            "internal import Carbon.HIToolbox",
            "import AppKit.NSEvent",
        ]
    )
    func detectsForbiddenImports(source: String) {
        #expect(!Self.violations(in: source).isEmpty)
    }

    @Test(
        "許可されたモジュールやコメント内の import は違反にしない",
        arguments: ["import Foundation", "import CoreGraphics", "// import Carbon.HIToolbox", "let note = \"import AppKit\""]
    )
    func allowsPermittedImports(source: String) {
        #expect(Self.violations(in: source).isEmpty)
    }

    private static func violations(in source: String) -> Set<String> {
        importedModules(in: source).intersection(forbiddenModules)
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
