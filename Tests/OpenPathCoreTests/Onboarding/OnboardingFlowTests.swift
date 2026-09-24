import Testing

import OpenPathCore

@Suite("OnboardingFlow: 初回起動の案内の状態遷移（UX-001 §7）")
struct OnboardingFlowTests {
    /// 指定の権限で、初回起動の案内を始めた状態を作る
    private static func launchedFlow(permission: AccessibilityPermissionStatus) -> OnboardingFlow {
        var flow = OnboardingFlow(permission: permission)
        _ = flow.handle(.launched(hasFinishedBefore: false))
        return flow
    }

    /// 権限の説明からシステム設定を開き、権限待ちにした状態を作る
    private static func awaitingFlow() -> OnboardingFlow {
        var flow = launchedFlow(permission: .notGranted)
        _ = flow.handle(.command(.openSystemSettings))
        return flow
    }

    // MARK: - 起動

    @Test("生成直後は未表示")
    func initialState() {
        let flow = OnboardingFlow(permission: .notGranted)

        #expect(flow.step == .notShown)
        #expect(flow.isPresented == false)
        #expect(flow.presentedPage == nil)
    }

    @Test("初回起動で権限が無ければ、権限の説明を出す")
    func firstLaunchWithoutPermission() {
        var flow = OnboardingFlow(permission: .notGranted)

        let effects = flow.handle(.launched(hasFinishedBefore: false))

        #expect(effects == [.present(.permissionExplanation)])
        #expect(flow.step == .explainingPermission)
        #expect(flow.presentedPage == .permissionExplanation)
    }

    @Test("初回起動で権限が既にあれば説明を飛ばし、設定ファイルを用意して完了を出す")
    func firstLaunchWithPermission() {
        var flow = OnboardingFlow(permission: .granted)

        let effects = flow.handle(.launched(hasFinishedBefore: false))

        #expect(effects == [.prepareConfigFile, .present(.ready)])
        #expect(flow.step == .completed)
        #expect(flow.presentedPage == .ready)
    }

    @Test("以前に案内を終えていれば、起動しても何も出さない", arguments: [AccessibilityPermissionStatus.granted, .notGranted])
    func laterLaunchShowsNothing(permission: AccessibilityPermissionStatus) {
        var flow = OnboardingFlow(permission: permission)

        let effects = flow.handle(.launched(hasFinishedBefore: true))

        #expect(effects.isEmpty)
        #expect(flow.step == .notShown)
        #expect(flow.isPresented == false)
    }

    @Test("起動の知らせは 1 度だけ扱う")
    func launchIsHandledOnce() {
        var flow = Self.launchedFlow(permission: .notGranted)
        _ = flow.handle(.command(.close))

        let effects = flow.handle(.launched(hasFinishedBefore: false))

        #expect(effects.isEmpty)
        #expect(flow.step == .skipped)
    }

    // MARK: - 権限の説明 → 権限待ち → 完了

    @Test("説明で「システム設定を開く」を選ぶと、権限待ちの案内に替えてからシステム設定を開く")
    func openSystemSettingsFromExplanation() {
        var flow = Self.launchedFlow(permission: .notGranted)

        let effects = flow.handle(.command(.openSystemSettings))

        #expect(effects == [.present(.awaitingPermission), .openAccessibilitySettings])
        #expect(flow.step == .awaitingPermission)
    }

    @Test("権限待ちでもう一度「システム設定を開く」を選ぶと、システム設定を開くだけ")
    func reopenSystemSettingsWhileAwaiting() {
        var flow = Self.awaitingFlow()

        let effects = flow.handle(.command(.openSystemSettings))

        #expect(effects == [.openAccessibilitySettings])
        #expect(flow.step == .awaitingPermission)
    }

    @Test("権限待ちで権限が付与されたら、設定ファイルを用意して完了を出す")
    func permissionGrantedWhileAwaiting() {
        var flow = Self.awaitingFlow()

        let effects = flow.handle(.permissionChanged(.granted))

        #expect(effects == [.prepareConfigFile, .present(.ready)])
        #expect(flow.step == .completed)
        #expect(flow.permission == .granted)
    }

    @Test("説明の表示中にメニュー等から権限が付与されても、完了へ進む")
    func permissionGrantedWhileExplaining() {
        var flow = Self.launchedFlow(permission: .notGranted)

        let effects = flow.handle(.permissionChanged(.granted))

        #expect(effects == [.prepareConfigFile, .present(.ready)])
        #expect(flow.step == .completed)
    }

    @Test("完了の表示中に権限が取り消されたら、権限の説明に戻る")
    func permissionRevokedWhileCompleted() {
        var flow = Self.launchedFlow(permission: .granted)

        let effects = flow.handle(.permissionChanged(.notGranted))

        #expect(effects == [.present(.permissionExplanation)])
        #expect(flow.step == .explainingPermission)
    }

    @Test("同じ権限の知らせでは何もしない")
    func samePermissionIsIgnored() {
        var flow = Self.awaitingFlow()

        let effects = flow.handle(.permissionChanged(.notGranted))

        #expect(effects.isEmpty)
        #expect(flow.step == .awaitingPermission)
    }

    @Test("案内を出していない間の権限の変化は覚えるだけで、何も出さない")
    func permissionChangeWhileHidden() {
        var flow = OnboardingFlow(permission: .notGranted)

        let effects = flow.handle(.permissionChanged(.granted))

        #expect(effects.isEmpty)
        #expect(flow.step == .notShown)
        #expect(flow.permission == .granted)
    }

    // MARK: - 閉じる・試してみる

    @Test("説明・権限待ちで閉じると（あとで・クローズボタン）スキップし、次の起動から出さないよう記録する")
    func closeBeforePermissionSkips() {
        var explaining = Self.launchedFlow(permission: .notGranted)
        var awaiting = Self.awaitingFlow()

        let explainingEffects = explaining.handle(.command(.close))
        let awaitingEffects = awaiting.handle(.command(.close))

        #expect(explainingEffects == [.dismiss, .recordFinished])
        #expect(awaitingEffects == [.dismiss, .recordFinished])
        #expect(explaining.step == .skipped)
        #expect(awaiting.step == .skipped)
        #expect(explaining.isPresented == false)
    }

    @Test("完了で「試してみる」を選ぶと、案内を閉じて記録してから「開く」ダイアログを出す")
    func tryOpenPanel() {
        var flow = Self.launchedFlow(permission: .granted)

        let effects = flow.handle(.command(.tryOpenPanel))

        #expect(effects == [.dismiss, .recordFinished, .launchTrialPanel])
        #expect(flow.step == .completed)
        #expect(flow.isPresented == false)
    }

    @Test("完了で閉じると、試さずに案内を閉じて記録する")
    func closeAfterCompletion() {
        var flow = Self.launchedFlow(permission: .granted)

        let effects = flow.handle(.command(.close))

        #expect(effects == [.dismiss, .recordFinished])
        #expect(flow.step == .completed)
        #expect(flow.isPresented == false)
    }

    @Test("権限が無い間は「試してみる」を受け付けない（パネルを検知できないため）")
    func tryOpenPanelRequiresCompletion() {
        var flow = Self.awaitingFlow()

        let effects = flow.handle(.command(.tryOpenPanel))

        #expect(effects.isEmpty)
        #expect(flow.step == .awaitingPermission)
    }

    @Test("完了では「システム設定を開く」を受け付けない")
    func openSystemSettingsIgnoredWhenCompleted() {
        var flow = Self.launchedFlow(permission: .granted)

        let effects = flow.handle(.command(.openSystemSettings))

        #expect(effects.isEmpty)
        #expect(flow.step == .completed)
    }

    @Test("案内を出していない間のボタンの操作は無視する", arguments: OnboardingCommand.allCases)
    func commandsWhileHiddenAreIgnored(command: OnboardingCommand) {
        var flow = Self.launchedFlow(permission: .granted)
        _ = flow.handle(.command(.close))

        let effects = flow.handle(.command(command))

        #expect(effects.isEmpty)
        #expect(flow.isPresented == false)
    }

    // MARK: - メニューの「はじめに…」

    @Test("スキップした後に開き直すと、権限が無ければ権限の説明から出す")
    func reopenAfterSkipWithoutPermission() {
        var flow = Self.launchedFlow(permission: .notGranted)
        _ = flow.handle(.command(.close))

        let effects = flow.handle(.reopenRequested)

        #expect(effects == [.present(.permissionExplanation)])
        #expect(flow.step == .explainingPermission)
    }

    @Test("閉じている間に権限が付与されていたら、開き直すと完了から出す")
    func reopenAfterPermissionGrantedWhileHidden() {
        var flow = Self.launchedFlow(permission: .notGranted)
        _ = flow.handle(.command(.close))
        _ = flow.handle(.permissionChanged(.granted))

        let effects = flow.handle(.reopenRequested)

        #expect(effects == [.prepareConfigFile, .present(.ready)])
        #expect(flow.step == .completed)
    }

    @Test("以前に案内を終えていても、メニューから開き直せる")
    func reopenAfterFinishedBefore() {
        var flow = OnboardingFlow(permission: .granted)
        _ = flow.handle(.launched(hasFinishedBefore: true))

        let effects = flow.handle(.reopenRequested)

        #expect(effects == [.prepareConfigFile, .present(.ready)])
    }

    @Test("表示中に開き直すと、同じ段階のまま前面に出し直す")
    func reopenWhilePresented() {
        var flow = Self.awaitingFlow()

        let effects = flow.handle(.reopenRequested)

        #expect(effects == [.present(.awaitingPermission)])
        #expect(flow.step == .awaitingPermission)
    }

    @Test("起動処理が終わる前にメニューから開いていたら、起動の知らせで出し直さない")
    func launchAfterReopenIsIgnored() {
        var flow = OnboardingFlow(permission: .notGranted)
        _ = flow.handle(.reopenRequested)

        let effects = flow.handle(.launched(hasFinishedBefore: false))

        #expect(effects.isEmpty)
        #expect(flow.step == .explainingPermission)
    }
}
