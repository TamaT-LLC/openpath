import Testing

import OpenPathCore

@MainActor
@Suite("PaletteViewModel")
struct PaletteViewModelTests {
    private static let home = "/Users/example"

    private static func makeRows(_ names: String...) -> [PaletteRow] {
        names.map { PaletteRow(name: $0, path: "\(home)/repos/\($0)", lastUsed: nil) }
    }

    private let viewModel = PaletteViewModel(homeDirectory: PaletteViewModelTests.home)

    // MARK: - 初期状態

    @Test("初期状態は空の検索語・候補なし・未選択・ヒント表示")
    func initialState() {
        #expect(viewModel.query.isEmpty)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.selectedIndex == nil)
        #expect(viewModel.selectedRow == nil)
        #expect(viewModel.isLocked == false)
        #expect(viewModel.footer == .keyHints)
        #expect(viewModel.homeDirectory == Self.home)
    }

    // MARK: - 候補の差し替え

    @Test("候補を差し替えると先頭を選択する")
    func replacingRowsSelectsFirstRow() {
        let rows = Self.makeRows("fern", "fern-docs")

        viewModel.replaceRows(rows)

        #expect(viewModel.rows == rows)
        #expect(viewModel.selectedIndex == 0)
        #expect(viewModel.selectedRow == rows[0])
    }

    @Test("候補が 0 件になると未選択になる")
    func replacingWithEmptyRowsClearsSelection() {
        viewModel.replaceRows(Self.makeRows("fern"))

        viewModel.replaceRows([])

        #expect(viewModel.selectedIndex == nil)
        #expect(viewModel.selectedRow == nil)
    }

    @Test("既定では差し替えのたびに先頭へ戻す（検索語の変更を想定）")
    func replacingRowsResetsSelectionByDefault() {
        viewModel.replaceRows(Self.makeRows("a", "b", "c"))
        viewModel.moveSelection(by: 2)

        viewModel.replaceRows(Self.makeRows("a", "b", "c"))

        #expect(viewModel.selectedIndex == 0)
    }

    @Test("keepingSelection なら同じ候補の選択を保つ（候補ソースの再構築を想定）")
    func replacingRowsCanKeepSelection() {
        viewModel.replaceRows(Self.makeRows("a", "b", "c"))
        viewModel.moveSelection(by: 1)

        viewModel.replaceRows(Self.makeRows("new", "a", "b", "c"), keepingSelection: true)

        #expect(viewModel.selectedRow?.name == "b")
        #expect(viewModel.selectedIndex == 2)
    }

    @Test("keepingSelection でも選択中の候補が消えたら先頭を選択する")
    func keepingSelectionFallsBackToFirstRow() {
        viewModel.replaceRows(Self.makeRows("a", "b"))
        viewModel.moveSelection(by: 1)

        viewModel.replaceRows(Self.makeRows("x", "y"), keepingSelection: true)

        #expect(viewModel.selectedIndex == 0)
    }

    @Test("候補があれば 0 件の案内は出さない")
    func emptyMessageIsShownOnlyWithoutRows() {
        #expect(viewModel.emptyMessage == PaletteText.noMatches)

        viewModel.replaceRows(Self.makeRows("fern"))

        #expect(viewModel.emptyMessage == nil)
    }

    // MARK: - 選択の移動

    @Test("選択は ±offset だけ移動し、先頭と末尾で止まる（循環しない）")
    func moveSelectionIsClamped() {
        viewModel.replaceRows(Self.makeRows("a", "b", "c"))

        viewModel.moveSelection(by: 1)
        #expect(viewModel.selectedIndex == 1)

        viewModel.moveSelection(by: 5)
        #expect(viewModel.selectedIndex == 2)

        viewModel.moveSelection(by: -1)
        #expect(viewModel.selectedIndex == 1)

        viewModel.moveSelection(by: -5)
        #expect(viewModel.selectedIndex == 0)
    }

    @Test("候補がなければ選択の移動は何もしない")
    func moveSelectionWithoutRowsDoesNothing() {
        viewModel.moveSelection(by: 1)

        #expect(viewModel.selectedIndex == nil)
    }

    @Test("範囲内の添字を直接選択でき、範囲外は無視する")
    func selectAtIndex() {
        viewModel.replaceRows(Self.makeRows("a", "b", "c"))

        viewModel.select(at: 2)
        #expect(viewModel.selectedIndex == 2)

        viewModel.select(at: 3)
        viewModel.select(at: -1)
        #expect(viewModel.selectedIndex == 2)
    }

    @Test("ロック中（注入中）は選択を変えない")
    func selectionIsFrozenWhileLocked() {
        viewModel.replaceRows(Self.makeRows("a", "b", "c"))
        viewModel.setLocked(true)

        viewModel.moveSelection(by: 1)
        viewModel.select(at: 2)

        #expect(viewModel.isLocked)
        #expect(viewModel.selectedIndex == 0)

        viewModel.setLocked(false)
        viewModel.moveSelection(by: 1)

        #expect(viewModel.selectedIndex == 1)
    }

    // MARK: - フッター

    @Test("候補ソースの構築中はフッターに「候補を構築中…」を出す")
    func footerShowsBuildingState() {
        viewModel.setBuildingCandidates(true)

        #expect(viewModel.footer == .status(PaletteText.buildingCandidates))

        viewModel.setBuildingCandidates(false)

        #expect(viewModel.footer == .keyHints)
    }

    @Test("状態表示とエラーは後から出したものに置き換わり、構築中より優先する")
    func statusAndErrorReplaceEachOther() {
        viewModel.setBuildingCandidates(true)

        viewModel.showStatus(PaletteMessage.injecting)
        #expect(viewModel.status == .info(PaletteMessage.injecting))
        #expect(viewModel.footer == .status(PaletteMessage.injecting))

        viewModel.showError(PaletteMessage.injectionFailed)
        #expect(viewModel.status == .error(PaletteMessage.injectionFailed))
        #expect(viewModel.footer == .error(PaletteMessage.injectionFailed))

        viewModel.clearStatus()
        #expect(viewModel.status == nil)
        #expect(viewModel.footer == .status(PaletteText.buildingCandidates))
    }

    // MARK: - リセット

    @Test("リセットで検索語・候補・選択・状態表示・ロックを初期状態に戻し、構築中の状態は保つ")
    func resetRestoresSessionState() {
        viewModel.query = "fern"
        viewModel.replaceRows(Self.makeRows("fern"))
        viewModel.setLocked(true)
        viewModel.setBuildingCandidates(true)
        viewModel.showError(PaletteMessage.injectionFailed)

        viewModel.reset()

        #expect(viewModel.query.isEmpty)
        #expect(viewModel.rows.isEmpty)
        #expect(viewModel.selectedIndex == nil)
        #expect(viewModel.status == nil)
        #expect(viewModel.isLocked == false)
        #expect(viewModel.isBuildingCandidates)
    }

    // MARK: - 文言

    @Test("キーヒントは UX-001 §3 のフッターの文言どおり")
    func keyHintsFollowUXDesign() {
        let footerText = PaletteText.keyHints.map { "\($0.key) \($0.action)" }.joined(separator: "  ")

        #expect(footerText == "↑↓ 選択  ⏎ 移動  ⌘⏎ 移動して開く  esc 閉じる")
    }

    @Test("状態表示の文言は UX-001 §5 のとおり")
    func statusTextsFollowUXDesign() {
        #expect(PaletteText.buildingCandidates == "候補を構築中…")
        #expect(PaletteText.noMatches == "一致する候補がありません。~/ や / で始まるパスも入力できます")
    }
}
