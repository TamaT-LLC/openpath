import Testing

import OpenPathCore

@Suite("GoToSheetState: 移動先シートを確定してよいかの判定（Issue #74）")
struct GoToSheetStateTests {
    private static let normalizer = InjectionPathNormalizer(homeDirectory: "/Users/me")
    private static let path = "/Users/me/Library"

    @Test(
        "入力欄の値と候補の選択から判定する",
        arguments: [
            // 入力欄が移動先で、候補リストが無い（旧来のシート）・選択が無い
            (GoToSheetState(fieldValue: "/Users/me/Library", selectedSuggestion: nil), GoToSheetReadiness.ready),
            // 候補の選択も移動先
            (GoToSheetState(fieldValue: "/Users/me/Library", selectedSuggestion: "/Users/me/Library"), .ready),
            // 貼り付け直後: 候補リストが前の値（前回の移動先）の候補を選んだまま
            (GoToSheetState(fieldValue: "/Users/me/Library", selectedSuggestion: "/Users/me/Desktop"), .suggestionNotUpdated),
            // 貼り付けが効かず、前回の値が残っている
            (GoToSheetState(fieldValue: "/Users/me/Desktop", selectedSuggestion: "/Users/me/Desktop"), .fieldMismatch),
            // ⌘A が効かずに追記された
            (GoToSheetState(fieldValue: "/Users/me/Desktop/Users/me/Library", selectedSuggestion: nil), .fieldMismatch),
            (GoToSheetState(fieldValue: "", selectedSuggestion: nil), .fieldMismatch),
            // 入力欄の値を読めない
            (GoToSheetState(fieldValue: nil, selectedSuggestion: "/Users/me/Library"), .unavailable),
        ]
    )
    func readiness(state: GoToSheetState, expected: GoToSheetReadiness) {
        #expect(state.readiness(for: Self.path, normalizer: Self.normalizer) == expected)
    }

    @Test(
        "表記の違い（末尾の /、~、. と ..、NFC と NFD）は同じパスとして比べる",
        arguments: [
            "/Users/me/Library/",
            "~/Library",
            "/Users/me/./Documents/../Library",
        ]
    )
    func comparesNormalizedPaths(fieldValue: String) {
        let state = GoToSheetState(fieldValue: fieldValue, selectedSuggestion: fieldValue)

        #expect(state.readiness(for: Self.path, normalizer: Self.normalizer) == .ready)
    }

    @Test("日本語のパスは NFC と NFD を同じものとして比べる")
    func comparesCanonicallyEquivalentPaths() {
        let nfc = "/Users/me/Documents/資料/ガイド"
        let nfd = nfc.decomposedStringWithCanonicalMapping
        let state = GoToSheetState(fieldValue: nfd, selectedSuggestion: nfd)

        #expect(state.readiness(for: nfc, normalizer: Self.normalizer) == .ready)
    }
}

@Suite("GoToSheetSubmitGate: 確定の前に入力欄と候補の選択が移動先になるのを待つ（Issue #74）", .timeLimit(.minutes(1)))
@MainActor
struct GoToSheetSubmitGateTests {
    private static let path = "/Users/me/Library"
    private static let previousPath = "/Users/me/Desktop"

    @MainActor
    private final class Harness {
        let clock = VirtualClock()
        let log: InjectionEventLog
        let field: PanelElementFake
        let suggestions = SuggestionListFake()
        let locator: GoToFieldLocatorFake
        let gate: GoToSheetSubmitGate

        init() {
            let log = InjectionEventLog(clock: clock)
            self.log = log
            field = PanelElementFake("path", log: log)
            field.simulateTyping(GoToSheetSubmitGateTests.path)
            locator = GoToFieldLocatorFake(clock: clock, log: log)
            locator.field = field
            locator.suggestionList = suggestions
            gate = GoToSheetSubmitGate(
                locator: locator,
                normalizer: InjectionPathNormalizer(homeDirectory: "/Users/me"),
                clock: clock
            )
        }

        func wait(controls: GoToFieldControls? = nil) async throws -> GoToSheetReadiness {
            try await gate.waitUntilReady(path: GoToSheetSubmitGateTests.path, controls: controls)
        }
    }

    @Test("待ち時間の既定値: 探すのは 150ms まで、追いつくのを 250ms まで 50ms 間隔で待つ")
    func standardTiming() {
        let timing = GoToSheetSubmitTiming.standard

        #expect(timing.lookupLimit == .milliseconds(150))
        #expect(timing.settleLimit == .milliseconds(250))
        #expect(timing.pollInterval == .milliseconds(50))
    }

    @Test("入力欄が移動先で候補の選択も移動先なら、待たずに ready を返す")
    func readyImmediately() async throws {
        let harness = Harness()
        harness.suggestions.selectedPathProvider = { Self.path }

        #expect(try await harness.wait() == .ready)
        #expect(harness.clock.elapsed == .zero)
        #expect(harness.locator.lookupCount == 1)
        #expect(harness.field.valueReadCount == 1)
    }

    @Test("候補の選択が前の値のままなら 50ms ごとに確かめ直し、追いついた時点で ready を返す")
    func waitsUntilSuggestionCatchesUp() async throws {
        let harness = Harness()
        harness.suggestions.selectedPathProvider = { [clock = harness.clock] in
            clock.elapsed >= .milliseconds(120) ? Self.path : Self.previousPath
        }

        #expect(try await harness.wait() == .ready)
        #expect(harness.clock.elapsed == .milliseconds(150))
        #expect(harness.field.valueReadCount == 4)
    }

    @Test("候補の選択が 250ms までに追いつかなければ suggestionNotUpdated を返す（呼び出し側はそのまま確定する）")
    func givesUpWaitingForSuggestion() async throws {
        let harness = Harness()
        harness.suggestions.selectedPathProvider = { Self.previousPath }

        #expect(try await harness.wait() == .suggestionNotUpdated)
        #expect(harness.clock.elapsed == .milliseconds(250))
        #expect(harness.field.valueReadCount == 6)
    }

    @Test("入力欄の値が 250ms までに移動先にならなければ fieldMismatch を返す")
    func reportsFieldMismatch() async throws {
        let harness = Harness()
        harness.field.valueProvider = { Self.previousPath }

        #expect(try await harness.wait() == .fieldMismatch)
        #expect(harness.clock.elapsed == .milliseconds(250))
    }

    @Test("貼り付けの反映が遅れても、期限までに入力欄が移動先になれば ready を返す")
    func waitsForSlowPaste() async throws {
        let harness = Harness()
        harness.field.valueProvider = { [clock = harness.clock] in
            clock.elapsed >= .milliseconds(80) ? Self.path : Self.previousPath
        }

        #expect(try await harness.wait() == .ready)
        #expect(harness.clock.elapsed == .milliseconds(100))
    }

    @Test("入力欄が見つからなければ、待たずに unavailable を返す（呼び出し側は確かめずに確定する）")
    func unavailableWithoutField() async throws {
        let harness = Harness()
        harness.locator.field = nil

        #expect(try await harness.wait() == .unavailable)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test(
        "探すのに失敗したら（AX の失敗・パネルが消えた・InjectionError 以外）、投げずに unavailable を返す",
        arguments: [
            InjectionError.axError(code: -25_204) as any Error,
            InjectionError.panelGone,
            AdapterFailure(),
        ]
    )
    func lookupFailureIsUnavailable(error: any Error) async throws {
        let harness = Harness()
        harness.locator.error = error

        #expect(try await harness.wait() == .unavailable)
    }

    @Test("探すのが 150ms を超えたら打ち切り、unavailable を返す")
    func lookupCutOffIsUnavailable() async throws {
        let harness = Harness()
        // 走査は 4 回の AX 操作に分かれ、1 回目の後（150ms）の操作の前で打ち切られる
        harness.locator.lookupLatency = .milliseconds(600)

        #expect(try await harness.wait() == .unavailable)
        #expect(harness.log.events.contains(.scanCutOff))
        #expect(harness.clock.elapsed == .milliseconds(150))
    }

    @Test("入力欄の値を読めなければ unavailable を返す")
    func valueReadFailureIsUnavailable() async throws {
        let harness = Harness()
        harness.field.valueReadError = InjectionError.axError(code: -25_204)

        #expect(try await harness.wait() == .unavailable)
        #expect(harness.clock.elapsed == .zero)
    }

    @Test("候補の選択を読めなくても、入力欄の値だけで判定する")
    func suggestionReadFailureIsIgnored() async throws {
        let harness = Harness()
        harness.suggestions.readError = InjectionError.axError(code: -25_204)

        #expect(try await harness.wait() == .ready)
    }

    @Test("見つけ済みの入力欄を渡されたら、探し直さない（副方式）")
    func usesKnownControls() async throws {
        let harness = Harness()
        let controls = GoToFieldControls(field: harness.field, goButton: nil, suggestionList: harness.suggestions)

        #expect(try await harness.wait(controls: controls) == .ready)
        #expect(harness.locator.lookupCount == 0)
    }

    @Test("待っている間にキャンセルされたら CancellationError を投げる")
    func cancelledWhileWaiting() async {
        let harness = Harness()
        harness.suggestions.selectedPathProvider = {
            cancelCurrentTask()
            return Self.previousPath
        }

        await #expect(throws: CancellationError.self) {
            try await harness.wait()
        }
    }
}
