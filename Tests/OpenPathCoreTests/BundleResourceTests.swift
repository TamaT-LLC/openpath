import Foundation
import Testing

import OpenPathCore

@Suite("バンドル設定ファイル")
struct BundleResourceTests {
    private struct InfoPlist: Decodable {
        let bundleIdentifier: String
        let bundleName: String
        let bundleExecutable: String
        let shortVersion: String
        let isUIElement: Bool

        enum CodingKeys: String, CodingKey {
            case bundleIdentifier = "CFBundleIdentifier"
            case bundleName = "CFBundleName"
            case bundleExecutable = "CFBundleExecutable"
            case shortVersion = "CFBundleShortVersionString"
            case isUIElement = "LSUIElement"
        }
    }

    /// macOS のプライバシー保護（TCC）の対象フォルダを読むときに、確認ダイアログへ出す用途の説明
    private struct ProtectedFolderUsageDescriptions: Decodable {
        let desktop: String?
        let documents: String?
        let downloads: String?

        enum CodingKeys: String, CodingKey, CaseIterable {
            case desktop = "NSDesktopFolderUsageDescription"
            case documents = "NSDocumentsFolderUsageDescription"
            case downloads = "NSDownloadsFolderUsageDescription"
        }

        var all: [String?] { [desktop, documents, downloads] }
    }

    /// 値の型を問わず、トップレベルのキー名だけを読む
    private struct TopLevelKeys: Decodable {
        let names: Set<String>

        private struct AnyKey: CodingKey {
            let stringValue: String
            let intValue: Int? = nil

            init(stringValue: String) {
                self.stringValue = stringValue
            }

            init?(intValue: Int) {
                nil
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyKey.self)
            names = Set(container.allKeys.map(\.stringValue))
        }
    }

    private static let usageDescriptionKeySuffix = "UsageDescription"

    private struct Entitlements: Decodable {
        let isAppSandboxEnabled: Bool
        let isNetworkClientAllowed: Bool?
        let isNetworkServerAllowed: Bool?

        enum CodingKeys: String, CodingKey {
            case isAppSandboxEnabled = "com.apple.security.app-sandbox"
            case isNetworkClientAllowed = "com.apple.security.network.client"
            case isNetworkServerAllowed = "com.apple.security.network.server"
        }
    }

    private static let infoPlistPath = "Resources/Info.plist"
    private static let entitlementsPath = "Resources/openpath.entitlements"

    private static func decodePropertyList<T: Decodable>(_ type: T.Type, at relativePath: String) throws -> T {
        let data = try Data(contentsOf: PackageLayout.url(relativePath))
        return try PropertyListDecoder().decode(type, from: data)
    }

    @Test("Info.plist の識別子・名前・バージョンが AppInfo と一致する")
    func infoPlistMatchesAppInfo() throws {
        let infoPlist = try Self.decodePropertyList(InfoPlist.self, at: Self.infoPlistPath)

        #expect(infoPlist.bundleIdentifier == AppInfo.bundleIdentifier)
        #expect(infoPlist.bundleName == AppInfo.name)
        #expect(infoPlist.bundleExecutable == AppInfo.name)
        #expect(infoPlist.shortVersion == AppInfo.version)
    }

    @Test("Dock に出さないため LSUIElement が有効")
    func infoPlistIsUIElement() throws {
        let infoPlist = try Self.decodePropertyList(InfoPlist.self, at: Self.infoPlistPath)

        #expect(infoPlist.isUIElement)
    }

    @Test("roots にホームを指定したときの確認ダイアログに理由を出すため、デスクトップ・書類・ダウンロードの用途の説明がある")
    func infoPlistDescribesProtectedFolderUsage() throws {
        let descriptions = try Self.decodePropertyList(ProtectedFolderUsageDescriptions.self, at: Self.infoPlistPath)

        for description in descriptions.all {
            let text = try #require(description)
            #expect(!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @Test("用途の説明は保護フォルダの 3 つだけで、ほかの権限の確認を増やさない（NFR-02）")
    func infoPlistHasNoOtherUsageDescriptions() throws {
        let keys = try Self.decodePropertyList(TopLevelKeys.self, at: Self.infoPlistPath)
        let usageDescriptionKeys = keys.names.filter { $0.hasSuffix(Self.usageDescriptionKeySuffix) }
        let protectedFolderKeys = Set(ProtectedFolderUsageDescriptions.CodingKeys.allCases.map(\.rawValue))

        #expect(usageDescriptionKeys == protectedFolderKeys)
    }

    @Test("AX 観測のため非サンドボックス、かつネットワーク権限を持たない")
    func entitlementsAreMinimal() throws {
        let entitlements = try Self.decodePropertyList(Entitlements.self, at: Self.entitlementsPath)

        #expect(entitlements.isAppSandboxEnabled == false)
        #expect(entitlements.isNetworkClientAllowed == nil)
        #expect(entitlements.isNetworkServerAllowed == nil)
    }
}
