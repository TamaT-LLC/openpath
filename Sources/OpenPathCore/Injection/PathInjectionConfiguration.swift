/// 主方式の待ち時間（DSN-001 §3.1）。
public struct PathInjectionTiming: Equatable, Sendable {
    /// ⌘⇧G から移動先シートの出現を待つ上限（ステップ 4）。
    public let sheetWaitLimit: Duration
    /// 移動先シートの出現を確かめる間隔（ステップ 4）。
    public let sheetPollInterval: Duration
    /// ⌘V からペーストの反映を待つ時間（ステップ 6）。
    public let pasteSettleDelay: Duration
    /// Return からペーストボードを戻すまでの時間（ステップ 9、ARCH-001 §7）。
    public let restoreDelay: Duration

    public init(sheetWaitLimit: Duration, sheetPollInterval: Duration, pasteSettleDelay: Duration, restoreDelay: Duration) {
        self.sheetWaitLimit = sheetWaitLimit
        self.sheetPollInterval = sheetPollInterval
        self.pasteSettleDelay = pasteSettleDelay
        self.restoreDelay = restoreDelay
    }

    public static let standard = PathInjectionTiming(
        sheetWaitLimit: .milliseconds(600),
        sheetPollInterval: .milliseconds(50),
        pasteSettleDelay: .milliseconds(100),
        restoreDelay: .milliseconds(200)
    )
}

/// 主方式の手順に外から差し込む処理。
public struct PathInjectionHooks: Sendable {
    public typealias PrepareForKeyEvents = @MainActor @Sendable () async -> Void
    public typealias DidSubmitGoToSheet = @MainActor @Sendable (_ autoConfirm: Bool) async throws -> Void

    /// キー操作を送る前に 1 回呼ぶ。
    /// パレットにキーウィンドウを手放させ、キー入力が NSOpenPanel に届く状態にしてから戻ること。
    /// パレットがキーのままだと ⌘⇧G などがパレットに届いてしまう。
    public var prepareForKeyEvents: PrepareForKeyEvents
    /// Return（移動先シートの確定）を送った後、ペーストボードを戻す前に呼ぶ（DSN-001 §3.1 ステップ 8）。
    /// auto_confirm 時の「開く」の押下を差し込むためのもの。投げたエラーは注入の失敗としてそのまま伝える。
    public var didSubmitGoToSheet: DidSubmitGoToSheet

    public init(
        prepareForKeyEvents: @escaping PrepareForKeyEvents = {},
        didSubmitGoToSheet: @escaping DidSubmitGoToSheet = { _ in }
    ) {
        self.prepareForKeyEvents = prepareForKeyEvents
        self.didSubmitGoToSheet = didSubmitGoToSheet
    }

    /// 何も差し込まない。
    public static let none = PathInjectionHooks()
}
