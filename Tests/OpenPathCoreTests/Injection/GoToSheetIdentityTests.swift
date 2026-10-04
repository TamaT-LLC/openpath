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

/// 同じアプリが 2 つのパネルを開き、どちらにも移動先シートが付いている AX ツリー。注入先はパネル A。
private enum TwoPanels {
    static let goToSheetA = goToSheet("go-to-a")
    static let goToSheetB = goToSheet("go-to-b")
    /// パネル A に付いた、移動先シートでないシート（「新規フォルダ」等）。
    static let otherSheetA = FakeAXElement(name: "new-folder-a", role: "AXSheet", children: [.textField("name-a")])
    static let panelA = panel("panel-a", [goToSheetA, otherSheetA])
    static let panelB = panel("panel-b", [goToSheetB])
    static let application = FakeAXElement.group("application", [panelA, panelB])

    static func goToSheet(_ name: String) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXSheet", identifier: "GoToWindow", children: [.pathTextField("path \(name)")])
    }

    static func panel(_ name: String, _ sheets: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXWindow", subrole: "AXDialog", children: [.group("content \(name)", [])] + sheets)
    }
}

@Suite("GoToSheetIdentity: フォーカス中のウィンドウが、注入先のウィンドウに付いた移動先シートか（PR #118 のレビュー）")
struct GoToSheetAttachmentTests {
    @Test("注入先のパネルに付いた移動先シートなら true（自分のパネルのシートには Return を送る）")
    func acceptsGoToSheetOfTargetPanel() throws {
        #expect(try FakeAXSearch.isGoToSheet(TwoPanels.goToSheetA, attachedTo: TwoPanels.panelA, in: TwoPanels.application))
    }

    @Test("同じアプリの別のパネルに付いた移動先シートなら false（別のパネルのシートには Return を送らない）")
    func rejectsGoToSheetOfAnotherPanel() throws {
        #expect(try !FakeAXSearch.isGoToSheet(TwoPanels.goToSheetB, attachedTo: TwoPanels.panelA, in: TwoPanels.application))
    }

    @Test("注入先として移動先シートそのものを記録していた（付いたパネルをたどれなかった）なら、親を読まずに true")
    func acceptsTargetThatIsGoToSheetItself() throws {
        let counter = AXOperationCounter()

        #expect(try FakeAXSearch.isGoToSheet(TwoPanels.goToSheetA, attachedTo: TwoPanels.goToSheetA, in: TwoPanels.application, counter: counter))
        // ロールと AXIdentifier の 2 回だけ（親は読まない）
        #expect(counter.value == 2)
    }

    @Test("注入先のパネルに付いていても、移動先シートでないシートなら false")
    func rejectsOtherSheetOfTargetPanel() throws {
        #expect(try !FakeAXSearch.isGoToSheet(TwoPanels.otherSheetA, attachedTo: TwoPanels.panelA, in: TwoPanels.application))
    }

    @Test("付いたパネルを読めない（AXParent が無い）なら、確かめられないため false（誤った相手に Return を送らない）")
    func rejectsWhenParentIsUnavailable() throws {
        let detached = TwoPanels.goToSheet("go-to-detached")

        #expect(try !FakeAXSearch.isGoToSheet(detached, attachedTo: TwoPanels.panelA, in: TwoPanels.application))
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let fullScan = AXOperationCounter()
        #expect(try FakeAXSearch.isGoToSheet(TwoPanels.goToSheetA, attachedTo: TwoPanels.panelA, in: TwoPanels.application, counter: fullScan))

        for limit in 0..<fullScan.value {
            let counter = AXOperationCounter()
            #expect(throws: ScanCutoff.Reached.self) {
                try FakeAXSearch.isGoToSheet(
                    TwoPanels.goToSheetA,
                    attachedTo: TwoPanels.panelA,
                    in: TwoPanels.application,
                    counter: counter,
                    cutoff: counter.cutoff(afterOperations: limit)
                )
            }
            #expect(counter.value == limit, "\(limit) 回目で打ち切った後に AX 操作をしている")
        }
    }
}

@Suite("InjectionWindowRelation: フォーカス中のウィンドウが、注入先のウィンドウそのものか、それに付いたシートか")
struct InjectionWindowRelationTests {
    private static func isTargetOrAttached(_ window: FakeAXElement, to target: FakeAXElement) throws -> Bool {
        try InjectionWindowRelation.isTargetOrAttached(
            window,
            to: target,
            isSameElement: { $0.name == $1.name },
            parent: { TwoPanels.application.parent(of: $0) }
        )
    }

    @Test(
        "注入先そのもの・注入先に付いたシートは true、別のパネル・そのシートは false（注入先の確認と移動先シートの確認で同じ対応づけを使う）",
        arguments: [
            (TwoPanels.panelA, true),
            (TwoPanels.goToSheetA, true),
            (TwoPanels.otherSheetA, true),
            (TwoPanels.panelB, false),
            (TwoPanels.goToSheetB, false),
        ]
    )
    func relatesWindowToTarget(window: FakeAXElement, expected: Bool) throws {
        #expect(try Self.isTargetOrAttached(window, to: TwoPanels.panelA) == expected)
    }
}
