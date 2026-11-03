import Foundation
import Testing
@testable import OpenPathCore

@Suite("保存先の注入: ファイル名保持と自動保存の禁止")
@MainActor
struct SavePanelInjectionTests {
    /// 主方式と副方式のそれぞれで、移動中の名前変更が復元され、保存が確定されないことを確認する。
    @Test(arguments: [false, true])
    func preservesFilenameAndNeverConfirms(secondary: Bool) async throws {
        let log = InjectionEventLog(clock: VirtualClock())
        let filename = PanelElementFake("filename", log: log)
        let original = "見積書 2026.txt"
        filename.simulateTyping(original)
        let preservation = SaveFilenamePreservation { _ in filename }
        let harness = FlowHarness(sheetAppearsAt: secondary ? nil : .milliseconds(150), saveFilename: preservation)
        // 移動中にパネルがファイル名を変えた場合も、拡張子を含めて元に戻す。
        harness.pasteboard.onWrite = { _ in filename.simulateTyping("changed.txt") }
        if secondary {
            harness.goButton.onActivate = {
                filename.simulateTyping("changed.txt")
                harness.closeGoToSheet()
            }
        }
        try await harness.flow.run(path: NSTemporaryDirectory(), autoConfirm: true, panelKind: .save)
        #expect(filename.currentValue == original)
        #expect(!harness.log.events.contains(.press(element: "open")))
        #expect(harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
        #expect(harness.pasteboard.contents == .userClipboard)
    }

    @Test func missingFilenameStopsBeforeKeyboard() async {
        let harness = FlowHarness(saveFilename: SaveFilenamePreservation { _ in nil })
        await #expect(throws: InjectionError.saveFilenameUnavailable) {
            try await harness.flow.run(path: NSTemporaryDirectory(), autoConfirm: true, panelKind: .save)
        }
        #expect(!harness.log.events.contains(.prepareForKeyEvents))
    }

    @Test func fileDestinationStopsBeforeKeyboard() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let harness = FlowHarness()
        await #expect(throws: InjectionError.saveDestinationNotDirectory) {
            try await harness.flow.run(path: file.path, autoConfirm: true, panelKind: .save)
        }
        #expect(harness.log.events.isEmpty)
    }

    @Test func failedRestorationIsReported() async {
        let log = InjectionEventLog(clock: VirtualClock())
        let filename = PanelElementFake("filename", log: log)
        filename.simulateTyping("original.txt")
        filename.setValueError = InjectionError.axError(code: -25204)
        let harness = FlowHarness(saveFilename: SaveFilenamePreservation { _ in filename })
        harness.pasteboard.onWrite = { _ in filename.simulateTyping("changed.txt") }
        await #expect(throws: InjectionError.axError(code: -25204)) {
            try await harness.flow.run(path: NSTemporaryDirectory(), autoConfirm: true, panelKind: .save)
        }
        #expect(!harness.log.events.contains(.press(element: "open")))
    }
}
