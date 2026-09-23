import os

import OpenPathCore

/// パネル内の要素探し（GoToFieldSearch / OpenButtonSearch）のテストで、AX ツリーの代わりに使う要素。
struct FakeAXElement: Equatable, Sendable {
    let name: String
    let role: String?
    var subrole: String?
    var title: String?
    var placeholder: String?
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
            placeholder: { counter.record(); return $0.placeholder },
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
