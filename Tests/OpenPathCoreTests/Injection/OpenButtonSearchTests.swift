import Testing

import OpenPathCore

@Suite("OpenButtonSearch: auto_confirm で押すパネルの「開く」ボタンを探す（DSN-001 §3.1 ステップ 8）")
struct OpenButtonSearchTests {
    private static func panelContents(confirmTitle: String) -> [FakeAXElement] {
        [
            .searchField("search"),
            .outline("files", [.button("row", title: confirmTitle)]),
            .group("buttons", [
                .button("new-folder", title: "新規フォルダ"),
                .button("cancel", title: "キャンセル"),
                .button("confirm", title: confirmTitle),
            ]),
        ]
    }

    /// 独自の表題の確定ボタンを持ち、既定ボタン（AXDefaultButton）がそれを指すパネルの中身。
    private static func customTitledContents(confirmTitle: String) -> [FakeAXElement] {
        [
            .searchField("search"),
            .group("buttons", [
                .button("new-folder", title: "新規フォルダ"),
                .button("cancel", title: "キャンセル"),
                .button("confirm", title: confirmTitle),
            ]),
        ]
    }

    private static func withDefaultButton(_ element: FakeAXElement, _ name: String?) -> FakeAXElement {
        var element = element
        element.defaultButtonName = name
        return element
    }

    @Test(
        "パネルの確定ボタンを、パネル判定（DSN-001 §2.2）と同じ表題で見つける",
        arguments: ["開く", "Open", "選択", "Choose", "追加", "Add", "アップロード", "Upload"]
    )
    func findsConfirmButton(title: String) throws {
        let panel = FakeAXElement.dialog(Self.panelContents(confirmTitle: title))

        let match = try #require(try FakeAXSearch.openButton(in: panel))

        #expect(match.button.name == "confirm")
        #expect(match.identification == .title)
    }

    @Test("表題の前後の空白は無視する（パネル判定と同じ）")
    func ignoresSurroundingWhitespaceInTitle() throws {
        let panel = FakeAXElement.dialog(Self.panelContents(confirmTitle: " 開く "))

        #expect(try FakeAXSearch.openButton(in: panel)?.button.name == "confirm")
    }

    @Test("確定ボタンが無ければ nil（キャンセルや新規フォルダは押さない）")
    func returnsNilWithoutConfirmButton() throws {
        let panel = FakeAXElement.dialog([
            .button("new-folder", title: "新規フォルダ"),
            .button("cancel", title: "Cancel"),
        ])

        #expect(try FakeAXSearch.openButton(in: panel) == nil)
    }

    @Test("シートとして付いたパネルのボタンを、シートの外のボタンより優先する")
    func prefersButtonInsideSheet() throws {
        let hostDialog = FakeAXElement.dialog([
            .button("host-add", title: "追加"),
            .sheet("open-panel", Self.panelContents(confirmTitle: "開く")),
        ])

        #expect(try FakeAXSearch.openButton(in: hostDialog)?.button.name == "confirm")
    }

    @Test("通常のウィンドウでは、シートの外の確定ボタンを押さない（パネルが閉じた後にホストアプリのボタンを押さないため）")
    func ignoresButtonOutsideSheetsInStandardWindow() throws {
        let hostWindow = FakeAXElement.standardWindow([.button("host-add", title: "Add")])

        #expect(try FakeAXSearch.openButton(in: hostWindow) == nil)
    }

    @Test("通常のウィンドウでも、シートとして付いたパネルの確定ボタンは見つける（サンドボックスアプリのパネル）")
    func findsButtonInPanelSheetOfStandardWindow() throws {
        let hostWindow = FakeAXElement.standardWindow([
            .button("host-add", title: "Add"),
            .sheet("open-panel", Self.panelContents(confirmTitle: "Open")),
        ])

        #expect(try FakeAXSearch.openButton(in: hostWindow)?.button.name == "confirm")
    }

    // MARK: - 起点がパネルそのもの（Issue #89）

    @Test("フォーカス中のウィンドウがシート型のパネル自体（ロール AXSheet・サブロール無し）でも、その確定ボタンを見つける（Issue #89）")
    func findsButtonWhenRootIsPanelSheet() throws {
        let panelSheet = FakeAXElement.panelSheet(Self.panelContents(confirmTitle: "開く"))

        #expect(try FakeAXSearch.openButton(in: panelSheet)?.button.name == "confirm")
    }

    @Test("フォーカス中のウィンドウが非モーダルのパネル（AXStandardWindow・AXIdentifier open-panel）でも、その確定ボタンを見つける（Issue #89）")
    func findsButtonWhenRootIsNonModalPanel() throws {
        let panel = FakeAXElement.nonModalPanel(Self.panelContents(confirmTitle: "Open"))

        #expect(try FakeAXSearch.openButton(in: panel)?.button.name == "confirm")
    }

    @Test("シート型のパネルの上に、閉じかけの移動先シートが残っていても、パネルの確定ボタンを見つける")
    func findsButtonWhileGoToSheetIsClosing() throws {
        let panelSheet = FakeAXElement.panelSheet(
            Self.panelContents(confirmTitle: "開く") + [.modernGoToSheet()]
        )

        #expect(try FakeAXSearch.openButton(in: panelSheet)?.button.name == "confirm")
    }

    // MARK: - 既定ボタン（Issue #89）

    @Test(
        "表題が一覧に無くても、パネルの既定ボタン（AXDefaultButton）を確定ボタンとして見つける（Issue #89）",
        arguments: ["読み込む", "フォルダーを開く", "Open Folder"]
    )
    func findsDefaultButtonWithCustomTitle(title: String) throws {
        let panel = Self.withDefaultButton(.dialog(Self.customTitledContents(confirmTitle: title)), "confirm")

        let match = try #require(try FakeAXSearch.openButton(in: panel))

        #expect(match.button.name == "confirm")
        #expect(match.identification == .defaultButton)
    }

    @Test("シート型・非モーダルのパネルでも、既定ボタンで見つける")
    func findsDefaultButtonOfPanelRoots() throws {
        let panelSheet = Self.withDefaultButton(.panelSheet(Self.customTitledContents(confirmTitle: "読み込む")), "confirm")
        let nonModal = Self.withDefaultButton(.nonModalPanel(Self.customTitledContents(confirmTitle: "読み込む")), "confirm")

        #expect(try FakeAXSearch.openButton(in: panelSheet)?.identification == .defaultButton)
        #expect(try FakeAXSearch.openButton(in: nonModal)?.identification == .defaultButton)
    }

    @Test("表題で見つかれば、既定ボタンより表題を使う")
    func prefersTitleOverDefaultButton() throws {
        let panel = Self.withDefaultButton(.dialog(Self.panelContents(confirmTitle: "開く")), "confirm")

        let match = try #require(try FakeAXSearch.openButton(in: panel))

        #expect(match.button.name == "confirm")
        #expect(match.identification == .title)
    }

    @Test(
        "既定ボタンが確定ボタンでない表題（キャンセル・新規フォルダ・移動先シートの「移動」）なら押さない",
        arguments: ["キャンセル", "Cancel", "新規フォルダ", "New Folder", "移動", "Go"]
    )
    func ignoresNonConfirmDefaultButton(title: String) throws {
        let panel = Self.withDefaultButton(.dialog([
            .button("other", title: title),
            .button("custom", title: "読み込む"),
        ]), "other")

        #expect(try FakeAXSearch.openButton(in: panel) == nil)
    }

    @Test("パネルでない通常のウィンドウの既定ボタンは押さない（ホストアプリのボタンを押さないため）")
    func ignoresDefaultButtonOfStandardWindow() throws {
        let hostWindow = Self.withDefaultButton(.standardWindow([.button("host-ok", title: "OK")]), "host-ok")

        #expect(try FakeAXSearch.openButton(in: hostWindow) == nil)
    }

    @Test("シートとして付いたパネルの既定ボタンを、シートの外（ホスト側）の表題より優先する")
    func prefersDefaultButtonInSheetOverHostTitle() throws {
        let hostDialog = FakeAXElement.dialog([
            .button("host-add", title: "追加"),
            Self.withDefaultButton(.sheet("open-panel", Self.customTitledContents(confirmTitle: "読み込む")), "confirm"),
        ])

        let match = try #require(try FakeAXSearch.openButton(in: hostDialog))

        #expect(match.button.name == "confirm")
        #expect(match.identification == .defaultButton)
    }

    @Test("閉じかけの移動先シートの既定ボタン（旧来の「移動」）ではなく、パネルの既定ボタンを使う")
    func ignoresGoButtonOfClosingGoToSheet() throws {
        let classicGoToSheet = Self.withDefaultButton(.sheet("go-to", [
            .comboBox("path"),
            .button("go", title: "移動"),
        ]), "go")
        let panel = Self.withDefaultButton(
            .dialog(Self.customTitledContents(confirmTitle: "読み込む") + [classicGoToSheet]),
            "confirm"
        )

        #expect(try FakeAXSearch.openButton(in: panel)?.button.name == "confirm")
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let panels = [
            FakeAXElement.dialog(Self.panelContents(confirmTitle: "開く")),
            Self.withDefaultButton(.nonModalPanel(Self.customTitledContents(confirmTitle: "読み込む")), "confirm"),
        ]
        for panel in panels {
            let fullScan = AXOperationCounter()
            #expect(try FakeAXSearch.openButton(in: panel, counter: fullScan) != nil)

            for limit in 0..<fullScan.value {
                let counter = AXOperationCounter()
                #expect(throws: ScanCutoff.Reached.self) {
                    try FakeAXSearch.openButton(in: panel, counter: counter, cutoff: counter.cutoff(afterOperations: limit))
                }
                #expect(counter.value == limit, "\(limit) 回目で打ち切った後に AX 操作をしている")
            }
        }
    }
}
