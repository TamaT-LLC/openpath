import Foundation

/// パネル判定の診断の debug ログの文言（Issue #83）。
///
/// QA が `logLevel debug` で S-01 を再実行し、そのログだけでどの条件で弾いたかを見分けられるようにする。
/// パス・ファイル名・ウィンドウタイトル・入力欄の文字列は出さない。アプリが決める文字列は、決まった値だけをそのまま出し、
/// それ以外は長さなどの分類だけを出す（ファイル名などを含み得るため。Issue #83 の CodeRabbit の指摘）。
/// - role・subrole: AX の定数（`AX` で始まる英数字）だけ。それ以外は `<custom len: N>`
/// - AXIdentifier: `loggedIdentifiers`（`open-panel` / `save-panel`）だけ。それ以外は `<other len: N>`（`panel` を含めば添える）
/// - ボタンの表題: パネルでよく使う表題（`loggedButtonTitles`）だけ。それ以外は長さと、含む確定ボタンの表題（定数）
/// - 入力欄: 説明・タイトルの有無と、保存パネルの語（`OpenPanelCriteria.saveFieldKeywords`）のどれに一致したか
extension OpenPanelDiagnostic {
    /// ボタンを並べる数の上限。超えた分は数だけ出す。
    static let maxLoggedButtons = 12
    /// ロールの数を並べる種類の上限。
    static let maxLoggedRoles = 12
    /// そのまま出すボタンの表題（前後の空白を除いて完全一致）。確定ボタンの表題と、開く・保存パネルやアラートの
    /// 決まった表題。これ以外の表題は本文を出さない。
    static let loggedButtonTitles: Set<String> = OpenPanelCriteria.confirmButtonTitles.union([
        "キャンセル", "Cancel", "新規フォルダ", "New Folder", "新規書類", "New Document",
        "オプションを表示", "Show Options", "オプションを隠す", "Hide Options",
        "保存", "Save", "移動", "Go", "完了", "Done", "OK",
    ])
    /// そのまま出す AXIdentifier。NSOpenPanel / NSSavePanel のウィンドウの識別子。
    static let loggedIdentifiers: Set<String> = [OpenPanelCriteria.openPanelIdentifier, "save-panel"]
    /// AXIdentifier の `<other …>` に、含むかを添える語。パネルらしい別の識別子を見分けるため。
    static let identifierHint = "panel"
    /// `<other …>` に添える確定ボタンの表題を探す順（長いものを先に。同じ長さなら名前の順）。
    private static let confirmTitlesByLength = OpenPanelCriteria.confirmButtonTitles.sorted { lhs, rhs in
        lhs.count != rhs.count ? lhs.count > rhs.count : lhs < rhs
    }

    /// 弾いた条件（`notCandidate` / `noConfirmButton` / `noFileList` / `looksLikeSavePanel` / `truncated`）と、
    /// 判定できなかったこと（`unreadable`）。開くパネルなら空。
    /// `truncated` は、確定ボタンかファイル一覧が見つからず、探索を上限で打ち切っていた場合に添える。
    public var rejectionReasons: [String] {
        switch result {
        case .notCandidate:
            ["notCandidate"]
        case .openPanel:
            []
        case .savePanel:
            ["looksLikeSavePanel"]
        case .unreadable:
            ["unreadable"]
        case .missingElements(let hasConfirmButton, let hasFileList, _):
            (hasConfirmButton ? [] : ["noConfirmButton"])
                + (hasFileList ? [] : ["noFileList"])
                + (details?.isTruncated == true ? ["truncated"] : [])
        }
    }

    /// debug ログの 1 行。
    ///
    /// 例: `panel check (target: window, role: AXWindow, subrole: AXStandardWindow, identifier: open-panel,
    /// candidate: openPanelIdentifier, attempt: 1/5, result: openPanel, buttons: [開く*(enabled: false), …], lists: […],
    /// textFields: […], search: (visited: 61/400, deepest: 6/6, unexploredAtDepthLimit: 0), roles: AXGroup×20 …)`
    public var logMessage: String {
        var fields = [
            "target: \(targetText)",
            "role: \(Self.roleLabel(role))",
            "subrole: \(Self.roleLabel(subrole))",
            "identifier: \(Self.identifierLabel(identifier))",
        ]
        if result == .notCandidate {
            fields.append("result: rejected: notCandidate")
        } else {
            fields += [
                "candidate: \(candidateReason?.rawValue ?? "none")",
                "attempt: \(attempt)/\(maxAttempts)",
                "result: \(resultText)",
            ]
            if let details {
                fields += Self.detailFields(details)
            }
        }
        return "panel check (\(fields.joined(separator: ", ")))"
    }

    private var targetText: String {
        switch target {
        case .window:
            "window"
        case .sheet(let nesting):
            "sheet#\(nesting)"
        }
    }

    private var resultText: String {
        switch result {
        case .notCandidate, .savePanel:
            "rejected: \(rejectionReasons.joined(separator: "+"))"
        case .openPanel:
            "openPanel"
        case .missingElements(_, _, let willRecheck):
            "\(willRecheck ? "pending" : "rejected"): \(rejectionReasons.joined(separator: "+"))"
        case .unreadable:
            "undetermined: unreadable"
        }
    }

    // MARK: - 子孫の要約

    private static func detailFields(_ details: OpenPanelClassificationDetails) -> [String] {
        [
            "buttons: [\(buttonsText(details.buttons))]",
            "lists: [\(details.lists.map(listText).joined(separator: ", "))]",
            "textFields: [\(details.textFields.map(textFieldText).joined(separator: ", "))]",
            "search: (visited: \(details.visitedCount)/\(details.maxVisitedNodes), deepest: \(details.deepestLevel)/\(details.maxDepth), "
                + "unexploredAtDepthLimit: \(details.unexploredAtDepthLimit))",
            "roles: \(rolesText(details.roleCounts))",
        ]
    }

    private static func buttonsText(_ buttons: [OpenPanelClassificationDetails.Button]) -> String {
        var items = buttons.prefix(maxLoggedButtons).map(buttonText)
        if buttons.count > maxLoggedButtons {
            items.append("+\(buttons.count - maxLoggedButtons) more")
        }
        return items.joined(separator: ", ")
    }

    /// 表題のあるボタンは `開く*(enabled: false)`（* は確定ボタンのタイトル）。よく使う表題でなければ
    /// `<other len: 3, contains: 開く>(enabled: false)`（長さと、含む確定ボタンの表題だけ）。
    /// 表題の無いボタンは `-(desc: yes, enabled: true)`。説明は、確定ボタンのタイトルと一致するときだけその表題を出す。
    private static func buttonText(_ button: OpenPanelClassificationDetails.Button) -> String {
        let enabled = button.isEnabled.map(String.init) ?? "?"
        if let title = button.title, !title.isEmpty {
            return "\(titleLabel(title))\(button.isConfirm ? "*" : "")(enabled: \(enabled))"
        }
        let description = if let confirmTitle = button.descriptionConfirmTitle {
            "\(confirmTitle)*"
        } else {
            button.hasDescription ? "yes" : "no"
        }
        return "-(desc: \(description), enabled: \(enabled))"
    }

    /// `AXList(AXCollectionList)*`（* はファイル一覧とみなしたもの）。
    private static func listText(_ list: OpenPanelClassificationDetails.ListElement) -> String {
        let subrole = list.subrole.map { "(\(roleLabel($0)))" } ?? ""
        return "\(roleLabel(list.role))\(subrole)\(list.isFileList ? "*" : "")"
    }

    /// `AXSearchField(desc: yes, title: no)`、保存パネルの語に一致したら `…, saveKeyword: 名前 in desc)`。
    private static func textFieldText(_ field: OpenPanelClassificationDetails.TextField) -> String {
        var attributes = ["desc: \(field.hasDescription ? "yes" : "no")", "title: \(field.hasTitle ? "yes" : "no")"]
        if let match = field.saveKeywordMatch {
            attributes.append("saveKeyword: \(match.keyword) in \(match.source.rawValue)")
        }
        return "\(roleLabel(field.subrole ?? OpenPanelCriteria.textFieldRole))(\(attributes.joined(separator: ", ")))"
    }

    /// 数の多い順（同数ならロール名の順）に `AXGroup×20 AXButton×8`。ロールを読めなかった要素は `nil`。
    private static func rolesText(_ roleCounts: [String: Int]) -> String {
        guard !roleCounts.isEmpty else { return "none" }
        let labeled = roleCounts.reduce(into: [String: Int]()) { labeled, entry in
            labeled[entry.key == "nil" ? "nil" : roleLabel(entry.key), default: 0] += entry.value
        }
        let sorted = labeled.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        var items = sorted.prefix(maxLoggedRoles).map { "\($0.key)×\($0.value)" }
        if sorted.count > maxLoggedRoles {
            items.append("+\(sorted.count - maxLoggedRoles) more")
        }
        return items.joined(separator: " ")
    }

    // MARK: - 文字列の整形

    /// ボタンの表題の出し方。よく使う表題はそのまま、それ以外は長さと、含む確定ボタンの表題（大文字小文字を区別しない）だけ。
    /// 確定ボタンの表題の違い（「開く…」など）を、表題の本文を出さずに見分けられるようにする。
    static func titleLabel(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if loggedButtonTitles.contains(trimmed) {
            return trimmed
        }
        var attributes = ["len: \(trimmed.count)"]
        if let confirmTitle = confirmTitlesByLength.first(where: { trimmed.range(of: $0, options: .caseInsensitive) != nil }) {
            attributes.append("contains: \(confirmTitle)")
        }
        return "<other \(attributes.joined(separator: ", "))>"
    }

    /// role・subrole。AX の定数（`AX` で始まる ASCII の英数字）だけそのまま出し、それ以外は長さだけを出す。
    static func roleLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        let isAXConstant = value.hasPrefix("AX") && value.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
        return isAXConstant ? value : "<custom len: \(value.count)>"
    }

    /// AXIdentifier。NSOpenPanel / NSSavePanel の識別子だけそのまま出し、それ以外は長さと、`panel` を含むかだけを出す。
    static func identifierLabel(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        if loggedIdentifiers.contains(value) {
            return value
        }
        let hint = value.range(of: identifierHint, options: .caseInsensitive) != nil ? ", contains: \(identifierHint)" : ""
        return "<other len: \(value.count)\(hint)>"
    }
}
