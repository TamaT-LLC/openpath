import Testing

import OpenPathCore

@MainActor
@Suite("AppLifecycle", .timeLimit(.minutes(1)))
struct AppLifecycleTests {
    // MARK: - 起動

    @Test("起動は設定の読み込み → 候補の構築 → パネルの監視 → ホットキーの順に始める")
    func launchOrder() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)

        await lifecycle.launch()

        #expect(services.calls == [
            .loadConfiguration,
            .startCandidateIndexing,
            .setPanelWatching(true),
            .setHotkeyRegistered(true),
        ])
        #expect(lifecycle.phase == .running)
        #expect(lifecycle.isPanelWatching)
        #expect(lifecycle.isHotkeyRegistered)
    }

    @Test("アクセシビリティ権限が無ければパネルの監視を始めない（ホットキーは登録する）")
    func launchWithoutPermission() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .notGranted)

        await lifecycle.launch()

        #expect(services.calls == [.loadConfiguration, .startCandidateIndexing, .setHotkeyRegistered(true)])
        #expect(lifecycle.isPanelWatching == false)
    }

    @Test("2 回目の起動は何もしない")
    func launchIsIdempotent() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)
        await lifecycle.launch()

        await lifecycle.launch()

        #expect(services.calls.filter { $0 == .loadConfiguration }.count == 1)
    }

    @Test("設定の読み込みを終えるまでは、候補の構築もパネルの監視も始めない")
    func waitsForConfiguration() async {
        let services = AppLifecycleServicesSpy(holdsConfigurationLoading: true)
        let lifecycle = AppLifecycle(services: services, permission: .granted)

        let launch = Task { await lifecycle.launch() }
        await services.waitForConfigurationLoading()
        let callsWhileLoading = services.calls
        let phaseWhileLoading = lifecycle.phase
        services.finishLoadingConfiguration()
        await launch.value

        #expect(callsWhileLoading == [.loadConfiguration])
        #expect(phaseWhileLoading == .launching)
        #expect(services.calls.last == .setHotkeyRegistered(true))
    }

    // MARK: - 権限の変化

    @Test("権限が付与されたらパネルの監視を始め、取り消されたら止める")
    func followsPermission() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .notGranted)
        await lifecycle.launch()

        lifecycle.permissionDidChange(.granted)
        lifecycle.permissionDidChange(.notGranted)

        #expect(services.calls.suffix(2) == [.setPanelWatching(true), .setPanelWatching(false)])
        #expect(lifecycle.isPanelWatching == false)
    }

    @Test("同じ権限の通知では何もしない")
    func ignoresSamePermission() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)
        await lifecycle.launch()
        let callsAfterLaunch = services.calls

        lifecycle.permissionDidChange(.granted)

        #expect(services.calls == callsAfterLaunch)
    }

    @Test("起動中に権限が付与されたら、起動を終えた時点で監視を始める")
    func permissionGrantedWhileLaunching() async {
        let services = AppLifecycleServicesSpy(holdsConfigurationLoading: true)
        let lifecycle = AppLifecycle(services: services, permission: .notGranted)
        let launch = Task { await lifecycle.launch() }
        await services.waitForConfigurationLoading()

        lifecycle.permissionDidChange(.granted)
        let callsWhileLoading = services.calls
        services.finishLoadingConfiguration()
        await launch.value

        #expect(callsWhileLoading == [.loadConfiguration])
        #expect(services.calls.contains(.setPanelWatching(true)))
    }

    // MARK: - 有効・無効（メニューの「有効」）

    @Test("無効にするとパネルの監視とホットキーを止め、有効に戻すと再開する")
    func followsEnabled() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)
        await lifecycle.launch()

        lifecycle.setEnabled(false)
        let callsAfterDisabling = services.calls.suffix(2)
        lifecycle.setEnabled(true)

        #expect(Array(callsAfterDisabling) == [.setPanelWatching(false), .setHotkeyRegistered(false)])
        #expect(services.calls.suffix(2) == [.setPanelWatching(true), .setHotkeyRegistered(true)])
        #expect(lifecycle.isEnabled)
    }

    @Test("無効の間に権限が付与されても監視を始めず、有効に戻したときに始める")
    func permissionWhileDisabled() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .notGranted)
        await lifecycle.launch()
        lifecycle.setEnabled(false)

        lifecycle.permissionDidChange(.granted)
        let watchedWhileDisabled = lifecycle.isPanelWatching
        lifecycle.setEnabled(true)

        #expect(watchedWhileDisabled == false)
        #expect(services.calls.suffix(2) == [.setPanelWatching(true), .setHotkeyRegistered(true)])
    }

    @Test("起動前に無効にしたら、起動しても監視もホットキーも始めない")
    func disabledBeforeLaunch() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)

        lifecycle.setEnabled(false)
        await lifecycle.launch()

        #expect(services.calls == [.loadConfiguration, .startCandidateIndexing])
    }

    @Test("同じ値の設定や、終了後の設定では何もしない")
    func ignoresRedundantEnabled() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)
        await lifecycle.launch()
        let callsAfterLaunch = services.calls

        lifecycle.setEnabled(true)
        let callsAfterRedundant = services.calls
        lifecycle.terminate()
        let callsAfterTerminate = services.calls
        lifecycle.setEnabled(false)

        #expect(callsAfterRedundant == callsAfterLaunch)
        #expect(services.calls == callsAfterTerminate)
    }

    // MARK: - 終了

    @Test("終了はパネルの監視 → ホットキーを止めてから終了処理をする")
    func terminateOrder() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)
        await lifecycle.launch()

        lifecycle.terminate()

        #expect(services.calls.suffix(3) == [.setPanelWatching(false), .setHotkeyRegistered(false), .shutDown])
        #expect(lifecycle.phase == .terminated)
    }

    @Test("終了は 1 度だけ行い、終了後の権限の変化では監視を始めない")
    func terminateIsFinal() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .notGranted)
        await lifecycle.launch()
        lifecycle.terminate()
        let callsAfterTerminate = services.calls

        lifecycle.terminate()
        lifecycle.permissionDidChange(.granted)

        #expect(services.calls == callsAfterTerminate)
        #expect(services.calls.filter { $0 == .shutDown }.count == 1)
    }

    @Test("設定の読み込み中に終了したら、読み込み後に候補の構築も監視も始めない")
    func terminateWhileLaunching() async {
        let services = AppLifecycleServicesSpy(holdsConfigurationLoading: true)
        let lifecycle = AppLifecycle(services: services, permission: .granted)
        let launch = Task { await lifecycle.launch() }
        await services.waitForConfigurationLoading()

        lifecycle.terminate()
        services.finishLoadingConfiguration()
        await launch.value

        #expect(services.calls == [.loadConfiguration, .shutDown])
        #expect(lifecycle.phase == .terminated)
    }

    @Test("起動前に終了したら終了処理だけを行い、以降の起動は何もしない")
    func terminateBeforeLaunch() async {
        let services = AppLifecycleServicesSpy()
        let lifecycle = AppLifecycle(services: services, permission: .granted)

        lifecycle.terminate()
        await lifecycle.launch()

        #expect(services.calls == [.shutDown])
    }
}
