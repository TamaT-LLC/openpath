import Foundation

/// `OpenPanelClassifier` が判定の探索のついでに子孫の要約（`OpenPanelClassificationDetails`）を集める（debug ログ用、Issue #83）。
///
/// 判定で読んだ値はそのまま使い、足りない値（ボタンの有効状態・説明、入力欄のサブロールなど）だけを追加で読む。
/// 追加の読み取りは `diagnosticReadCount` に数え、失敗しても nil として扱う（判定の結果や例外を変えない）。
struct ClassificationDetailsRecorder {
    /// 深さの上限の要素について、子の数を読む回数の上限。上限の深さに要素が並ぶパネルで読み取りが増えすぎないようにする。
    static let maxDepthLimitChecks = 16
    /// 一覧らしい要素として記録するロール（判定では中へ降りない）。
    private static let listLikeRoles = OpenPanelCriteria.fileListRoles.union([OpenPanelCriteria.collectionListRole, "AXWebArea"])

    private(set) var summary: OpenPanelClassificationDetails
    private var depthLimitChecks = 0

    init(search: BoundedBreadthFirstSearch) {
        summary = OpenPanelClassificationDetails(search: search)
    }

    /// 探索で要素を 1 つ訪問した。深さの上限の要素なら、中を調べ残したか（子を持つか）を確かめる。
    /// - Parameter isSearchStopped: 保存パネルと分かり、以降の読み取りをやめた後か。
    mutating func visit<Reader: PanelTreeReader>(
        _ node: Reader.Node,
        role: String?,
        depth: Int,
        isSearchStopped: Bool,
        reader: Reader
    ) {
        summary.visitedCount += 1
        summary.deepestLevel = max(summary.deepestLevel, depth)
        summary.roleCounts[role ?? "nil", default: 0] += 1
        let isPruned = role.map(OpenPanelCriteria.prunedRoles.contains) ?? false
        guard !isSearchStopped, depth >= summary.maxDepth, !isPruned, depthLimitChecks < Self.maxDepthLimitChecks else { return }
        depthLimitChecks += 1
        if let count = read({ try reader.itemCount(.children, of: node) }), count > 0 {
            summary.unexploredAtDepthLimit += 1
        }
    }

    /// ボタン。
    /// - Parameter readTitle: 判定で読んだタイトル。読んでいなければ nil（`.some(nil)` はタイトルが無いことを表す）。
    mutating func recordButton<Reader: PanelTreeReader>(_ node: Reader.Node, readTitle: String??, reader: Reader) {
        let title = readTitle ?? read { try reader.title(of: node) }
        let isEnabled = read { try reader.isEnabled(of: node) }
        let description = read { try reader.accessibilityDescription(of: node) }
        summary.buttons.append(OpenPanelClassificationDetails.Button(
            title: title,
            isEnabled: isEnabled,
            hasDescription: description?.isEmpty == false,
            descriptionConfirmTitle: description.flatMap { description in
                OpenPanelCriteria.isConfirmButtonTitle(description)
                    ? description.trimmingCharacters(in: .whitespacesAndNewlines)
                    : nil
            }
        ))
    }

    /// 入力欄。文字列は持たず、説明・タイトルの有無と、保存パネルの語に一致したかだけを記録する。
    mutating func recordTextField<Reader: PanelTreeReader>(_ node: Reader.Node, labels: SaveFieldLabels, reader: Reader) {
        let subrole = read { try reader.subrole(of: node) }
        let title = labels.isTitleRead ? labels.title : read { try reader.title(of: node) }
        summary.textFields.append(OpenPanelClassificationDetails.TextField(
            subrole: subrole,
            hasDescription: labels.description?.isEmpty == false,
            hasTitle: title?.isEmpty == false,
            saveKeywordMatch: Self.saveKeywordMatch(description: labels.description, title: title)
        ))
    }

    /// 一覧らしい要素（ファイル一覧のロール・AXList・AXWebArea）なら記録する。
    /// - Parameter readSubrole: 判定で読んだサブロール（AXList のときだけ読んでいる）。
    mutating func recordListIfNeeded<Reader: PanelTreeReader>(
        _ node: Reader.Node,
        role: String,
        readSubrole: String?,
        reader: Reader
    ) {
        guard Self.listLikeRoles.contains(role) else { return }
        let subrole = role == OpenPanelCriteria.collectionListRole ? readSubrole : read { try reader.subrole(of: node) }
        summary.lists.append(OpenPanelClassificationDetails.ListElement(
            role: role,
            subrole: subrole,
            isFileList: OpenPanelCriteria.isFileList(role: role, subrole: subrole)
        ))
    }

    /// 要約のためだけの読み取り。回数を数え、失敗は nil にする。
    private mutating func read<T>(_ body: () throws -> T?) -> T? {
        summary.diagnosticReadCount += 1
        return (try? body()) ?? nil
    }

    private static func saveKeywordMatch(description: String?, title: String?) -> OpenPanelClassificationDetails.SaveKeywordMatch? {
        if let keyword = description.flatMap(OpenPanelCriteria.saveFieldKeyword(in:)) {
            return .init(source: .description, keyword: keyword)
        }
        if let keyword = title.flatMap(OpenPanelCriteria.saveFieldKeyword(in:)) {
            return .init(source: .title, keyword: keyword)
        }
        return nil
    }
}
