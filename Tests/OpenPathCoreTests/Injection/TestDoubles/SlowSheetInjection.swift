import Testing

import OpenPathCore

/// Issue #29 の実機 QA（macOS 26 の VS Code、初回の注入）に近い、遅いが成功する自動確定（auto_confirm / Cmd+Enter）の注入。
///
/// 経路の記憶が無い初回の注入で、注入先のプロセスへの ⌘⇧G（①）もシステム経由の /（②）も届かない。
/// ③（システム経由の ⌘⇧G）を送ると、QA と同じく注入の開始から 887ms に移動先シートが出て、③ の最後の確認（900ms）で見つける。
/// ② の前のフォーカス中の要素の読み取り（AX）に 50ms かかる。入力欄はシートを見つけた 100ms 後にフォーカスを持ち、
/// 候補リストはその 250ms 後に移動先を選ぶ（Issue #74 の QA の条件。PathInjectionFlowFocusTests）。
/// QA では、③ でシートが出た後のペーストと確定が 1.5 秒の全体タイムアウトに間に合わず、`timeout(overall)` になった。
enum SlowSheetInjection: CaseIterable, Sendable, CustomTestStringConvertible {
    /// 主方式で貼り付けて Return を送り、「開く」を押す。
    case primary
    /// ⌘V が入力欄に届かず（fieldMismatch）、副方式で値をセットして Return を送り、「開く」を押す（QA の S-05 の Cmd+Enter）。
    case secondaryAfterFieldMismatch

    static let path = "/Users/me/Library"
    /// 移動先シートの入力欄に、最初から入っている前回の移動先。
    static let previousPath = "/Users/me/前回の場所"
    /// QA で ③ の後に移動先シートが出た時刻（注入の開始から）。
    static let sheetAppearsAt: Duration = .milliseconds(887)
    /// フォーカス中の要素の読み取り（AX）にかかる時間。
    static let focusReadLatency: Duration = .milliseconds(50)
    /// 入力欄がフォーカスを持つ時刻（シートを見つけた 900ms の 100ms 後）。
    static let fieldFocusedAt: Duration = .milliseconds(1_000)
    /// 候補リストが移動先を選ぶ時刻（入力欄がフォーカスを持った 250ms 後）。
    static let suggestionUpdatedAt: Duration = .milliseconds(1_250)

    var testDescription: String {
        switch self {
        case .primary:
            "主方式で貼り付けて「開く」まで"
        case .secondaryAfterFieldMismatch:
            "⌘V が届かず副方式で値をセットして「開く」まで"
        }
    }

    @MainActor
    func makeHarness() -> FlowHarness {
        let harness = FlowHarness(sheetAppearsAt: nil, fallsBackWhenSheetMissing: true)
        let clock = harness.clock
        harness.focusReader.latency = Self.focusReadLatency
        harness.keyboard.onRoutedPost = { [harness] keyStroke, route in
            guard keyStroke == .goToFolder, route == .systemWide else { return }
            harness.sheetDetector.appearsAt = Self.sheetAppearsAt
        }
        harness.goToField.simulateTyping(Self.previousPath)
        harness.goToField.focusProvider = { clock.elapsed >= Self.fieldFocusedAt }
        let suggestions = SuggestionListFake()
        suggestions.selectedPathProvider = { clock.elapsed >= Self.suggestionUpdatedAt ? Self.path : Self.previousPath }
        harness.submitCheckLocator.suggestionList = suggestions
        harness.goToFieldLocator.suggestionList = suggestions
        // macOS 13 以降の移動先シートには「移動」ボタンが無く、副方式は Return で確定する
        harness.goToFieldLocator.goButton = nil
        if self == .secondaryAfterFieldMismatch {
            // システム経由で送った ⌘V が入力欄に届かず、前回の移動先が残る
            harness.keyboard.onPost = nil
        }
        return harness
    }
}
