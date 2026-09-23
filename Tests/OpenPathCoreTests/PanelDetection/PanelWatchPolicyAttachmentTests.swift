import Testing

import OpenPathCore

@Suite("PanelWatchPolicy: 観測するアプリの張り替え")
struct PanelWatchPolicyAttachmentTests {
    private let finderPID = ActiveApplication.finder.processID
    private let claudePID = ActiveApplication.claude.processID

    // MARK: - 開始と停止

    @Test("開始すると最前面のアプリに張り付き、すぐに走査してポーリングを始める")
    func startAttachesToFrontmostApplication() {
        var driver = PolicyDriver()

        let steps = driver.send(.start(frontmost: .finder))

        #expect(steps == [.attach(finderPID), .scan(finderPID), .startPolling])
        #expect(driver.policy.isStarted)
        #expect(driver.policy.attachedProcessID == finderPID)
        #expect(driver.policy.isPolling)
    }

    @Test("最前面のアプリが分からなければ、開始しても張り付かずポーリングもしない")
    func startWithoutFrontmostApplication() {
        var driver = PolicyDriver()

        let steps = driver.send(.start(frontmost: nil))

        #expect(steps.isEmpty)
        #expect(driver.policy.isStarted)
        #expect(driver.policy.attachedProcessID == nil)
        #expect(!driver.policy.isPolling)
    }

    @Test("開始済みなら start を無視する")
    func startTwiceIsIgnored() {
        var driver = PolicyDriver()
        driver.startWatching()

        let steps = driver.send(.start(frontmost: .claude))

        #expect(steps.isEmpty)
        #expect(driver.policy.attachedProcessID == finderPID)
    }

    @Test("開始前のアプリ切り替えでは張り付かない")
    func activationBeforeStartIsIgnored() {
        var driver = PolicyDriver()

        let steps = driver.send(.applicationActivated(.finder))

        #expect(steps.isEmpty)
        #expect(driver.policy.attachedProcessID == nil)
    }

    @Test("停止すると観測とポーリングをやめ、停止中のアプリ切り替えは追わない")
    func stopDetachesAndIgnoresLaterActivations() {
        var driver = PolicyDriver()
        driver.startWatching()

        #expect(driver.send(.stop) == [.detach, .stopPolling])
        #expect(!driver.policy.isStarted)
        #expect(driver.policy.attachedProcessID == nil)
        #expect(!driver.policy.isPolling)

        #expect(driver.send(.applicationActivated(.claude)).isEmpty)
        #expect(driver.send(.stop).isEmpty)
    }

    @Test("停止後に再び開始すると、その時点の最前面のアプリに張り付く")
    func restartAttachesToCurrentFrontmost() {
        var driver = PolicyDriver()
        driver.startWatching()
        driver.send(.stop)

        let steps = driver.send(.start(frontmost: .claude))

        #expect(steps == [.attach(claudePID), .scan(claudePID), .startPolling])
    }

    @Test("再開時に最前面のアプリが分からなければ、停止前に観測していたアプリには張り付かない")
    func restartWithoutFrontmostDoesNotReuseStaleApplication() {
        var driver = PolicyDriver()
        driver.startWatching(.finder)
        driver.send(.stop)

        #expect(driver.send(.start(frontmost: nil)).isEmpty)
        #expect(driver.policy.attachedProcessID == nil)
    }

    @Test("再開時の最前面が自プロセスなら、停止前に観測していたアプリへ張り直す")
    func restartWhileOwnProcessIsFrontmostReattachesPreviousApplication() {
        var driver = PolicyDriver()
        driver.startWatching(.finder)
        driver.send(.stop)

        #expect(driver.send(.start(frontmost: .own)) == [.attach(finderPID), .scan(finderPID), .startPolling])
    }

    // MARK: - アプリの切り替え

    @Test("別のアプリに切り替わると、そのアプリへ張り替えてすぐに走査する")
    func activationSwitchesAttachment() {
        var driver = PolicyDriver()
        driver.startWatching()

        let steps = driver.send(.applicationActivated(.claude))

        // ポーリングは張り替え後のアプリに対して続けるため、止めも再開もしない
        #expect(steps == [.attach(claudePID), .scan(claudePID)])
        #expect(driver.policy.attachedProcessID == claudePID)
        #expect(driver.policy.isPolling)
    }

    @Test("観測中のアプリが再びアクティブになっても何もしない")
    func reactivationOfAttachedApplicationDoesNothing() {
        var driver = PolicyDriver()
        driver.startWatching()

        #expect(driver.send(.applicationActivated(.finder)).isEmpty)
    }

    @Test("自プロセス（openpath）がアクティブになっても、観測中のアプリを外さない")
    func ownProcessActivationKeepsAttachment() {
        var driver = PolicyDriver()
        driver.startWatching()

        let steps = driver.send(.applicationActivated(.own))

        #expect(steps.isEmpty)
        #expect(driver.policy.attachedProcessID == finderPID)
    }

    @Test("開始時の最前面が自プロセスなら張り付かず、次に別のアプリがアクティブになったら張り付く")
    func startWhileOwnProcessIsFrontmost() {
        var driver = PolicyDriver()

        #expect(driver.send(.start(frontmost: .own)).isEmpty)
        #expect(driver.send(.applicationActivated(.finder)) == [.attach(finderPID), .scan(finderPID), .startPolling])
    }

    // MARK: - disabled_apps

    @Test("disabled_apps のアプリがアクティブになったら観測を外し、ポーリングを止める")
    func disabledApplicationDetaches() {
        var driver = PolicyDriver()
        driver.startWatching()

        let steps = driver.send(.applicationActivated(.disabled))

        #expect(steps == [.detach, .stopPolling])
        #expect(driver.policy.attachedProcessID == nil)
        #expect(!driver.policy.isPolling)
    }

    @Test("disabled_apps のアプリが最前面のまま開始しても張り付かない")
    func startWhileDisabledApplicationIsFrontmost() {
        var driver = PolicyDriver()

        #expect(driver.send(.start(frontmost: .disabled)).isEmpty)
        #expect(driver.policy.attachedProcessID == nil)
    }

    @Test("disabled_apps のアプリから有効なアプリへ切り替えると張り付き、ポーリングを再開する")
    func activationFromDisabledToEnabledApplication() {
        var driver = PolicyDriver()
        driver.send(.start(frontmost: .disabled))

        let steps = driver.send(.applicationActivated(.claude))

        #expect(steps == [.attach(claudePID), .scan(claudePID), .startPolling])
    }

    @Test("bundle id を持たないアプリは disabled_apps と照合できないため観測する")
    func bundlelessApplicationIsAttached() {
        var driver = PolicyDriver()
        let bundlelessPID = ActiveApplication.bundleless.processID

        let steps = driver.send(.start(frontmost: .bundleless))

        #expect(steps == [.attach(bundlelessPID), .scan(bundlelessPID), .startPolling])
    }

    @Test("disabled_apps が変わると最前面のアプリを判定し直し、無効になれば外し、有効に戻れば張り直す")
    func disabledAppsChangeReevaluatesFrontmost() {
        let disabledApps = DisabledAppsStub([])
        var driver = PolicyDriver(disabledApps: disabledApps)
        driver.startWatching(.finder)

        disabledApps.bundleIdentifiers = [PanelWatchFixtures.finderBundleIdentifier]
        #expect(driver.send(.disabledAppsChanged) == [.detach, .stopPolling])

        disabledApps.bundleIdentifiers = []
        #expect(driver.send(.disabledAppsChanged) == [.attach(finderPID), .scan(finderPID), .startPolling])
    }

    @Test("disabled_apps が変わっても、観測中のアプリに影響がなければ何もしない")
    func unrelatedDisabledAppsChangeDoesNothing() {
        let disabledApps = DisabledAppsStub([])
        var driver = PolicyDriver(disabledApps: disabledApps)
        driver.startWatching(.finder)

        disabledApps.bundleIdentifiers = [PanelWatchFixtures.claudeBundleIdentifier]

        #expect(driver.send(.disabledAppsChanged).isEmpty)
    }

    // MARK: - アプリの終了

    @Test("観測中のアプリが終了したら観測を外し、ポーリングを止める")
    func terminationOfAttachedApplicationDetaches() {
        var driver = PolicyDriver()
        driver.startWatching()

        let steps = driver.send(.applicationTerminated(processID: finderPID))

        #expect(steps == [.detach, .stopPolling])
        #expect(driver.policy.attachedProcessID == nil)
    }

    @Test("観測していないアプリの終了は無視する")
    func terminationOfOtherApplicationIsIgnored() {
        var driver = PolicyDriver()
        driver.startWatching()

        #expect(driver.send(.applicationTerminated(processID: claudePID)).isEmpty)
        #expect(driver.policy.attachedProcessID == finderPID)
    }
}
