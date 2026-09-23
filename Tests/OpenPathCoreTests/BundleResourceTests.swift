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

    @Test("AX 観測のため非サンドボックス、かつネットワーク権限を持たない")
    func entitlementsAreMinimal() throws {
        let entitlements = try Self.decodePropertyList(Entitlements.self, at: Self.entitlementsPath)

        #expect(entitlements.isAppSandboxEnabled == false)
        #expect(entitlements.isNetworkClientAllowed == nil)
        #expect(entitlements.isNetworkServerAllowed == nil)
    }
}
