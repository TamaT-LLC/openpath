import Testing

import OpenPathCore

@Suite("GoToSuggestionSearch: 移動先シートの候補リストで選ばれている候補のパスを読む（Issue #74）")
struct GoToSuggestionSearchTests {
    @Test("候補の行（AXRow > AXCell > AXList）の AXList の AXIdentifier をパスとして返す")
    func readsPathFromSuggestionRow() throws {
        let row = FakeAXElement.suggestionRow("/Users/me/Library")

        #expect(try FakeAXSearch.suggestionPath(inSelectedRow: row) == "/Users/me/Library")
    }

    @Test("見出しの行（「Go to:」）はパスを持たないため nil")
    func headerRowHasNoPath() throws {
        #expect(try FakeAXSearch.suggestionPath(inSelectedRow: .suggestionHeaderRow) == nil)
    }

    @Test("AXList の AXIdentifier がパス（/ で始まる）でなければ nil")
    func ignoresNonPathIdentifier() throws {
        let row = FakeAXElement(name: "row", role: "AXRow", children: [
            FakeAXElement(name: "cell", role: "AXCell", children: [
                FakeAXElement(name: "list", role: "AXList", identifier: "_NS:120"),
            ]),
        ])

        #expect(try FakeAXSearch.suggestionPath(inSelectedRow: row) == nil)
    }

    @Test("行から 3 階層より深い AXList は探さない")
    func doesNotSearchTooDeep() throws {
        let deepList = FakeAXElement(name: "list", role: "AXList", identifier: "/Users/me/Library")
        let row = FakeAXElement(name: "row", role: "AXRow", children: [
            .group("g1", [.group("g2", [.group("g3", [deepList])])]),
        ])

        #expect(try FakeAXSearch.suggestionPath(inSelectedRow: row) == nil)
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let row = FakeAXElement.suggestionRow("/Users/me/Library")
        let fullScan = AXOperationCounter()
        #expect(try FakeAXSearch.suggestionPath(inSelectedRow: row, counter: fullScan) != nil)

        for limit in 0..<fullScan.value {
            let counter = AXOperationCounter()
            #expect(throws: ScanCutoff.Reached.self) {
                try FakeAXSearch.suggestionPath(inSelectedRow: row, counter: counter, cutoff: counter.cutoff(afterOperations: limit))
            }
            #expect(counter.value == limit, "\(limit) 回目で打ち切った後に AX 操作をしている")
        }
    }
}

@Suite("PanelLocationSearch: パネルが表示している現在地（フォルダの表示名）を読む（Issue #74 の診断ログ）")
struct PanelLocationSearchTests {
    @Test("場所のポップアップ（AXIdentifier `where popup`）の値を返す")
    func readsLocationPopUpValue() throws {
        let panel = FakeAXElement.standardWindow([
            .group("split", [
                FakeAXElement(name: "other-popup", role: "AXPopUpButton", identifier: "view popup", value: "リスト"),
                .locationPopUp("Library"),
            ]),
        ])

        #expect(try FakeAXSearch.displayedFolderName(in: panel) == "Library")
    }

    @Test("パネルがシートとして付いたウィンドウでも、シートの中の場所のポップアップを読む")
    func readsLocationInPanelSheet() throws {
        let hostWindow = FakeAXElement.standardWindow([
            .sheet("open-panel", [.group("split", [.locationPopUp("ライブラリ")])]),
        ])

        #expect(try FakeAXSearch.displayedFolderName(in: hostWindow) == "ライブラリ")
    }

    @Test("場所のポップアップが無ければ nil")
    func returnsNilWithoutLocationPopUp() throws {
        let panel = FakeAXElement.dialog([.button("open", title: "開く")])

        #expect(try FakeAXSearch.displayedFolderName(in: panel) == nil)
    }

    @Test("打ち切り条件に達したら、それ以降の AX 操作をせずに ScanCutoff.Reached を投げる（何回目の操作の前でも）")
    func stopsBeforeNextAXOperationWhenCutOff() throws {
        let panel = FakeAXElement.dialog([.group("split", [.locationPopUp("Library")])])
        let fullScan = AXOperationCounter()
        #expect(try FakeAXSearch.displayedFolderName(in: panel, counter: fullScan) != nil)

        for limit in 0..<fullScan.value {
            let counter = AXOperationCounter()
            #expect(throws: ScanCutoff.Reached.self) {
                try FakeAXSearch.displayedFolderName(in: panel, counter: counter, cutoff: counter.cutoff(afterOperations: limit))
            }
            #expect(counter.value == limit, "\(limit) 回目で打ち切った後に AX 操作をしている")
        }
    }
}
