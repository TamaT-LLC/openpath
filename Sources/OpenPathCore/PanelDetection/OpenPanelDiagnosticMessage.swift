import Foundation

/// パネル判定の診断の debug ログの文言（Issue #83）。
///
/// QA が `logLevel debug` で S-01 を再実行し、そのログだけでどの条件で弾いたかを見分けられるようにする。
/// パス・ファイル名・ウィンドウタイトル・入力欄の文字列は出さない。出すのはロール名・AXIdentifier・ボタンの表題と、
/// 保存パネルの語（`OpenPanelCriteria.saveFieldKeywords`）のどれに一致したかだけ。ボタンの表題も、パスらしいもの
/// （"/" を含む）は伏せ、長いものは切る。
extension OpenPanelDiagnostic {
    /// ボタンを並べる数の上限。超えた分は数だけ出す。
    static let maxLoggedButtons = 12
    /// ロールの数を並べる種類の上限。
    static let maxLoggedRoles = 12
    /// 表題・ロール名などを切る長さ（文字数）。
    static let maxLoggedLabelLength = 24

    /// 弾いた条件（`notCandidate` / `noConfirmButton` / `noFileList` / `looksLikeSavePanel` / `truncated`）。開くパネルなら空。
    /// `truncated` は、確定ボタンかファイル一覧が見つからず、探索を上限で打ち切っていた場合に添える。
    public var rejectionReasons: [String] {
        switch result {
        case .notCandidate:
            ["notCandidate"]
        case .openPanel:
            []
        case .savePanel:
            ["looksLikeSavePanel"]
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
            "role: \(Self.label(role))",
            "subrole: \(Self.label(subrole))",
            "identifier: \(Self.label(identifier))",
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

    /// 表題のあるボタンは `開く*(enabled: false)`（* は確定ボタンのタイトル）。
    /// 表題の無いボタンは `-(desc: yes, enabled: true)`。説明は、確定ボタンのタイトルと一致するときだけその表題を出す。
    private static func buttonText(_ button: OpenPanelClassificationDetails.Button) -> String {
        let enabled = button.isEnabled.map(String.init) ?? "?"
        if let title = button.title, !title.isEmpty {
            return "\(sanitized(title))\(button.isConfirm ? "*" : "")(enabled: \(enabled))"
        }
        let description = if let confirmTitle = button.descriptionConfirmTitle {
            "\(sanitized(confirmTitle))*"
        } else {
            button.hasDescription ? "yes" : "no"
        }
        return "-(desc: \(description), enabled: \(enabled))"
    }

    /// `AXList(AXCollectionList)*`（* はファイル一覧とみなしたもの）。
    private static func listText(_ list: OpenPanelClassificationDetails.ListElement) -> String {
        let subrole = list.subrole.map { "(\(sanitized($0)))" } ?? ""
        return "\(sanitized(list.role))\(subrole)\(list.isFileList ? "*" : "")"
    }

    /// `AXSearchField(desc: yes, title: no)`、保存パネルの語に一致したら `…, saveKeyword: 名前 in desc)`。
    private static func textFieldText(_ field: OpenPanelClassificationDetails.TextField) -> String {
        var attributes = ["desc: \(field.hasDescription ? "yes" : "no")", "title: \(field.hasTitle ? "yes" : "no")"]
        if let match = field.saveKeywordMatch {
            attributes.append("saveKeyword: \(match.keyword) in \(match.source.rawValue)")
        }
        return "\(sanitized(field.subrole ?? OpenPanelCriteria.textFieldRole))(\(attributes.joined(separator: ", ")))"
    }

    /// 数の多い順（同数ならロール名の順）に `AXGroup×20 AXButton×8`。
    private static func rolesText(_ roleCounts: [String: Int]) -> String {
        guard !roleCounts.isEmpty else { return "none" }
        let sorted = roleCounts.sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.key < rhs.key
        }
        var items = sorted.prefix(maxLoggedRoles).map { "\(sanitized($0.key))×\($0.value)" }
        if sorted.count > maxLoggedRoles {
            items.append("+\(sorted.count - maxLoggedRoles) more")
        }
        return items.joined(separator: " ")
    }

    // MARK: - 文字列の整形

    private static func label(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "none" }
        return sanitized(value)
    }

    /// 改行などの制御文字を空白にし、パスらしいもの（"/" を含む）は伏せ、長いものは切る。
    static func sanitized(_ value: String) -> String {
        guard !value.contains("/") else { return "<path-like>" }
        let flattened = String(value.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) || CharacterSet.newlines.contains(scalar) ? " " : Character(scalar)
        })
        guard flattened.count > maxLoggedLabelLength else { return flattened }
        return "\(flattened.prefix(maxLoggedLabelLength))…"
    }
}
