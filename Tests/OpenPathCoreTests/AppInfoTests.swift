import Testing

import OpenPathCore

@Suite("AppInfo")
struct AppInfoTests {
    @Test("アプリ名は openpath")
    func name() {
        #expect(AppInfo.name == "openpath")
    }

    @Test("bundle id は jp.tamat.openpath")
    func bundleIdentifier() {
        #expect(AppInfo.bundleIdentifier == "jp.tamat.openpath")
    }

    @Test("バージョンは major.minor.patch 形式")
    func versionIsSemanticVersion() {
        #expect(AppInfo.version.wholeMatch(of: /[0-9]+\.[0-9]+\.[0-9]+/) != nil)
    }
}
