import os

import OpenPathCore

/// パネル内の要素探し（GoToFieldSearch / OpenButtonSearch）のテストで、AX ツリーの代わりに使う要素。
struct FakeAXElement: Equatable, Sendable {
    let name: String
    let role: String?
    var subrole: String?
    var title: String?
    var placeholder: String?
    var identifier: String?
    var value: String?
    var children: [FakeAXElement] = []

    /// 独立したダイアログとして表示された NSOpenPanel（DSN-001 §2.2）。
    static func dialog(_ children: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: "dialog", role: "AXWindow", subrole: "AXDialog", children: children)
    }

    /// ホストアプリの通常のウィンドウ（パネルはシートとして子に付く）。
    static func standardWindow(_ children: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: "window", role: "AXWindow", subrole: "AXStandardWindow", children: children)
    }

    static func sheet(_ name: String, _ children: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXSheet", children: children)
    }

    static func group(_ name: String, _ children: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXGroup", children: children)
    }

    static func textField(_ name: String, placeholder: String? = nil) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXTextField", placeholder: placeholder)
    }

    /// 旧来の移動先シートの入力欄。
    static func comboBox(_ name: String, placeholder: String? = nil) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXComboBox", placeholder: placeholder)
    }

    /// パネルのツールバーの検索フィールド。
    static func searchField(_ name: String) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXTextField", subrole: "AXSearchField", placeholder: "Search path")
    }

    static func button(_ name: String, title: String) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXButton", title: title)
    }

    /// ファイル一覧（行が大量にあるため中へは降りない要素）。
    static func outline(_ name: String, _ children: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXOutline", children: children)
    }

    /// macOS 13 以降の移動先シートの入力欄（placeholder が無く、AXIdentifier で見分ける。macOS 27 で確認）。
    static func pathTextField(_ name: String) -> FakeAXElement {
        FakeAXElement(name: name, role: "AXTextField", identifier: "PathTextField")
    }

    /// macOS 13 以降の移動先シート（入力欄・閉じるボタン・候補リスト。「移動」ボタンは無い）。
    static func modernGoToSheet(rows: [FakeAXElement] = []) -> FakeAXElement {
        .sheet("go-to", [
            FakeAXElement(name: "label", role: "AXStaticText"),
            FakeAXElement(name: "close", role: "AXButton", subrole: "AXCloseButton"),
            .pathTextField("path"),
            FakeAXElement(name: "scroll", role: "AXScrollArea", children: [.suggestionTable(rows)]),
        ])
    }

    /// 移動先シートの候補リスト。
    static func suggestionTable(_ rows: [FakeAXElement]) -> FakeAXElement {
        FakeAXElement(name: "suggestions", role: "AXTable", children: rows)
    }

    /// 候補リストの見出しの行（「Go to:」）。
    static let suggestionHeaderRow = FakeAXElement(name: "header-row", role: "AXRow", children: [
        FakeAXElement(name: "header-cell", role: "AXCell", children: [
            FakeAXElement(name: "header-text", role: "AXStaticText", value: "Go to:"),
        ]),
    ])

    /// 候補リストの候補の行（AXRow > AXCell > AXList。AXList の AXIdentifier が候補のパス）。
    static func suggestionRow(_ path: String) -> FakeAXElement {
        FakeAXElement(name: "row \(path)", role: "AXRow", children: [
            FakeAXElement(name: "cell \(path)", role: "AXCell", children: [
                FakeAXElement(name: "list \(path)", role: "AXList", identifier: path, children: [
                    FakeAXElement(name: "component", role: "AXStaticText", value: "Users"),
                ]),
            ]),
        ])
    }

    /// パネルのツールバーの場所のポップアップ（値が現在のフォルダの表示名）。
    static func locationPopUp(_ folderName: String) -> FakeAXElement {
        FakeAXElement(name: "where", role: "AXPopUpButton", identifier: "where popup", value: folderName)
    }
}

/// 要素探しが呼んだ AX 操作（role / subrole / title / placeholder / children の読み取り）を数える。
/// 打ち切り条件は axQueue 上で確かめられる想定のため、どのスレッドからでも読めるようロックで守る。
struct AXOperationCounter: Sendable {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    var value: Int {
        count.withLock { $0 }
    }

    func record() {
        count.withLock { $0 += 1 }
    }

    /// AX 操作が limit 回に達したら打ち切る条件。
    func cutoff(afterOperations limit: Int) -> ScanCutoff {
        let count = count
        return ScanCutoff { count.withLock { $0 } >= limit }
    }
}

/// FakeAXElement のツリーに対して要素探しを呼ぶ。
enum FakeAXSearch {
    static func goToField(
        in root: FakeAXElement,
        counter: AXOperationCounter = AXOperationCounter(),
        cutoff: ScanCutoff = .never
    ) throws -> GoToFieldMatch<FakeAXElement>? {
        try GoToFieldSearch.locate(
            in: root,
            cutoff: cutoff,
            role: { counter.record(); return $0.role },
            subrole: { counter.record(); return $0.subrole },
            title: { counter.record(); return $0.title },
            identifier: { counter.record(); return $0.identifier },
            placeholder: { counter.record(); return $0.placeholder },
            children: { counter.record(); return $0.children }
        )
    }

    static func suggestionPath(
        inSelectedRow row: FakeAXElement,
        counter: AXOperationCounter = AXOperationCounter(),
        cutoff: ScanCutoff = .never
    ) throws -> String? {
        try GoToSuggestionSearch.path(
            inSelectedRow: row,
            cutoff: cutoff,
            role: { counter.record(); return $0.role },
            identifier: { counter.record(); return $0.identifier },
            children: { counter.record(); return $0.children }
        )
    }

    static func displayedFolderName(
        in root: FakeAXElement,
        counter: AXOperationCounter = AXOperationCounter(),
        cutoff: ScanCutoff = .never
    ) throws -> String? {
        try PanelLocationSearch.displayedFolderName(
            in: root,
            cutoff: cutoff,
            role: { counter.record(); return $0.role },
            subrole: { counter.record(); return $0.subrole },
            identifier: { counter.record(); return $0.identifier },
            value: { counter.record(); return $0.value },
            children: { counter.record(); return $0.children }
        )
    }

    static func openButton(
        in root: FakeAXElement,
        counter: AXOperationCounter = AXOperationCounter(),
        cutoff: ScanCutoff = .never
    ) throws -> FakeAXElement? {
        try OpenButtonSearch.locate(
            in: root,
            cutoff: cutoff,
            role: { counter.record(); return $0.role },
            subrole: { counter.record(); return $0.subrole },
            title: { counter.record(); return $0.title },
            children: { counter.record(); return $0.children }
        )
    }
}
