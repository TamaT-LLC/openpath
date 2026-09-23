import Testing

import OpenPathCore

@MainActor
@Suite("PaletteQuerySession", .timeLimit(.minutes(1)))
struct PaletteQuerySessionTests {
    /// 反映された候補を記録する。
    @MainActor
    final class AppliedRows {
        struct Application: Equatable {
            let rows: [PaletteRow]
            let keepingSelection: Bool
        }

        private(set) var applications: [Application] = []
        private let waiter = ConditionWaiter()

        func apply(_ rows: [PaletteRow], keepingSelection: Bool) {
            applications.append(Application(rows: rows, keepingSelection: keepingSelection))
            waiter.notify()
        }

        func waitForApplications(_ count: Int) async {
            await waiter.wait { self.applications.count >= count }
        }
    }

    private let search = ScriptedPaletteSearch()
    private let applied = AppliedRows()
    private let session: PaletteQuerySession

    init() {
        let applied = applied
        session = PaletteQuerySession(search: search.search) { rows, keepingSelection in
            applied.apply(rows, keepingSelection: keepingSelection)
        }
    }

    @Test("検索語・ディレクトリの絞り込み・件数の上限を渡して候補を引き、結果を反映する")
    func appliesResult() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")

        session.request("fern", directoriesOnly: true)
        await search.waitForCalls(1)
        search.respond(to: 0, with: rows)
        await applied.waitForApplications(1)

        #expect(search.calls == [.init(text: "fern", directoriesOnly: true, limit: PaletteQuerySession.resultLimit)])
        #expect(applied.applications == [.init(rows: rows, keepingSelection: false)])
    }

    @Test("件数の上限はリストでスクロールして辿れる程度にする")
    func resultLimitCoversScrolling() {
        #expect(PaletteQuerySession.resultLimit > PaletteMetrics.standard.maxVisibleRowCount)
    }

    @Test("選択を保つかを反映先へ渡す")
    func passesKeepingSelection() async {
        session.request("", directoriesOnly: false, keepingSelection: true)
        await search.waitForCalls(1)
        search.respond(to: 0, with: PaletteRowFixtures.rows("fern"))
        await applied.waitForApplications(1)

        #expect(applied.applications.map(\.keepingSelection) == [true])
    }

    @Test("新しい要求は前の要求を取り消し、前の要求は反映しない")
    func newRequestCancelsPrevious() async {
        let latest = PaletteRowFixtures.rows("fern")

        session.request("f", directoriesOnly: false)
        await search.waitForCalls(1)
        session.request("fe", directoriesOnly: false)
        await search.waitForCancellation(of: 0)
        await search.waitForCalls(2)
        search.fail(0, with: CancellationError())
        search.respond(to: 1, with: latest)
        await applied.waitForApplications(1)
        await MainActorQueue.drain()

        #expect(search.calls.map(\.text) == ["f", "fe"])
        #expect(applied.applications == [.init(rows: latest, keepingSelection: false)])
    }

    @Test("取り消しを無視して前の要求の結果が後から届いても、最新の要求の結果だけを反映する")
    func staleResultIsDiscarded() async {
        let stale = PaletteRowFixtures.rows("stale")
        let latest = PaletteRowFixtures.rows("latest")

        session.request("s", directoriesOnly: false)
        await search.waitForCalls(1)
        session.request("l", directoriesOnly: false)
        await search.waitForCalls(2)
        search.respond(to: 1, with: latest)
        await applied.waitForApplications(1)
        search.respond(to: 0, with: stale)
        await MainActorQueue.drain()

        #expect(applied.applications == [.init(rows: latest, keepingSelection: false)])
    }

    @Test("cancel() した要求は取り消し、結果が届いても反映しない")
    func cancelDiscardsPendingResult() async {
        session.request("fern", directoriesOnly: false)
        await search.waitForCalls(1)

        session.cancel()
        await search.waitForCancellation(of: 0)
        search.respond(to: 0, with: PaletteRowFixtures.rows("fern"))
        await MainActorQueue.drain()

        #expect(applied.applications.isEmpty)
    }

    @Test("取り消し以外のエラーでは候補を変えない")
    func otherErrorKeepsRows() async {
        struct SearchFailure: Error {}

        session.request("fern", directoriesOnly: false)
        await search.waitForCalls(1)
        search.fail(0, with: SearchFailure())
        await MainActorQueue.drain()

        #expect(applied.applications.isEmpty)
    }

    @Test("エラーの後も次の要求は反映する")
    func recoversAfterError() async {
        struct SearchFailure: Error {}
        let rows = PaletteRowFixtures.rows("fern")

        session.request("f", directoriesOnly: false)
        await search.waitForCalls(1)
        search.fail(0, with: SearchFailure())
        await MainActorQueue.drain()
        session.request("fe", directoriesOnly: false)
        await search.waitForCalls(2)
        search.respond(to: 1, with: rows)
        await applied.waitForApplications(1)

        #expect(applied.applications == [.init(rows: rows, keepingSelection: false)])
    }
}
