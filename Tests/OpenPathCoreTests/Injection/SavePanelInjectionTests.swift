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

    /// キャンセル後も同じ保存パネルが前面なら名前を戻すが、別のウィンドウへは書き込まない。
    @Test(arguments: [false, true])
    func cancellationRestoresOnlyOriginalTarget(targetChanged: Bool) async {
        let log = InjectionEventLog(clock: VirtualClock())
        let filename = PanelElementFake("filename", log: log)
        filename.simulateTyping("original.txt")
        let harness = FlowHarness(saveFilename: SaveFilenamePreservation { _ in filename })
        harness.pasteboard.onWrite = { snapshot in
            guard snapshot != .userClipboard else { return }
            filename.simulateTyping("changed.txt")
            if targetChanged {
                harness.targetGuard.invalidation = (fromCheck: 0, status: .notFrontmost)
            }
            cancelCurrentTask()
        }
        let task = Task {
            try await harness.flow.run(path: NSTemporaryDirectory(), autoConfirm: true, panelKind: .save)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(filename.currentValue == (targetChanged ? "changed.txt" : "original.txt"))
        #expect(harness.pasteboard.contents == .userClipboard)
        #expect(!harness.log.events.contains(.press(element: "open")))
    }

    @Test func cancellationAfterNavigationStillRestoresName() async {
        let log = InjectionEventLog(clock: VirtualClock())
        let filename = PanelElementFake("filename", log: log)
        filename.simulateTyping("original.txt")
        let harness = FlowHarness(
            saveFilename: SaveFilenamePreservation { _ in filename },
            afterSubmit: { cancelCurrentTask() }
        )
        harness.pasteboard.onWrite = { snapshot in
            if snapshot != .userClipboard { filename.simulateTyping("changed.txt") }
        }
        let task = Task {
            try await harness.flow.run(path: NSTemporaryDirectory(), autoConfirm: true, panelKind: .save)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(harness.log.events.contains(.didSubmitGoToSheet(autoConfirm: false)))
        #expect(filename.currentValue == "original.txt")
    }

    @Test func filenameCleanupDoesNotReplaceOriginalFailure() async {
        let log = InjectionEventLog(clock: VirtualClock())
        let filename = PanelElementFake("filename", log: log)
        filename.simulateTyping("original.txt")
        filename.setValueError = InjectionError.axError(code: -25204)
        let harness = FlowHarness(saveFilename: SaveFilenamePreservation { _ in filename })
        harness.pasteboard.onWrite = { snapshot in
            guard snapshot != .userClipboard else { return }
            filename.simulateTyping("changed.txt")
            harness.pasteboard.remainingWriteFailures = 20
        }
        await #expect(throws: InjectionError.pasteboardRestoreFailed) {
            try await harness.flow.run(path: NSTemporaryDirectory(), autoConfirm: true, panelKind: .save)
        }
        #expect(log.events.contains(.setValue(element: "filename", value: "original.txt")))
    }

}
