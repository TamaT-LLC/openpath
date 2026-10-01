import Testing

import OpenPathCore

@Suite("GoToSheetIdentity: フォーカス中のウィンドウが移動先シートそのものか（Issue #95）")
struct GoToSheetIdentityTests {
    @Test("AXIdentifier が GoToWindow のシートは移動先シート（子は読まない）")
    func recognizesGoToSheetByIdentifier() throws {
        let counter = AXOperationCounter()

        #expect(try FakeAXSearch.isGoToSheet(.goToSheetWindow(), counter: counter))
        // ロールと AXIdentifier の 2 回だけ
        #expect(counter.value == 2)
    }

    @Test("AXIdentifier が違っても、移動先シートの入力欄（PathTextField）を子に持つシートは移動先シート")
    func recognizesGoToSheetByPathField() throws {
        let sheet = FakeAXElement(name: "sheet", role: "AXSheet", children: [
            FakeAXElement(name: "label", role: "AXStaticText"),
            .pathTextField("path"),
        ])

        #expect(try FakeAXSearch.isGoToSheet(sheet))
    }

    @Test("シートとして付いたパネル自体（移動先シートの入力欄を直接持たない）は移動先シートでない")
    func panelSheetIsNotGoToSheet() throws {
        let panelSheet = FakeAXElement.panelSheet([
            .searchField("search"),
            .group("buttons", [.button("confirm", title: "開く")]),
            .modernGoToSheet(),
        ])

        #expect(try !FakeAXSearch.isGoToSheet(panelSheet))
    }

    @Test("シートでないウィンドウは、移動先シートの入力欄を持っていても移動先シートでない（子は読まない）")
    func windowIsNotGoToSheet() throws {
        let counter = AXOperationCounter()
        let window = FakeAXElement.dialog([.pathTextField("path")])

        #expect(try !FakeAXSearch.isGoToSheet(window, counter: counter))
        #expect(counter.value == 1)
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let sheet = FakeAXElement(name: "sheet", role: "AXSheet", children: [
            FakeAXElement(name: "label", role: "AXStaticText"),
            .pathTextField("path"),
        ])
        let fullScan = AXOperationCounter()
        #expect(try FakeAXSearch.isGoToSheet(sheet, counter: fullScan))

        for limit in 0..<fullScan.value {
            let counter = AXOperationCounter()
            #expect(throws: ScanCutoff.Reached.self) {
                try FakeAXSearch.isGoToSheet(sheet, counter: counter, cutoff: counter.cutoff(afterOperations: limit))
            }
            #expect(counter.value == limit, "\(limit) 回目で打ち切った後に AX 操作をしている")
        }
    }
}
