/// 主方式の待ち時間（DSN-001 §3.1）。
///
/// 移動先シートを開く 3 段（① 注入先のプロセスへの ⌘⇧G → ② システム経由の / → ③ システム経由の ⌘⇧G、`GoToSheetOpener`）の
/// 待ちは、① が届かない注入先（macOS 26 の VS Code のリモートのパネル、Issue #29）でも ③ まで進めるよう、
/// 1.5 秒を目安に配分している。各段は最後の確認を期限の 1 間隔前に行うため、① は 150ms・② は送ってから 250ms で見切る。
/// ② を経て ③ で開く最も遅い経路でも、シートが ③ の 150ms 後に出れば auto_confirm の「開く」まで約 950ms で終わる
/// （PathInjectionFlowKeyRouteTests）。③ の上限近くでシートが出て、入力欄のフォーカスと候補の更新を待つと 1.5 秒を超えるため
/// （Issue #29 の QA の初回の注入、PathInjectionFlowSlowSheetTests）、AppCoordinator の全体タイムアウトは 2.5 秒にしている。
/// シートが出なければ各段の待ちで打ち切って副方式へ回るため、全体タイムアウトを延ばしても失敗が遅れることはない。
public struct PathInjectionTiming: Equatable, Sendable {
    /// 代替（`GoToSheetFallback`）の無い構成で、⌘⇧G から移動先シートの出現を待つ上限（ステップ 4）。
    /// 基準の走査（ステップ 2）の上限にも使う。
    public let sheetWaitLimit: Duration
    /// 移動先シートの出現を確かめる間隔（ステップ 4）。
    public let sheetPollInterval: Duration
    /// ⌘V からペーストの反映を待つ時間（ステップ 6）。
    public let pasteSettleDelay: Duration
    /// Return からペーストボードを戻すまでの時間（ステップ 9、ARCH-001 §7）。
    public let restoreDelay: Duration
    /// ①: 代替がある構成で、注入先のプロセスへ送った ⌘⇧G からシートの出現を待つ上限。
    /// 届かない注入先で ②・③ に進むまでの時間を短くするため、`sheetWaitLimit` より短くする。
    public let targetProcessSheetWaitLimit: Duration
    /// ②: システム経由で送った / からシートの出現を待つ上限。
    public let slashSheetWaitLimit: Duration
    /// ③: システム経由で送った ⌘⇧G からシートの出現を待つ上限。#107 より前に VS Code で移動まで成功した経路のため、最も長く待つ。
    public let systemGoToSheetWaitLimit: Duration

    public init(
        sheetWaitLimit: Duration,
        sheetPollInterval: Duration,
        pasteSettleDelay: Duration,
        restoreDelay: Duration,
        targetProcessSheetWaitLimit: Duration = Self.defaultTargetProcessSheetWaitLimit,
        slashSheetWaitLimit: Duration = Self.defaultSlashSheetWaitLimit,
        systemGoToSheetWaitLimit: Duration = Self.defaultSystemGoToSheetWaitLimit
    ) {
        self.sheetWaitLimit = sheetWaitLimit
        self.sheetPollInterval = sheetPollInterval
        self.pasteSettleDelay = pasteSettleDelay
        self.restoreDelay = restoreDelay
        self.targetProcessSheetWaitLimit = targetProcessSheetWaitLimit
        self.slashSheetWaitLimit = slashSheetWaitLimit
        self.systemGoToSheetWaitLimit = systemGoToSheetWaitLimit
    }

    public static let defaultTargetProcessSheetWaitLimit: Duration = .milliseconds(200)
    public static let defaultSlashSheetWaitLimit: Duration = .milliseconds(300)
    public static let defaultSystemGoToSheetWaitLimit: Duration = .milliseconds(500)

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
