import ApplicationServices

import OpenPathCore

/// 注入先のアプリのプロセス ID（`InjectionTargetGuard.targetProcessID`）。
public typealias InjectionTargetProcessID = @MainActor () -> pid_t?

/// 注入先のウィンドウ（`InjectionTargetGuard.targetWindow`）。
public typealias InjectionTargetWindow = @MainActor () -> AXUIElement?

/// 移動先シートの入力欄と「移動」/「Go」ボタン・候補リストを AX で探す（副方式の DSN-001 §3.2 と、主方式の確定前の確認）。
///
/// 注入の最初に記録したウィンドウ（とそのシート）の中を探す。同じアプリの別のウィンドウの入力欄を書き換えないため。
/// どの要素を入力欄とみなすかは OpenPathCore の `GoToFieldSearch` が持つ。
@MainActor
public final class GoToFieldLocator: GoToFieldLocating {
    private let targetWindow: InjectionTargetWindow

    public init(targetWindow: @escaping InjectionTargetWindow) {
        self.targetWindow = targetWindow
    }

    public func locateGoToField(cutoff: ScanCutoff) async throws -> GoToFieldControls? {
        let window = try PanelControlAX.require(targetWindow())
        let match = try await onAXQueue { () throws -> GoToFieldMatch<AXUIElement>? in
            try GoToFieldSearch.locate(
                in: window,
                cutoff: cutoff,
                role: { $0.role },
                subrole: { $0.subrole },
                title: { $0.title },
                identifier: { $0.attr(kAXIdentifierAttribute) },
                placeholder: { $0.attr(kAXPlaceholderValueAttribute) },
                children: PanelControlAX.children(of:)
            )
        }
        guard let match else { return nil }
        return GoToFieldControls(
            field: AXPanelElement(match.field),
            goButton: match.goButton.map { AXPanelElement($0) },
            suggestionList: match.suggestionList.map { AXSuggestionList($0) }
        )
    }
}

/// 移動先シートの候補リスト（AXTable）。選ばれている行の候補のパスを読む。どの要素がパスを持つかは `GoToSuggestionSearch` が持つ。
@MainActor
final class AXSuggestionList: GoToSuggestionListReading {
    /// 1 回の読み取り（行から候補のパスまでたどる数回の AX 操作）の上限。応答しないアプリで確定前の確認が長引かないようにする。
    private static let readLimit: Duration = .milliseconds(100)

    private let table: AXUIElement

    init(_ table: AXUIElement) {
        self.table = table
    }

    /// - Throws: 期限を超えたら `ScanCutoff.Reached`（呼び出し側は選択を読めなかったものとして扱う）。
    func selectedPath() async throws -> String? {
        let table = table
        let deadline = ContinuousClock.now.advanced(by: Self.readLimit)
        let cutoff = ScanCutoff { ContinuousClock.now >= deadline }
        return try await onAXQueue { () throws -> String? in
            let rows: [AXUIElement]
            do {
                let value = try table.copyAttributeValue(kAXSelectedRowsAttribute)
                rows = AXAttributeCast.cast(value, to: [AXUIElement].self) ?? []
            } catch let error as AXElementError {
                // 選択が無い（属性の値が無い）ことは失敗ではない
                guard error.code != .noValue else { return nil }
                throw GoToSheetAX.injectionError(for: error.code)
            }
            guard let row = rows.first.map(GoToSheetAX.limitingMessagingTimeout) else { return nil }
            return try GoToSuggestionSearch.path(
                inSelectedRow: row,
                cutoff: cutoff,
                role: { $0.role },
                identifier: { $0.attr(kAXIdentifierAttribute) },
                children: PanelControlAX.children(of:)
            )
        }
    }
}

/// パネルが表示している現在地（フォルダの表示名）を AX で読む（Issue #74 の診断ログ用）。
/// どの要素が現在地を持つかは OpenPathCore の `PanelLocationSearch` が持つ。
enum PanelLocationReader {
    /// 走査の上限。診断のためだけの走査で `axQueue` を塞ぎ、次の注入を待たせないため短く打ち切る。
    private static let scanLimit: Duration = .milliseconds(300)

    /// window（注入先のウィンドウ）の中のパネルの現在のフォルダの表示名。見つからない・読めない・期限を超えたら nil。
    static func displayedFolderName(in window: AXUIElement) async -> String? {
        let deadline = ContinuousClock.now.advanced(by: scanLimit)
        let cutoff = ScanCutoff { ContinuousClock.now >= deadline }
        return await onAXQueue { () -> String? in
            try? PanelLocationSearch.displayedFolderName(
                in: window,
                cutoff: cutoff,
                role: { $0.role },
                subrole: { $0.subrole },
                identifier: { $0.attr(kAXIdentifierAttribute) },
                value: { $0.attr(kAXValueAttribute) },
                children: PanelControlAX.children(of:)
            )
        }
    }
}

/// auto_confirm（DSN-001 §3.1 ステップ 8）で、パネルの確定ボタン（「開く」等）を AX で探す。
/// 注入の最初に記録したウィンドウ（とそのシート）の中を探す。どのボタンを押すかは OpenPathCore の `OpenButtonSearch` が持つ。
@MainActor
public final class OpenButtonLocator: OpenButtonLocating {
    private let targetWindow: InjectionTargetWindow

    public init(targetWindow: @escaping InjectionTargetWindow) {
        self.targetWindow = targetWindow
    }

    public func locateOpenButton(cutoff: ScanCutoff) async throws -> (any PanelElementOperating)? {
        let window = try PanelControlAX.require(targetWindow())
        let button = try await onAXQueue { () throws -> AXUIElement? in
            try OpenButtonSearch.locate(
                in: window,
                cutoff: cutoff,
                role: { $0.role },
                subrole: { $0.subrole },
                title: { $0.title },
                children: PanelControlAX.children(of:)
            )
        }
        return button.map { AXPanelElement($0) }
    }
}

/// AX で操作するパネル内の要素（入力欄・ボタン）。
@MainActor
final class AXPanelElement: PanelElementOperating {
    private let element: AXUIElement

    init(_ element: AXUIElement) {
        self.element = element
    }

    func setValue(_ value: String) async throws {
        let element = element
        try await onAXQueue { () throws in
            try PanelControlAX.check(AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, value as CFString))
        }
    }

    func press() async throws {
        try await perform(kAXPressAction)
    }

    func confirm() async throws {
        try await perform(kAXConfirmAction)
    }

    func hasDisappeared() async -> Bool {
        let element = element
        return await onAXQueue { () -> Bool in
            // 確かめられなかった（応答が無い等）場合は、消えたとはみなさない
            (try? PanelControlAX.exists(element)) == false
        }
    }

    func value() async throws -> String? {
        let element = element
        return try await onAXQueue { () throws -> String? in
            do {
                let value = try element.copyAttributeValue(kAXValueAttribute)
                return AXAttributeCast.cast(value, to: String.self)
            } catch let error as AXElementError {
                guard error.code != .noValue else { return nil }
                throw GoToSheetAX.injectionError(for: error.code)
            }
        }
    }

    private func perform(_ action: String) async throws {
        let element = element
        try await onAXQueue { () throws in
            try PanelControlAX.check(AXUIElementPerformAction(element, action as CFString))
        }
    }
}

/// `axQueue` 上で呼ぶ、副方式・auto_confirm・注入先の確認の AX 操作。
enum PanelControlAX {
    /// 注入先を記録していなければ、注入先のパネルが無いものとして扱う。
    static func require(_ window: AXUIElement?) throws -> AXUIElement {
        guard let window else { throw InjectionError.panelGone }
        return window
    }

    /// window（またはそのシート）が、processID のアプリのフォーカス中のウィンドウか。
    /// キー入力はフォーカス中のウィンドウに届くため、同じアプリの別のウィンドウに移っていれば false。
    static func hasFocus(_ window: AXUIElement, inProcess processID: pid_t, cutoff: ScanCutoff) throws -> Bool {
        let focusedWindow: AXUIElement
        do {
            focusedWindow = try GoToSheetAX.focusedWindow(ofProcess: processID)
        } catch InjectionError.panelGone {
            return false
        }
        if CFEqual(focusedWindow, window) {
            return true
        }
        try cutoff.throwIfReached()
        // 移動先シートがウィンドウとしてフォーカスを持つ場合も、記録したウィンドウに付いたものなら注入先とみなす
        guard let parent: AXUIElement = focusedWindow.attr(kAXParentAttribute) else { return false }
        return CFEqual(parent, window)
    }

    /// 走査で得た子要素にも、応答しないアプリで止まらないようメッセージングタイムアウトを設定する（GoToSheetDetector と同じ）。
    static func children(of element: AXUIElement) -> [AXUIElement] {
        element.children.map(GoToSheetAX.limitingMessagingTimeout)
    }

    /// 要素がまだ存在するか。
    /// - Throws: 確かめられなければ（応答が無い等）`InjectionError.axError`。
    static func exists(_ element: AXUIElement) throws -> Bool {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value)
        switch result {
        case .success:
            return true
        case .invalidUIElement:
            return false
        default:
            throw InjectionError.axError(code: result.rawValue)
        }
    }

    /// AX 呼び出しの結果を InjectionError に寄せる。kAXErrorAttributeUnsupported（値を書き込めない）も失敗。
    static func check(_ result: AXError) throws {
        guard result == .success else {
            throw GoToSheetAX.injectionError(for: result)
        }
    }
}
