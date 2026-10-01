import CoreGraphics
import Foundation
import Testing

import OpenPathCore

/// パレットの表示・閉じる・候補の引き直しの診断（実機 QA の FLOW-01・MENU-04・MENU-05 を debug ログで判定するため）。
/// 行数・空状態の案内の有無・待ち時間・パネル ID だけを報告し、パスと検索語は報告しない。
@MainActor
@Suite("PalettePresenter: 診断の報告", .timeLimit(.minutes(1)))
struct PalettePresenterDiagnosticTests {
    private static let usedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private let viewModel = PaletteViewModel(homeDirectory: "/Users/example")
    private let window = PaletteWindowSpy()
    private let search = ScriptedPaletteSearch()
    private let clock = TestClock()
    private let recorder = DiagnosticRecorder<PalettePresenterDiagnostic>()
    /// `palette shown` を知らせた時点で報告済みだった診断の数
    private let shownAt = DiagnosticRecorder<Int>()
    private let presenter: PalettePresenter

    init() {
        let recorder = recorder
        let shownAt = shownAt
        presenter = PalettePresenter(
            viewModel: viewModel,
            window: window,
            includeFiles: { false },
            search: search.search,
            clock: clock,
            didShow: { _ in shownAt.record(recorder.diagnostics.count) },
            diagnose: { recorder.record($0) }
        )
    }

    /// 最後に使った日時を持つ（履歴にある）行。
    private static func usedRows(_ names: String...) -> [PaletteRow] {
        names.map { PaletteRow(name: $0, path: "/Users/example/repos/\($0)", lastUsed: usedAt) }
    }

    /// パレットを出し、最初の候補の検索に `rows` で答えて、ウィンドウが出るまで待つ。
    private func show(_ context: PanelContext, answering rows: [PaletteRow], after waited: Duration = .zero) async {
        let callIndex = search.calls.count
        let shownCount = window.shownCount
        presenter.show(context: context)
        await search.waitForCalls(callIndex + 1)
        clock.advance(by: waited)
        search.respond(to: callIndex, with: rows)
        await MainActorQueue.waitUntil { window.shownCount > shownCount }
    }

    /// `index` 番目（0 始まり）の検索に `rows` で答え、反映されるまで待つ。
    private func answerSearch(_ index: Int, with rows: [PaletteRow]) async {
        await search.waitForCalls(index + 1)
        search.respond(to: index, with: rows)
        await MainActorQueue.waitUntil { viewModel.rows == rows }
    }

    private var revealRecords: [PaletteRevealRecord] {
        recorder.diagnostics.compactMap { if case .revealed(let record) = $0 { record } else { nil } }
    }

    private var refreshRecords: [PaletteRowsRefreshRecord] {
        recorder.diagnostics.compactMap { if case .rowsRefreshed(let record) = $0 { record } else { nil } }
    }

    // MARK: - 表示（FLOW-01）

    @Test("最初の候補が届いてから出したら、出した時点の行数・空状態の案内を出していないこと・待った時間を報告する")
    func reportsRevealAfterInitialRows() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")

        await show(.sample, answering: rows, after: .milliseconds(30))

        #expect(revealRecords == [
            PaletteRevealRecord(
                panelID: PanelContext.sample.id,
                rowCount: rows.count,
                showsEmptyMessage: false,
                initialRows: .received(after: .milliseconds(30))
            ),
        ])
    }

    @Test("palette shown を知らせた直後に報告する（検知レイテンシの終点の行の直後に出る）")
    func reportsRevealRightAfterShownNotification() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))

        #expect(shownAt.diagnostics == [0])
        #expect(recorder.diagnostics.count == 1)
    }

    @Test("0 件の候補を受け取って出したら、空状態の案内を出していることを報告する")
    func reportsEmptyMessageWhenNoCandidates() async {
        await show(.sample, answering: [])

        #expect(revealRecords.map(\.showsEmptyMessage) == [true])
        #expect(revealRecords.map(\.rowCount) == [0])
    }

    @Test("待ちの上限で出したら、上限に達したこと・待った時間を報告する（行は空で、空状態の案内は出していない）")
    func reportsRevealAtWaitLimit() async {
        presenter.show(context: .sample)
        await search.waitForCalls(1)

        clock.advance(by: PalettePresenter.initialRowsWaitLimit)
        await MainActorQueue.waitUntil { window.shownCount == 1 }

        #expect(revealRecords == [
            PaletteRevealRecord(
                panelID: PanelContext.sample.id,
                rowCount: 0,
                showsEmptyMessage: false,
                initialRows: .waitLimitReached(after: PalettePresenter.initialRowsWaitLimit)
            ),
        ])
    }

    @Test("候補を受け取り済みのパネルの再表示では、待たずに出したことを報告する")
    func reportsRevealWithoutWaitOnReshow() async {
        let rows = PaletteRowFixtures.rows("fern", "fern-docs")
        await show(.sample, answering: rows)
        presenter.hide()

        presenter.show(context: .sample)

        #expect(revealRecords.last == PaletteRevealRecord(
            panelID: PanelContext.sample.id,
            rowCount: rows.count,
            showsEmptyMessage: false,
            initialRows: .alreadyReceived
        ))
    }

    // MARK: - 閉じる（PAL-08・S-08）

    @Test("出していたパレットを閉じたら報告する。候補を待っている間に閉じたら、出していなかったことを報告する")
    func reportsHidden() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))
        presenter.hide()
        presenter.show(context: .another)
        await search.waitForCalls(2)
        presenter.hide()
        // 閉じている間の hide（Idle の panelGone 等）では報告しない
        presenter.hide()

        let hidden = recorder.diagnostics.filter { if case .hidden = $0 { true } else { false } }
        #expect(hidden == [
            .hidden(panelID: PanelContext.sample.id, wasVisible: true),
            .hidden(panelID: PanelContext.another.id, wasVisible: false),
        ])
    }

    // MARK: - 候補の差し替え（MENU-04・MENU-05）

    @Test("表示中に候補が差し替わったら、構築中かを報告し、引き直した行数・履歴のある行数・選択を保てたかを報告する")
    func reportsCandidatesChangeAndRefresh() async {
        presenter.candidateRebuildingDidChange(true)
        await show(.sample, answering: Self.usedRows("history-only", "fern"))

        presenter.candidatesDidChange()
        await answerSearch(1, with: PaletteRowFixtures.rows("fern", "openpath", "fern-docs"))

        #expect(recorder.diagnostics.contains(.candidatesChanged(panelID: PanelContext.sample.id, isBuildingCandidates: true)))
        #expect(refreshRecords == [
            PaletteRowsRefreshRecord(
                panelID: PanelContext.sample.id,
                trigger: .candidatesChanged,
                rowCount: 3,
                lastUsedRowCount: 0,
                isSelectionKept: false
            ),
        ])
    }

    @Test("閉じている間に候補が差し替わったら、表示していないことだけを報告する")
    func reportsCandidatesChangeWhileHidden() async {
        presenter.candidatesDidChange()
        await MainActorQueue.drain()

        #expect(recorder.diagnostics == [.candidatesChanged(panelID: nil, isBuildingCandidates: false)])
        #expect(search.calls.isEmpty)
    }

    @Test("全件の再構築の完了で引き直したら、選択を保てたかとともに報告する")
    func reportsRefreshAfterRebuild() async {
        let rows = Self.usedRows("fern", "fern-docs")
        presenter.candidateRebuildingDidChange(true)
        await show(.sample, answering: rows)
        viewModel.moveSelection(by: 1)

        presenter.candidateRebuildingDidChange(false)
        await answerSearch(1, with: rows + PaletteRowFixtures.rows("openpath"))

        #expect(refreshRecords == [
            PaletteRowsRefreshRecord(
                panelID: PanelContext.sample.id,
                trigger: .rebuildFinished,
                rowCount: 3,
                lastUsedRowCount: 2,
                isSelectionKept: true
            ),
        ])
    }

    @Test("検索語の変更で引いた候補は報告しない（打鍵ごとに出さない）")
    func doesNotReportQueryChange() async {
        await show(.sample, answering: PaletteRowFixtures.rows("fern"))

        viewModel.query = "fe"
        await answerSearch(1, with: PaletteRowFixtures.rows("fern", "fern-docs"))

        #expect(refreshRecords.isEmpty)
    }

    // MARK: - ログの文言

    @Test(
        "表示の文言",
        arguments: [
            (
                PaletteRevealRecord.InitialRows.received(after: .milliseconds(34)), 8, false,
                "palette reveal (id: panel-1, rows: 8, emptyMessage: false, waitedForInitialRows: true, waited: 34ms, waitLimitReached: false)"
            ),
            (
                .waitLimitReached(after: .milliseconds(100)), 0, false,
                "palette reveal (id: panel-1, rows: 0, emptyMessage: false, waitedForInitialRows: true, waited: 100ms, waitLimitReached: true)"
            ),
            (
                .alreadyReceived, 0, true,
                "palette reveal (id: panel-1, rows: 0, emptyMessage: true, waitedForInitialRows: false)"
            ),
        ]
    )
    func revealMessage(initialRows: PaletteRevealRecord.InitialRows, rowCount: Int, showsEmptyMessage: Bool, expected: String) {
        let record = PaletteRevealRecord(
            panelID: PanelContext.sample.id,
            rowCount: rowCount,
            showsEmptyMessage: showsEmptyMessage,
            initialRows: initialRows
        )

        #expect(PalettePresenterDiagnostic.revealed(record).logMessage == expected)
    }

    @Test("閉じる・候補の差し替え・引き直しの文言")
    func otherMessages() {
        let refresh = PaletteRowsRefreshRecord(
            panelID: PanelContext.sample.id,
            trigger: .candidatesChanged,
            rowCount: 7,
            lastUsedRowCount: 0,
            isSelectionKept: false
        )

        #expect(PalettePresenterDiagnostic.hidden(panelID: PanelContext.sample.id, wasVisible: true).logMessage
            == "palette hidden (id: panel-1, wasVisible: true)")
        #expect(PalettePresenterDiagnostic.candidatesChanged(panelID: PanelContext.sample.id, isBuildingCandidates: true).logMessage
            == "palette candidates changed (presented: true, id: panel-1, building: true)")
        #expect(PalettePresenterDiagnostic.candidatesChanged(panelID: nil, isBuildingCandidates: false).logMessage
            == "palette candidates changed (presented: false, building: false)")
        #expect(PalettePresenterDiagnostic.rowsRefreshed(refresh).logMessage
            == "palette rows refreshed (id: panel-1, trigger: candidatesChanged, rows: 7, lastUsedRows: 0, selectionKept: false)")
    }

    @Test("報告の文言は、候補のパス・名前と検索語を含まず、ログを読むスクリプトの目印も含まない")
    func messagesDoNotContainPathsOrQuery() async {
        let query = "secret-query"
        presenter.candidateRebuildingDidChange(true)
        await show(.sample, answering: Self.usedRows("history-only", "fern"))
        viewModel.query = query
        await answerSearch(1, with: Self.usedRows("fern"))
        presenter.candidatesDidChange()
        await answerSearch(2, with: PaletteRowFixtures.rows("fern-docs"))
        presenter.candidateRebuildingDidChange(false)
        await answerSearch(3, with: PaletteRowFixtures.rows("openpath"))
        presenter.hide()

        let messages = recorder.diagnostics.map(\.logMessage)
        #expect(messages.count >= 5)
        #expect(messages.allSatisfy(DiagnosticLogContract.isSafe))
        #expect(messages.allSatisfy { message in
            !message.contains(query) && !["history-only", "fern", "openpath", "example"].contains { message.contains($0) }
        })
    }
}
