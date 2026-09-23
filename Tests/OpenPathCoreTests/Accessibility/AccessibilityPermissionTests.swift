import Foundation
import Testing

import OpenPathCore

@Suite("アクセシビリティ権限")
struct AccessibilityPermissionTests {
    @Test("ポーリング間隔は 5 秒（付与後 5 秒以内に検知するため）")
    func pollingIntervalIsFiveSeconds() {
        #expect(AccessibilityPermissionPolicy.pollingInterval == .seconds(5))
    }

    @Test("AX の信頼状態から権限状態へ変換する", arguments: [
        (true, AccessibilityPermissionStatus.granted),
        (false, AccessibilityPermissionStatus.notGranted),
    ])
    func statusFromTrust(isTrusted: Bool, expected: AccessibilityPermissionStatus) {
        let status = AccessibilityPermissionStatus(isTrusted: isTrusted)

        #expect(status == expected)
        #expect(status.isGranted == isTrusted)
    }

    @Test("システム設定の「プライバシーとセキュリティ > アクセシビリティ」を開く URL")
    func systemSettingsURL() throws {
        let url = try #require(AccessibilityPermissionPolicy.systemSettingsURL)

        #expect(url.scheme == "x-apple.systempreferences")
        #expect(url.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }
}

@Suite("要求する権限の範囲")
struct PermissionScopeTests {
    private static let sourcesPath = "Sources"
    private static let swiftFileExtension = "swift"

    /// NFR-02: アクセシビリティ以外（Full Disk Access・画面収録・入力監視など）の権限を要求しない。
    /// それらの設定画面の URL アンカーと、権限要求 API の呼び出しをソースに含めないことで担保する。
    /// Regex は Sendable でないため、static let ではなく都度生成する。
    private static var forbiddenPatterns: [(name: String, regex: Regex<Substring>)] {
        [
            ("アクセシビリティ以外のプライバシー設定画面", /Privacy_(?!Accessibility\b)\w+/),
            ("Full Disk Access の TCC サービス", /SystemPolicyAllFiles|kTCCService/),
            ("画面収録の権限要求", /CGRequestScreenCaptureAccess/),
            ("入力監視の権限要求", /CGRequestListenEventAccess|IOHIDRequestAccess/),
        ]
    }

    @Test("ソースはアクセシビリティ以外の権限を要求しない")
    func sourcesRequestOnlyAccessibility() throws {
        let sourceDirectory = PackageLayout.url(Self.sourcesPath)
        let sourceFiles = try FileManager.default.subpathsOfDirectory(atPath: sourceDirectory.path)
            .filter { $0.hasSuffix(".\(Self.swiftFileExtension)") }
            .map { sourceDirectory.appending(path: $0) }

        #expect(!sourceFiles.isEmpty)
        for sourceFile in sourceFiles {
            let source = try String(contentsOf: sourceFile, encoding: .utf8)
            for pattern in Self.forbiddenPatterns {
                #expect(source.firstMatch(of: pattern.regex) == nil, "\(sourceFile.lastPathComponent) が\(pattern.name)を参照している")
            }
        }
    }
}
