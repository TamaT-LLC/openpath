import Testing

import OpenPathCore

@MainActor
@Suite("OnboardingController: 案内の副作用の実行と記録")
struct OnboardingControllerTests {
    private static func makeController(
        permission: AccessibilityPermissionStatus,
        hasFinished: Bool = false
    ) -> (controller: OnboardingController, services: OnboardingServicesSpy, record: OnboardingRecordFake) {
        let services = OnboardingServicesSpy()
        let record = OnboardingRecordFake(hasFinishedOnboarding: hasFinished)
        let controller = OnboardingController(services: services, record: record, permission: permission)
        return (controller, services, record)
    }

    @Test("初回の起動では記録を読んで案内を出す")
    func firstLaunchPresents() {
        let (controller, services, record) = Self.makeController(permission: .notGranted)

        controller.launched()

        #expect(services.calls == [.present(.permissionExplanation)])
        #expect(record.recordCount == 0)
        #expect(controller.flow.step == .explainingPermission)
    }

    @Test("案内を終えた記録があれば、起動しても何もしない")
    func finishedRecordSuppressesOnboarding() {
        let (controller, services, _) = Self.makeController(permission: .notGranted, hasFinished: true)

        controller.launched()

        #expect(services.calls.isEmpty)
    }

    @Test("システム設定を開き、権限の付与で設定ファイルを用意して完了を出す")
    func permissionFlow() {
        let (controller, services, _) = Self.makeController(permission: .notGranted)
        controller.launched()

        controller.perform(.openSystemSettings)
        controller.permissionDidChange(.granted)

        #expect(services.calls == [
            .present(.permissionExplanation),
            .present(.awaitingPermission),
            .openAccessibilitySettings,
            .prepareConfigFile,
            .present(.ready),
        ])
    }

    @Test("「試してみる」で案内を閉じ、終えたことを記録してから「開く」ダイアログを出す")
    func tryOpenPanelRecordsAndLaunches() {
        let (controller, services, record) = Self.makeController(permission: .granted)
        controller.launched()

        controller.perform(.tryOpenPanel)

        #expect(services.calls.suffix(2) == [.dismiss, .launchTrialPanel])
        #expect(record.recordCount == 1)
        #expect(record.hasFinishedOnboarding)
    }

    @Test("スキップでも終えたことを記録する")
    func skipRecords() {
        let (controller, services, record) = Self.makeController(permission: .notGranted)
        controller.launched()

        controller.perform(.close)

        #expect(services.calls.last == .dismiss)
        #expect(record.hasFinishedOnboarding)
        #expect(controller.flow.step == .skipped)
    }

    @Test("メニューから開き直せる")
    func reopen() {
        let (controller, services, _) = Self.makeController(permission: .granted, hasFinished: true)
        controller.launched()

        controller.reopen()

        #expect(services.calls == [.prepareConfigFile, .present(.ready)])
    }
}

/// OnboardingController からの呼び出しを順に記録する。
@MainActor
final class OnboardingServicesSpy: OnboardingServices {
    enum Call: Equatable {
        case present(OnboardingPage)
        case dismiss
        case openAccessibilitySettings
        case prepareConfigFile
        case launchTrialPanel
    }

    private(set) var calls: [Call] = []

    func presentOnboarding(_ page: OnboardingPage) {
        calls.append(.present(page))
    }

    func dismissOnboarding() {
        calls.append(.dismiss)
    }

    func openAccessibilitySettings() {
        calls.append(.openAccessibilitySettings)
    }

    func prepareConfigFile() {
        calls.append(.prepareConfigFile)
    }

    func launchTrialPanel() {
        calls.append(.launchTrialPanel)
    }
}

/// メモリ上に案内を終えたかを持つ OnboardingRecording。
@MainActor
final class OnboardingRecordFake: OnboardingRecording {
    private(set) var hasFinishedOnboarding: Bool
    private(set) var recordCount = 0

    init(hasFinishedOnboarding: Bool) {
        self.hasFinishedOnboarding = hasFinishedOnboarding
    }

    func recordOnboardingFinished() {
        hasFinishedOnboarding = true
        recordCount += 1
    }
}
