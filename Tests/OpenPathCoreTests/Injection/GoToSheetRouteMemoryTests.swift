import Testing

import OpenPathCore

@Suite("GoToSheetRouteMemory: 注入先のプロセスへの ⌘⇧G でシートが出なかった注入先を覚える")
@MainActor
struct GoToSheetRouteMemoryTests {
    private static let vscode = InjectionTargetIdentity(bundleIdentifier: "com.example.editor", processID: 501)
    private static let textEdit = InjectionTargetIdentity(bundleIdentifier: "com.example.text", processID: 502)

    @Test("覚えていない注入先では、注入先のプロセスへの ⌘⇧G を飛ばさない")
    func doesNotSkipUnknownTarget() {
        let memory = GoToSheetRouteMemory()

        #expect(!memory.skipsTargetProcessRoute(for: Self.vscode))
    }

    @Test("出なかった注入先を覚えると、同じ注入先では飛ばし、別の注入先では飛ばさない")
    func skipsOnlyRememberedTarget() {
        let memory = GoToSheetRouteMemory()

        memory.recordTargetProcessRouteMissed(for: Self.vscode)

        #expect(memory.skipsTargetProcessRoute(for: Self.vscode))
        #expect(!memory.skipsTargetProcessRoute(for: Self.textEdit))
    }

    @Test("bundle id が同じなら、プロセスが変わっても（再起動後も）同じ注入先とみなす")
    func identifiesByBundleIdentifier() {
        let memory = GoToSheetRouteMemory()

        memory.recordTargetProcessRouteMissed(for: Self.vscode)

        #expect(memory.skipsTargetProcessRoute(for: InjectionTargetIdentity(bundleIdentifier: "com.example.editor", processID: 999)))
    }

    @Test("bundle id が無い・空なら pid で見分ける", arguments: [nil, ""] as [String?])
    func identifiesByProcessIDWithoutBundleIdentifier(bundleIdentifier: String?) {
        let memory = GoToSheetRouteMemory()

        memory.recordTargetProcessRouteMissed(for: InjectionTargetIdentity(bundleIdentifier: bundleIdentifier, processID: 700))

        #expect(memory.skipsTargetProcessRoute(for: InjectionTargetIdentity(bundleIdentifier: nil, processID: 700)))
        #expect(!memory.skipsTargetProcessRoute(for: InjectionTargetIdentity(bundleIdentifier: nil, processID: 701)))
    }

    @Test("忘れると、また注入先のプロセスへの ⌘⇧G から試す")
    func forgetsTarget() {
        let memory = GoToSheetRouteMemory()
        memory.recordTargetProcessRouteMissed(for: Self.vscode)

        memory.forget(Self.vscode)

        #expect(!memory.skipsTargetProcessRoute(for: Self.vscode))
    }

    @Test("注入先を識別できなければ（nil）、覚えず・飛ばさない")
    func ignoresUnidentifiedTarget() {
        let memory = GoToSheetRouteMemory()

        memory.recordTargetProcessRouteMissed(for: nil)

        #expect(!memory.skipsTargetProcessRoute(for: nil))
    }
}
