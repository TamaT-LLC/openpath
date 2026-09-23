import Foundation
import Testing

import OpenPathCore

@Suite("ログイン時に起動: メニュー項目の表示")
struct LoginItemMenuItemTests {
    private typealias F = StatusMenuFixtures

    @Test(
        "登録状態からチェックと選択可否を決める",
        arguments: [
            (LoginItemStatus.enabled, StatusMenuCheckState.on, true),
            (.notRegistered, .off, true),
            (.notFound, .off, true),
            (.requiresApproval, .mixed, true),
            (.unavailable, .off, false),
        ]
    )
    func checkStateAndAvailability(status: LoginItemStatus, expectedCheck: StatusMenuCheckState, expectedEnabled: Bool) throws {
        let state = StatusMenuState(F.input(loginItemStatus: status))

        let item = try #require(state.item(for: .toggleLaunchAtLogin))
        #expect(item.checkState == expectedCheck)
        #expect(item.isEnabled == expectedEnabled)
    }

    @Test("承認待ちなら、システム設定で許可すると有効になることをツールチップで伝える")
    func requiresApprovalToolTip() throws {
        let state = StatusMenuState(F.input(loginItemStatus: .requiresApproval))

        let item = try #require(state.item(for: .toggleLaunchAtLogin))
        #expect(item.toolTip == "システム設定の「一般 > ログイン項目」で許可すると有効になります")
    }

    @Test(".app として起動していなければ選べない理由をツールチップで伝える")
    func unavailableToolTip() throws {
        let state = StatusMenuState(F.input(loginItemStatus: .unavailable))

        let item = try #require(state.item(for: .toggleLaunchAtLogin))
        #expect(item.toolTip == "openpath.app として起動したときだけ設定できます")
    }

    @Test("登録済み・未登録ならツールチップを出さない", arguments: [LoginItemStatus.enabled, .notRegistered, .notFound])
    func noToolTipForRegularStatus(status: LoginItemStatus) throws {
        let state = StatusMenuState(F.input(loginItemStatus: status))

        #expect(try #require(state.item(for: .toggleLaunchAtLogin)).toolTip == nil)
    }

    @Test("ログイン時に起動の状態はバッジに影響しない", arguments: [LoginItemStatus.requiresApproval, .unavailable, .notFound])
    func loginItemDoesNotAffectBadge(status: LoginItemStatus) {
        let state = StatusMenuState(F.input(loginItemStatus: status))

        #expect(!state.icon.hasBadge)
        #expect(state.notices.isEmpty)
    }
}

@Suite("ログイン時に起動: 登録状態")
struct LoginItemStatusTests {
    @Test(
        "クリックしたときの操作",
        arguments: [
            (LoginItemStatus.enabled, LoginItemCommand?.some(.unregister)),
            (.requiresApproval, .unregister),
            (.notRegistered, .register),
            (.notFound, .register),
            (.unavailable, nil),
        ]
    )
    func toggleCommand(status: LoginItemStatus, expected: LoginItemCommand?) {
        #expect(status.toggleCommand == expected)
    }

    @Test(
        ".app バンドルから起動しているときだけ SMAppService.mainApp を使える",
        arguments: [
            ("/Applications/openpath.app", true),
            ("/Applications/openpath.app/", true),
            ("/Users/tester/Build/Products/Release/openpath.APP", true),
            ("/Users/tester/repos/openpath/.build/arm64-apple-macosx/debug", false),
            ("/usr/local/bin", false),
        ]
    )
    func appBundleDetection(path: String, expected: Bool) {
        let url = URL(filePath: path, directoryHint: .isDirectory)

        #expect(LoginItemAvailability.isAppBundle(url) == expected)
    }
}
