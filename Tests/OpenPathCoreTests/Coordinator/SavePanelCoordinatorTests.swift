import Testing
import OpenPathCore

@Suite("保存パネル: 保存を確定しない")
@MainActor
struct SavePanelCoordinatorTests {
    @Test(arguments: [false, true], [false, true])
    func neverAutoConfirms(setting: Bool, command: Bool) async {
        let harness = CoordinatorHarness(isAutoConfirmEnabled: setting)
        let context = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: false, frame: .zero, kind: .save)
        harness.showPanel(context)
        harness.coordinator.handle(.confirm(path: "/tmp", openImmediately: command))
        await harness.waitForState(.idle)
        #expect(harness.injector.calls == [.init(path: "/tmp", autoConfirm: false)])
        #expect(harness.history.recordedPaths == ["/tmp"])
        #expect(context.showsDirectoriesOnly(includeFiles: true))
        #expect(context.withFrame(.zero).kind == .save)
    }

    @Test func unverifiedDestinationDoesNotRecordHistory() async throws {
        let error = InjectionError.saveNavigationUnverified
        let harness = CoordinatorHarness(injectorBehavior: .fail(error))
        let context = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: true, frame: .zero, kind: .save)
        harness.showPanel(context)
        harness.coordinator.handle(.confirm(path: "/tmp", openImmediately: true))
        await harness.waitForState(.panelShown(context, isPaletteVisible: true))
        #expect(harness.history.recordedPaths.isEmpty)
        #expect(harness.palette.calls.contains(.showError(try #require(error.userMessage))))
    }

    @Test func escapeKeepsSavePanel() {
        let harness = CoordinatorHarness()
        let context = PanelContext(id: PanelContext.sample.id, isDirectoriesOnly: true, frame: .zero, kind: .save)
        harness.showPanel(context)
        harness.coordinator.handle(.escape)
        #expect(harness.coordinator.state == .panelShown(context, isPaletteVisible: false))
        #expect(harness.injector.calls.isEmpty)
    }
}
