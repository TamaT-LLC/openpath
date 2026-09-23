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

    @Test(
        "パネルの確定ボタンを、DSN-001 §2.2 のタイトルで見つける",
        arguments: ["開く", "Open", "選択", "Choose", "追加", "Add"]
    )
    func findsConfirmButton(title: String) throws {
        let panel = FakeAXElement.dialog(Self.panelContents(confirmTitle: title))

        #expect(try FakeAXSearch.openButton(in: panel)?.name == "confirm")
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

        #expect(try FakeAXSearch.openButton(in: hostDialog)?.name == "confirm")
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

        #expect(try FakeAXSearch.openButton(in: hostWindow)?.name == "confirm")
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let panel = FakeAXElement.dialog(Self.panelContents(confirmTitle: "開く"))
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
