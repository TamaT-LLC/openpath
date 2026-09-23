/// パネルの候補（ダイアログのウィンドウまたはシート）を判定した結果。
public enum OpenPanelVerdict: Equatable, Sendable {
    /// NSOpenPanel（条件 2〜4 を満たす）。
    case openPanel
    /// 保存パネル（条件 4 に反する）。保存パネルが開くパネルに変わることはないため、確定的な判定。
    case savePanel
    /// 確定ボタンかファイル一覧が見つからなかった。アラートなどのほか、描画途中のパネル
    /// （サンドボックスアプリのパネルは別プロセスで描画される）の可能性もある。
    case missingElements(hasConfirmButton: Bool, hasFileList: Bool)
}

/// パネルの中で見つけたファイル一覧の要素。
public struct FileListElement<Node> {
    public let node: Node
    /// `OpenPanelCriteria.fileListRoles` のいずれか。
    public let role: String

    public init(node: Node, role: String) {
        self.node = node
        self.role = role
    }
}

extension FileListElement: Equatable where Node: Equatable {}

/// `OpenPanelClassifier.classification(of:reader:search:)` の結果。
public struct OpenPanelClassification<Node> {
    public let verdict: OpenPanelVerdict
    /// パネルの中身のファイル一覧。選択モードの推定（DSN-001 §2.3）に使う。
    ///
    /// パネルにはサイドバー（AXOutline）もファイル一覧のロールで現れる。サイドバーは中身の一覧より前（幅優先の順で先）に
    /// 現れるため、最後に見つけたものを中身の一覧とみなす。見つからなければ nil。
    public let fileList: FileListElement<Node>?
}

extension OpenPanelClassification: Equatable where Node: Equatable {}

/// パネルの候補の子孫を調べ、NSOpenPanel かどうかを判定する（DSN-001 §2.2 の条件 2〜4）。
public enum OpenPanelClassifier {
    /// candidate の子孫を幅優先で調べる。
    ///
    /// AX の往復を減らすため、ロールは 1 要素につき 1 回だけ読み、タイトルはボタンと入力欄、説明は入力欄にだけ読む。
    /// ファイル一覧など `OpenPanelCriteria.prunedRoles` の要素の中へは降りない。保存パネルと分かった時点で以降の読み取りをやめる。
    /// - Parameters:
    ///   - candidate: パネルの候補。条件 1（ロール・サブロール）は呼び出し側で確かめておくこと。
    ///   - search: 探索の上限。既定は DSN-001 §2.2 の 6 階層・400 要素。
    /// - Throws: 読み取りに失敗したら `PanelTreeReadError`。candidate 自身が破棄されていたら `.elementGone`。
    ///   子孫が消えていた場合はツリーが変化している途中とみなし、candidate は残っているので `.unavailable` にする。
    public static func classify<Reader: PanelTreeReader>(
        _ candidate: Reader.Node,
        reader: Reader,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch()
    ) throws -> OpenPanelVerdict {
        try classification(of: candidate, reader: reader, search: search).verdict
    }

    /// `classify(_:reader:search:)` と同じ判定を行い、見つけたファイル一覧の要素も返す。AX の読み取りは増えない。
    public static func classification<Reader: PanelTreeReader>(
        of candidate: Reader.Node,
        reader: Reader,
        search: BoundedBreadthFirstSearch = BoundedBreadthFirstSearch()
    ) throws -> OpenPanelClassification<Reader.Node> {
        var findings = Findings<Reader.Node>()
        // ロールの読み取り（AX の往復）を 1 要素 1 回にするため、子を列挙するときにロールも読んで組にする
        _ = try search.descendants(
            of: ClassifiedNode(node: candidate, role: nil, isCandidate: true),
            children: { element in
                guard !findings.isSavePanel else { return [] }
                if let role = element.role, OpenPanelCriteria.prunedRoles.contains(role) {
                    return []
                }
                let children = try element.isCandidate
                    ? reader.children(of: element.node)
                    : readingDescendant { try reader.children(of: element.node) }
                return try children.map { child in
                    ClassifiedNode(node: child, role: try readingDescendant { try reader.role(of: child) }, isCandidate: false)
                }
            },
            where: { element in
                try readingDescendant { try inspect(element, reader: reader, findings: &findings) }
                return false
            }
        )
        return OpenPanelClassification(verdict: verdict(from: findings), fileList: findings.fileList)
    }

    private static func verdict<Node>(from findings: Findings<Node>) -> OpenPanelVerdict {
        if findings.isSavePanel {
            return .savePanel
        }
        let hasFileList = findings.fileList != nil
        guard findings.hasConfirmButton, hasFileList else {
            return .missingElements(hasConfirmButton: findings.hasConfirmButton, hasFileList: hasFileList)
        }
        return .openPanel
    }

    /// 要素を 1 つ調べ、見つかった条件を findings に記録する。
    private static func inspect<Reader: PanelTreeReader>(
        _ element: ClassifiedNode<Reader.Node>,
        reader: Reader,
        findings: inout Findings<Reader.Node>
    ) throws {
        guard !findings.isSavePanel, let role = element.role else { return }
        switch role {
        case OpenPanelCriteria.buttonRole:
            guard !findings.hasConfirmButton, let title = try reader.title(of: element.node) else { return }
            findings.hasConfirmButton = OpenPanelCriteria.isConfirmButtonTitle(title)
        case OpenPanelCriteria.textFieldRole:
            findings.isSavePanel = try isSaveField(element.node, reader: reader)
        default:
            if OpenPanelCriteria.fileListRoles.contains(role) {
                findings.fileList = FileListElement(node: element.node, role: role)
            }
        }
    }

    /// 子孫の読み取り。子孫が消えていても候補は残っているため、`.elementGone` を `.unavailable` に読み替える。
    private static func readingDescendant<T>(_ read: () throws -> T) throws -> T {
        do {
            return try read()
        } catch PanelTreeReadError.elementGone {
            throw PanelTreeReadError.unavailable
        }
    }

    /// 説明を先に読み、保存パネルの語を含んでいればタイトルは読まない。
    private static func isSaveField<Reader: PanelTreeReader>(_ node: Reader.Node, reader: Reader) throws -> Bool {
        if let description = try reader.accessibilityDescription(of: node), OpenPanelCriteria.isSaveFieldLabel(description) {
            return true
        }
        guard let title = try reader.title(of: node) else { return false }
        return OpenPanelCriteria.isSaveFieldLabel(title)
    }
}

/// 判定の途中で見つかった条件。
private struct Findings<Node> {
    var hasConfirmButton = false
    /// 最後に見つけたファイル一覧
    var fileList: FileListElement<Node>?
    var isSavePanel = false
}

/// 探索中の要素と、列挙時に読み取ったロールの組。
private struct ClassifiedNode<Node> {
    let node: Node
    let role: String?
    /// 判定する候補そのものか（子孫でないか）
    let isCandidate: Bool
}
