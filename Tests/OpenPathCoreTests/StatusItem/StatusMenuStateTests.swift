import Testing

import OpenPathCore

@Suite("StatusMenuState: メニューの構成（UX-001 §6）")
struct StatusMenuLayoutTests {
    private typealias F = StatusMenuFixtures

    @Test("操作の項目は UX-001 §6 の順に並ぶ")
    func commandsFollowUXOrder() {
        let state = StatusMenuState(F.input(permission: .notGranted))

        #expect(state.commandItems.map(\.command) == [
            .toggleEnabled,
            .rebuildCandidates,
            .openConfigFile,
            .clearHistory,
            .toggleLaunchAtLogin,
            .openAccessibilitySettings,
            .showOnboarding,
            .quit,
        ])
    }

    @Test("項目の表題は UX-001 §6 の文言にする")
    func titlesMatchUX() {
        let state = StatusMenuState(F.input(permission: .notGranted))

        #expect(state.commandItems.map(\.title) == [
            "有効",
            "候補を再構築",
            "設定ファイルを開く…",
            "履歴をクリア…",
            "ログイン時に起動",
            "アクセシビリティ設定を開く…",
            "はじめに…",
            "終了",
        ])
    }

    @Test("アクセシビリティ設定を開く…は権限が付与済みなら出さない")
    func hidesAccessibilitySettingsWhenGranted() {
        let state = StatusMenuState(F.input(permission: .granted))

        #expect(state.item(for: .openAccessibilitySettings) == nil)
        #expect(state.commandItems.count == StatusMenuCommand.allCases.filter(\.appearsAsMenuItem).count - 1)
    }

    @Test("アクセシビリティ設定を開く…は権限が未付与なら出す")
    func showsAccessibilitySettingsWhenNotGranted() throws {
        let state = StatusMenuState(F.input(permission: .notGranted))

        let item = try #require(state.item(for: .openAccessibilitySettings))
        #expect(item.isEnabled)
        #expect(item.checkState == nil)
    }

    @Test("はじめに…（初回起動の案内を開き直す）は権限の有無に関わらず出す", arguments: [AccessibilityPermissionStatus.granted, .notGranted])
    func showsOnboarding(permission: AccessibilityPermissionStatus) throws {
        let state = StatusMenuState(F.input(permission: permission))

        let item = try #require(state.item(for: .showOnboarding))
        #expect(item.isEnabled)
        #expect(item.checkState == nil)
        #expect(item.keyEquivalent.isEmpty)
    }

    @Test("終了は ⌘Q、設定ファイルを開く…は ⌘, で選べる")
    func keyEquivalents() {
        let state = StatusMenuState(F.input())

        #expect(state.item(for: .quit)?.keyEquivalent == "q")
        #expect(state.item(for: .openConfigFile)?.keyEquivalent == ",")
        #expect(state.item(for: .rebuildCandidates)?.keyEquivalent == "")
    }

    @Test("チェック項目は有効とログイン時に起動だけ")
    func onlyTogglesHaveCheckState() {
        let state = StatusMenuState(F.input(permission: .notGranted))

        let checkable = state.commandItems.filter { $0.checkState != nil }.map(\.command)
        #expect(checkable == [.toggleEnabled, .toggleLaunchAtLogin])
    }

    @Test("通知が無ければ区切り線から始まらず、区切り線は連続しない")
    func separatorsAreNotRedundant() {
        for input in F.representativeInputs {
            let entries = StatusMenuState(input).entries

            #expect(entries.first != .separator)
            #expect(entries.last != .separator)
            let hasAdjacentSeparators = zip(entries, entries.dropFirst()).contains { $0 == .separator && $1 == .separator }
            #expect(!hasAdjacentSeparators)
        }
    }

    @Test("終了は最後に置き、直前を区切り線で分ける")
    func quitIsLastAndSeparated() throws {
        let state = StatusMenuState(F.input())

        let quit = try #require(state.item(for: .quit))
        #expect(state.entries.suffix(2) == [.separator, .command(quit)])
    }
}

@Suite("StatusMenuState: 有効の切り替え")
struct StatusMenuEnabledToggleTests {
    private typealias F = StatusMenuFixtures

    @Test("有効ならチェックを付け、アイコンを通常表示にする")
    func enabled() throws {
        let state = StatusMenuState(F.input(isEnabled: true))

        let item = try #require(state.item(for: .toggleEnabled))
        #expect(item.checkState == .on)
        #expect(item.isEnabled)
        #expect(!state.icon.isDimmed)
    }

    @Test("無効ならチェックを外し、アイコンを薄く表示してツールチップに明示する")
    func disabled() throws {
        let state = StatusMenuState(F.input(isEnabled: false))

        let item = try #require(state.item(for: .toggleEnabled))
        #expect(item.checkState == .off)
        #expect(item.isEnabled)
        #expect(state.icon.isDimmed)
        #expect(state.toolTip == "openpath（無効）")
    }

    @Test("無効でも権限や設定の問題はバッジで知らせる")
    func disabledStillShowsBadge() {
        let state = StatusMenuState(F.input(isEnabled: false, permission: .notGranted))

        #expect(state.icon.isDimmed)
        #expect(state.icon.hasBadge)
    }
}

@Suite("StatusMenuState: バッジと通知（UX-001 §5）")
struct StatusMenuNoticeTests {
    private typealias F = StatusMenuFixtures

    @Test("権限があり設定エラーも無ければバッジも通知も出さない")
    func noIssues() {
        let state = StatusMenuState(F.input())

        #expect(!state.icon.hasBadge)
        #expect(state.notices.isEmpty)
        #expect(state.toolTip == "openpath")
        #expect(state.icon.accessibilityLabel == "openpath")
    }

    @Test("権限が無ければバッジを付け、メニュー先頭で権限設定へ案内する")
    func permissionMissing() throws {
        let state = StatusMenuState(F.input(permission: .notGranted))

        #expect(state.icon.hasBadge)
        let notice = try #require(state.notices.first)
        #expect(state.notices.count == 1)
        #expect(notice.kind == .accessibilityPermissionMissing)
        #expect(notice.title == "アクセシビリティ権限がありません")
        #expect(notice.command == .openAccessibilitySettings)
        #expect(state.entries.prefix(2) == [.notice(notice), .separator])
    }

    @Test("設定ファイルのエラーはバッジを付け、理由（lastError.description）を先頭に出して設定ファイルへ案内する")
    func configError() throws {
        let error = F.configError
        let state = StatusMenuState(F.input(configError: error))

        #expect(state.icon.hasBadge)
        let notice = try #require(state.notices.first)
        #expect(state.notices.count == 1)
        #expect(notice.kind == .configError)
        #expect(notice.title == "設定ファイルにエラーがあります")
        #expect(notice.detail == error.description)
        #expect(notice.command == .openConfigFile)
    }

    @Test("権限と設定の両方に問題があれば、権限を先に出す")
    func bothIssuesOrderedByPermissionFirst() {
        let state = StatusMenuState(F.input(permission: .notGranted, configError: F.configError))

        #expect(state.notices.map(\.kind) == [.accessibilityPermissionMissing, .configError])
        #expect(state.entries.prefix(3) == [.notice(state.notices[0]), .notice(state.notices[1]), .separator])
    }

    @Test("クリップボードを戻せなかったらバッジを付け、通知を選ぶと消せるようにする")
    func clipboardRestoreFailure() throws {
        let state = StatusMenuState(F.input(hasClipboardRestoreFailure: true))

        #expect(state.icon.hasBadge)
        let notice = try #require(state.notices.first)
        #expect(state.notices.count == 1)
        #expect(notice.kind == .clipboardRestoreFailed)
        #expect(notice.title == "クリップボードを元に戻せませんでした")
        #expect(notice.command == .dismissClipboardNotice)
        #expect(state.item(for: .dismissClipboardNotice) == nil)
    }

    @Test("通知は権限 → 設定 → クリップボードの順に並べる")
    func noticeOrder() {
        let state = StatusMenuState(F.input(permission: .notGranted, configError: F.configError, hasClipboardRestoreFailure: true))

        #expect(state.notices.map(\.kind) == [.accessibilityPermissionMissing, .configError, .clipboardRestoreFailed])
    }

    @Test("通知を消す操作はメニューの項目には並ばない")
    func dismissIsNoticeOnly() {
        #expect(StatusMenuCommand.dismissClipboardNotice.appearsAsMenuItem == false)
        #expect(StatusMenuCommand.allCases.filter { !$0.appearsAsMenuItem } == [.dismissClipboardNotice])
    }

    @Test("ツールチップに理由を 1 行ずつ並べる")
    func toolTipListsReasons() {
        let error = F.configError
        let state = StatusMenuState(F.input(permission: .notGranted, configError: error))

        let lines = state.toolTip.split(separator: "\n").map(String.init)
        #expect(lines.count == 3)
        #expect(lines[0] == "openpath")
        #expect(lines[1].hasPrefix("アクセシビリティ権限がありません"))
        #expect(lines[2].hasPrefix("設定ファイルにエラーがあります"))
        #expect(lines[2].hasSuffix(error.description))
    }

    @Test("バッジがあるときはアイコンの読み上げにも要対応であることを含める")
    func accessibilityLabelWithBadge() {
        let state = StatusMenuState(F.input(permission: .notGranted))

        #expect(state.icon.accessibilityLabel == "openpath（要対応）")
    }

    @Test("無効かつ要対応なら両方を読み上げに含める")
    func accessibilityLabelDisabledWithBadge() {
        let state = StatusMenuState(F.input(isEnabled: false, configError: F.configError))

        #expect(state.icon.accessibilityLabel == "openpath（無効・要対応）")
    }
}
