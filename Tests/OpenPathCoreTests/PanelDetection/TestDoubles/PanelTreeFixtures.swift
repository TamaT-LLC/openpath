import CoreGraphics

/// パネルの UI の言語。日本語と英語の両方で判定できることを確かめる。
enum PanelUILanguage: String, CaseIterable, CustomStringConvertible {
    case japanese
    case english

    var description: String {
        rawValue
    }

    var labels: PanelLabels {
        switch self {
        case .japanese:
            PanelLabels(
                open: "開く", cancel: "キャンセル", newFolder: "新規フォルダ", search: "検索",
                save: "保存", saveAsField: "名前:", tagsField: "タグ:", go: "移動"
            )
        case .english:
            PanelLabels(
                open: "Open", cancel: "Cancel", newFolder: "New Folder", search: "Search",
                save: "Save", saveAsField: "Save As:", tagsField: "Tags:", go: "Go"
            )
        }
    }
}

/// パネルに現れる文言。
struct PanelLabels {
    let open: String
    let cancel: String
    let newFolder: String
    let search: String
    let save: String
    let saveAsField: String
    let tagsField: String
    let go: String
}

/// パネルやウィンドウの AX ツリー。実機の Accessibility Inspector で見える構造を簡略化したもの。
enum PanelTreeFixtures {
    static let dialogFrame = CGRect(x: 100, y: 120, width: 800, height: 520)
    static let sheetFrame = CGRect(x: 240, y: 80, width: 720, height: 460)
    static let documentFrame = CGRect(x: 200, y: 60, width: 1_000, height: 700)

    // MARK: - パネルの中身

    /// NSOpenPanel の中身。サイドバー（AXOutline）とファイル一覧、ツールバー、下部のボタン。
    static func openPanelBody(
        _ language: PanelUILanguage,
        confirmTitle: String? = nil,
        fileListRole: String = "AXBrowser"
    ) -> [StubNode] {
        let labels = language.labels
        return [
            StubNode(role: "AXSplitGroup", children: [
                StubNode(role: "AXScrollArea", children: [sidebar()]),
                group([
                    group([
                        StubNode(role: "AXButton", description: "戻る"),
                        StubNode(role: "AXPopUpButton"),
                        textField(description: labels.search, subrole: "AXSearchField"),
                    ]),
                    StubNode(role: "AXScrollArea", children: [fileList(role: fileListRole)]),
                ]),
            ]),
            button(labels.newFolder),
            button(labels.cancel),
            button(confirmTitle ?? labels.open),
        ]
    }

    /// NSSavePanel の中身。ファイル名欄とタグ欄、ファイル一覧（展開時）、下部のボタン。
    /// - Parameter fileList: 展開時のファイル一覧。省略するとカラム表示（AXBrowser）。
    static func savePanelBody(_ language: PanelUILanguage, confirmTitle: String? = nil, fileList: StubNode? = nil) -> [StubNode] {
        let labels = language.labels
        return [
            StubNode(role: "AXStaticText"),
            textField(description: labels.saveAsField),
            textField(description: labels.tagsField),
            group([StubNode(role: "AXScrollArea", children: [fileList ?? Self.fileList(role: "AXBrowser")])]),
            button(labels.newFolder),
            button(labels.cancel),
            button(confirmTitle ?? labels.save),
        ]
    }

    /// アラート。Gatekeeper の確認のように「開く」ボタンを持つものもあるが、ファイル一覧はない。
    static func alertBody(_ language: PanelUILanguage) -> [StubNode] {
        let labels = language.labels
        return [
            StubNode(role: "AXImage"),
            StubNode(role: "AXStaticText"),
            button(labels.cancel),
            button(labels.open),
        ]
    }

    /// ⌘⇧G の移動先シート。
    static func goToSheet(_ language: PanelUILanguage) -> StubNode {
        let labels = language.labels
        return sheet(id: nil, [
            StubNode(role: "AXStaticText"),
            textField(),
            button(labels.cancel),
            button(labels.go),
        ])
    }

    // MARK: - ウィンドウとシート

    /// 独立したダイアログ（`runModal` の NSOpenPanel など）。
    static func dialog(id: String, frame: CGRect = dialogFrame, _ body: [StubNode]) -> StubNode {
        StubNode(id: id, role: "AXWindow", subrole: "AXDialog", frame: frame, children: body)
    }

    /// ウィンドウに付くシート（`beginSheetModal` のパネルなど）。
    static func sheet(id: String?, frame: CGRect = sheetFrame, _ body: [StubNode]) -> StubNode {
        StubNode(id: id, role: "AXSheet", frame: frame, children: body)
    }

    /// サンドボックスアプリのパネル。別プロセス（openAndSavePanelService）で描画され、
    /// ホストのウィンドウの子の AXSheet の下に、リモートビューのグループを挟んで中身が現れる。
    static func remoteSheet(id: String?, _ body: [StubNode]) -> StubNode {
        sheet(id: id, [group([group(body)])])
    }

    /// 通常のウィンドウ。シートは子要素として末尾に付く。
    static func documentWindow(id: String, sheets: [StubNode] = []) -> StubNode {
        StubNode(id: id, role: "AXWindow", subrole: "AXStandardWindow", frame: documentFrame, children: [
            StubNode(role: "AXButton", subrole: "AXCloseButton"),
            StubNode(role: "AXButton", subrole: "AXMinimizeButton"),
            StubNode(role: "AXToolbar", children: [button("共有")]),
            StubNode(role: "AXScrollArea", children: [StubNode(role: "AXTextArea")]),
        ] + sheets)
    }

    // MARK: - 部品

    static func button(_ title: String?) -> StubNode {
        StubNode(role: "AXButton", title: title)
    }

    static func textField(description: String? = nil, title: String? = nil, subrole: String? = nil) -> StubNode {
        StubNode(role: "AXTextField", subrole: subrole, title: title, description: description)
    }

    static func group(_ children: [StubNode]) -> StubNode {
        StubNode(role: "AXGroup", children: children)
    }

    /// ファイル一覧。行の中にファイル名の入力欄やボタンがあるが、判定では中へ降りない。
    static func fileList(role: String, id: String? = nil) -> StubNode {
        StubNode(id: id, role: role, children: [
            StubNode(role: "AXRow", children: [
                textField(description: "保存したメモ.txt", title: "名前を変更"),
                button("開く"),
            ]),
        ])
    }

    /// サイドバー（よく使う項目）。AXOutline なのでファイル一覧の条件も満たす。
    private static func sidebar() -> StubNode {
        StubNode(role: "AXOutline", children: [
            StubNode(role: "AXRow", children: [StubNode(role: "AXStaticText")]),
        ])
    }
}
