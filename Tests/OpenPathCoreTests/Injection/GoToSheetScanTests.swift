import os
import Testing

import OpenPathCore

@Suite("GoToSheetScan: 移動先シートの出現判定")
struct GoToSheetScanTests {
    /// AX ツリーの代わりに使う要素。
    private struct Element {
        let name: String
        let role: String?
        var placeholder: String?
        var children: [Element] = []

        static func window(_ children: [Element]) -> Element {
            Element(name: "window", role: "AXWindow", children: children)
        }

        static func sheet(_ name: String, _ children: [Element] = []) -> Element {
            Element(name: name, role: "AXSheet", children: children)
        }

        static func textField(_ name: String, placeholder: String?) -> Element {
            Element(name: name, role: "AXTextField", placeholder: placeholder)
        }

        static func button(_ name: String) -> Element {
            Element(name: name, role: "AXButton")
        }
    }

    /// 子の取得を要求された要素の名前を記録しながら集計する。
    private static func scan(_ root: Element, visited: inout [String]) throws -> GoToSheetScan {
        try GoToSheetScan.scan(
            from: root,
            role: { $0.role },
            children: { element in
                visited.append(element.name)
                return element.children
            },
            placeholder: { $0.placeholder }
        )
    }

    private static func scan(_ root: Element) throws -> GoToSheetScan {
        var visited: [String] = []
        return try scan(root, visited: &visited)
    }

    /// 通常の NSOpenPanel（独立したダイアログ）の ⌘⇧G 送出前のツリー。
    private static let panelBeforeGoTo = Element.window([
        .textField("search", placeholder: "検索"),
        Element(name: "sidebar", role: "AXScrollArea", children: [Element(name: "outline", role: "AXOutline")]),
        .button("open"),
    ])

    @Test("シートとパス入力欄を数える")
    func countsSheetsAndPathFields() throws {
        let window = Element.window([
            .sheet("go-to", [
                .textField("path", placeholder: "パスを入力"),
                .button("go"),
            ]),
            .textField("search", placeholder: "Search"),
        ])

        #expect(try Self.scan(window) == GoToSheetScan(sheetCount: 1, pathFieldCount: 1))
    }

    @Test("コンボボックスのパス入力欄も数える（旧来の移動先シート）")
    func countsComboBoxPathField() throws {
        let window = Element.window([
            Element(name: "combo", role: "AXComboBox", placeholder: "Go to the folder:"),
        ])

        #expect(try Self.scan(window).pathFieldCount == 1)
    }

    @Test("⌘⇧G でシートが増えたら出現とみなす")
    func detectsNewSheet() throws {
        let baseline = try Self.scan(Self.panelBeforeGoTo)
        let afterGoTo = try Self.scan(.window(Self.panelBeforeGoTo.children + [.sheet("go-to")]))

        #expect(afterGoTo.indicatesSheetShown(since: baseline))
    }

    @Test("シートでなくても、パス入力欄が増えたら出現とみなす")
    func detectsNewPathField() throws {
        let baseline = try Self.scan(Self.panelBeforeGoTo)
        let afterGoTo = try Self.scan(.window(Self.panelBeforeGoTo.children + [
            Element(name: "popover", role: "AXPopover", children: [.textField("path", placeholder: "Enter path")]),
        ]))

        #expect(afterGoTo.indicatesSheetShown(since: baseline))
    }

    @Test("パネル自体がシートの場合、⌘⇧G の前から存在するシートは出現とみなさない")
    func ignoresSheetThatExistedBeforeGoTo() throws {
        let panelAsSheet = Element.window([.sheet("open-panel", [.button("open")])])
        let baseline = try Self.scan(panelAsSheet)

        #expect(baseline.sheetCount == 1)
        #expect(try !Self.scan(panelAsSheet).indicatesSheetShown(since: baseline))
    }

    @Test("パネル自体がシートの場合も、その上に移動先シートが重なれば出現とみなす")
    func detectsGoToSheetOnPanelSheet() throws {
        let baseline = try Self.scan(.window([.sheet("open-panel", [.button("open")])]))
        let afterGoTo = try Self.scan(.window([.sheet("open-panel", [.button("open"), .sheet("go-to")])]))

        #expect(afterGoTo.indicatesSheetShown(since: baseline))
    }

    @Test("ファイル一覧など行の多い要素の中へは降りない（AX の往復を減らすため）")
    func doesNotDescendIntoFileLists() throws {
        let hiddenSheet = Element.sheet("inside-list")
        let window = Element.window([
            Element(name: "browser", role: "AXBrowser", children: [hiddenSheet]),
            Element(name: "outline", role: "AXOutline", children: [hiddenSheet]),
            Element(name: "table", role: "AXTable", children: [hiddenSheet]),
            Element(name: "list", role: "AXList", children: [hiddenSheet]),
            Element(name: "web", role: "AXWebArea", children: [hiddenSheet]),
            Element(name: "group", role: "AXGroup", children: [.sheet("inside-group")]),
        ])
        var visited: [String] = []

        let result = try Self.scan(window, visited: &visited)

        #expect(result.sheetCount == 1)
        #expect(!visited.contains { ["browser", "outline", "table", "list", "web"].contains($0) })
        #expect(visited.contains("group"))
    }

    /// このツリーの走査は、子・ロール・placeholder の読み取りを合わせて 11 回の AX 操作になる。
    /// 最後の操作より前のどの回数で打ち切り条件に達しても、次の操作の前で止まることを確かめる。
    @Test(
        "打ち切り条件に達したら、それ以降の AX 操作（子・ロール・placeholder の読み取り）をせずに打ち切る",
        arguments: 1...10
    )
    func stopsBeforeNextAXOperationWhenCutoffIsReached(operationLimit: Int) {
        let operationCount = OSAllocatedUnfairLock(initialState: 0)
        let countOperation = { operationCount.withLock { $0 += 1 } }
        let window = Element.window([
            .textField("a", placeholder: "パス"),
            .sheet("b", [.textField("c", placeholder: "Path")]),
            .button("d"),
        ])

        #expect(throws: ScanCutoff.Reached()) {
            try GoToSheetScan.scan(
                from: window,
                cutoff: ScanCutoff { operationCount.withLock { $0 >= operationLimit } },
                role: { element in
                    countOperation()
                    return element.role
                },
                children: { element in
                    countOperation()
                    return element.children
                },
                placeholder: { element in
                    countOperation()
                    return element.placeholder
                }
            )
        }
        #expect(operationCount.withLock { $0 } == operationLimit)
    }

    @Test(
        "placeholder に「パス」「Path」「Go to」を含む入力欄をパス入力欄とみなす（大文字小文字は区別しない）",
        arguments: [
            ("パスを入力", true),
            ("Enter a path", true),
            ("PATH", true),
            ("Go to the folder:", true),
            ("GO TO", true),
            ("検索", false),
            ("Search", false),
            ("", false),
        ]
    )
    func pathFieldPlaceholder(placeholder: String, expected: Bool) {
        #expect(GoToSheetScan.isPathFieldPlaceholder(placeholder) == expected)
    }

    @Test("placeholder の無い入力欄はパス入力欄とみなさない")
    func textFieldWithoutPlaceholderIsNotPathField() throws {
        let window = Element.window([.textField("name", placeholder: nil)])

        #expect(try Self.scan(window).pathFieldCount == 0)
    }
}
