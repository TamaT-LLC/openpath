import Testing

import OpenPathCore

@MainActor
@Suite("PaletteViewModel: キー操作の適用")
struct PaletteViewModelKeyActionTests {
    private static let home = "/Users/example"
    private static let isDirectory: (String) -> Bool = { _ in true }
    private static let isFile: (String) -> Bool = { _ in false }

    private static func makeRows(_ names: String...) -> [PaletteRow] {
        names.map { PaletteRow(name: $0, path: "\(home)/repos/\($0)", lastUsed: nil) }
    }

    private let viewModel = PaletteViewModel(homeDirectory: PaletteViewModelKeyActionTests.home)

    private func perform(_ action: PaletteAction, isDirectory: (String) -> Bool = isDirectory) -> PaletteEvent? {
        viewModel.perform(action, isDirectory: isDirectory)
    }

    // MARK: - 選択の移動

    @Test("選択の移動を適用し、外へのイベントは出さない")
    func moveSelection() {
        viewModel.replaceRows(Self.makeRows("a", "b", "c"))

        #expect(perform(.moveSelection(by: 1)) == nil)
        #expect(viewModel.selectedIndex == 1)

        #expect(perform(.moveSelection(by: -1)) == nil)
        #expect(viewModel.selectedIndex == 0)
    }

    // MARK: - 確定

    @Test("確定は選択中の候補のパスで確定イベントを返す", arguments: [false, true])
    func confirmUsesSelectedRow(openImmediately: Bool) {
        viewModel.replaceRows(Self.makeRows("fern", "fern-docs"))
        viewModel.moveSelection(by: 1)

        let event = perform(.confirm(openImmediately: openImmediately))

        #expect(event == .confirm(path: "\(Self.home)/repos/fern-docs", openImmediately: openImmediately))
    }

    @Test("候補がなければ確定しない")
    func confirmWithoutRowsDoesNothing() {
        #expect(perform(.confirm(openImmediately: false)) == nil)
    }

    // MARK: - 閉じる

    @Test("閉じる操作は閉じるイベントを返し、検索語や候補は保つ（ホットキーでの再表示に備える）")
    func dismissKeepsState() {
        viewModel.query = "fern"
        viewModel.replaceRows(Self.makeRows("fern"))

        #expect(perform(.dismiss) == .dismiss)
        #expect(viewModel.query == "fern")
        #expect(viewModel.selectedIndex == 0)
    }

    // MARK: - 展開（Tab）

    @Test("展開はディレクトリなら末尾に / を付けたパスを検索語にする")
    func expandDirectory() {
        viewModel.query = "fe"
        viewModel.replaceRows(Self.makeRows("fern", "fern-docs"))
        viewModel.moveSelection(by: 1)

        #expect(perform(.expandSelection) == nil)
        #expect(viewModel.query == "\(Self.home)/repos/fern-docs/")
    }

    @Test("展開はファイルならパスをそのまま検索語にする")
    func expandFile() {
        viewModel.replaceRows([PaletteRow(name: "notes.md", path: "\(Self.home)/notes.md", lastUsed: nil)])

        _ = perform(.expandSelection, isDirectory: Self.isFile)

        #expect(viewModel.query == "\(Self.home)/notes.md")
    }

    @Test("展開は選択中の候補のパスでディレクトリかどうかを判定する")
    func expandChecksSelectedPath() {
        viewModel.replaceRows(Self.makeRows("fern"))
        var checkedPaths: [String] = []

        _ = perform(.expandSelection) { path in
            checkedPaths.append(path)
            return true
        }

        #expect(checkedPaths == ["\(Self.home)/repos/fern"])
    }

    @Test("候補がなければ展開しない")
    func expandWithoutRowsDoesNothing() {
        viewModel.query = "zzz"

        #expect(perform(.expandSelection) == nil)
        #expect(viewModel.query == "zzz")
    }

    // MARK: - ロック中

    @Test(
        "ロック中（注入中）はどの操作も適用しない",
        arguments: [
            PaletteAction.moveSelection(by: 1),
            .confirm(openImmediately: false),
            .confirm(openImmediately: true),
            .expandSelection,
            .dismiss,
        ]
    )
    func actionsAreIgnoredWhileLocked(action: PaletteAction) {
        viewModel.query = "fe"
        viewModel.replaceRows(Self.makeRows("fern", "fern-docs"))
        viewModel.setLocked(true)

        #expect(perform(action) == nil)
        #expect(viewModel.query == "fe")
        #expect(viewModel.selectedIndex == 0)
    }

    // MARK: - 検索語の変更通知

    @Test("検索語が変わると onQueryChange を呼び、同じ値の再設定では呼ばない")
    func queryChangeIsNotified() {
        var notified: [String] = []
        viewModel.onQueryChange = { notified.append($0) }

        viewModel.query = "f"
        viewModel.query = "fe"
        viewModel.query = "fe"

        #expect(notified == ["f", "fe"])
    }

    @Test("展開で検索語が変わったときも onQueryChange を呼ぶ")
    func expansionNotifiesQueryChange() {
        viewModel.replaceRows(Self.makeRows("fern"))
        var notified: [String] = []
        viewModel.onQueryChange = { notified.append($0) }

        _ = perform(.expandSelection)

        #expect(notified == ["\(Self.home)/repos/fern/"])
    }

    @Test("リセットで検索語が空に戻るときも onQueryChange を呼ぶ")
    func resetNotifiesQueryChange() {
        viewModel.query = "fern"
        var notified: [String] = []
        viewModel.onQueryChange = { notified.append($0) }

        viewModel.reset()

        #expect(notified == [""])
    }

    @Test("リセットの通知は他の状態を戻した後に呼び、通知の中で入れ直した候補を消さない")
    func resetNotifiesAfterClearingState() {
        viewModel.query = "fern"
        viewModel.replaceRows(Self.makeRows("fern"))
        viewModel.setLocked(true)
        viewModel.showError(PaletteMessage.injectionFailed)
        var isLockedAtNotification: Bool?
        var statusAtNotification: PaletteStatus?
        viewModel.onQueryChange = { [viewModel] _ in
            isLockedAtNotification = viewModel.isLocked
            statusAtNotification = viewModel.status
            viewModel.replaceRows(Self.makeRows("a", "b"))
        }

        viewModel.reset()

        #expect(isLockedAtNotification == false)
        #expect(statusAtNotification == nil)
        #expect(viewModel.rows.map(\.name) == ["a", "b"])
        #expect(viewModel.selectedIndex == 0)
    }
}
