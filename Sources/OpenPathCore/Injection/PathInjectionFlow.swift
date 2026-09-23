/// NSOpenPanel へのパス注入の全体（DSN-001 §3〜§4）。
///
/// 1. パスを正規化する（§4）
/// 2. 最前面アプリとそのウィンドウを注入先として記録する（以降のキー操作・AX 操作の直前ごとに確かめる）
/// 3. 主方式（⌘⇧G + ペースト、§3.1）
/// 4. 主方式が移動先シートを見つけられない（waitSheet）か、貼り付けの操作に失敗した（waitPaste）ら、副方式（AX 直接セット、§3.2）
///
/// 前の注入が副方式まで終えるまで、次の注入は始めない。
/// autoConfirm で「開く」を押す前にパネルが消えたら `.panelGoneBeforeConfirm` を投げ、押した後の消滅（成功）と区別する。
@MainActor
public final class PathInjectionFlow {
    /// 副方式へ切り替える主方式の失敗。どちらもシートの確定（Return）を送る前の失敗で、パネルはまだ移動していない。
    /// ペーストボードも、waitSheet では触れておらず、waitPaste では主方式が戻し終えている。
    static let fallbackSteps: Set<InjectionStep> = [.waitSheet, .waitPaste]

    private let targetGuard: any InjectionTargetGuarding
    private let primary: GoToFolderPasteSequencer
    private let secondary: GoToFieldDirectEntry
    private let normalizer: InjectionPathNormalizer
    private let clock: any Clock<Duration>
    private let gate = InjectionSerialGate()

    /// - Parameters:
    ///   - targetGuard: primary・secondary と同じものを渡す。ここで記録した注入先を、それぞれが確かめる。
    ///   - clock: 注入先の記録の期限の計測に使う。
    public init(
        targetGuard: any InjectionTargetGuarding,
        primary: GoToFolderPasteSequencer,
        secondary: GoToFieldDirectEntry,
        normalizer: InjectionPathNormalizer = InjectionPathNormalizer(),
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.targetGuard = targetGuard
        self.primary = primary
        self.secondary = secondary
        self.normalizer = normalizer
        self.clock = clock
    }

    /// NSOpenPanel を path へ移動させ、autoConfirm なら「開く」も押す。
    /// - Throws: 失敗時は `InjectionError`、キャンセル時は `CancellationError`。
    ///   autoConfirm で「開く」を押す前にパネルが消えた場合は、`.panelGone` ではなく `.panelGoneBeforeConfirm`。
    public func run(path: String, autoConfirm: Bool) async throws {
        await gate.enter()
        defer { gate.leave() }
        do {
            try await inject(path: path, autoConfirm: autoConfirm)
        } catch InjectionError.panelGone where autoConfirm {
            // 自動確定中の panelGone は、AppCoordinator が「開く」で閉じた成功とみなして履歴に残す。
            // 「開く」を押した後の消滅はここまで届かず成功で返るため、届いたものは押す前の消滅として区別する
            throw InjectionError.panelGoneBeforeConfirm
        }
    }

    private func inject(path: String, autoConfirm: Bool) async throws {
        try Task.checkCancellation()

        let normalizedPath = normalizer.normalize(path)
        try await InjectionTargetCheck.capture(targetGuard, on: ElapsedTimeline(clock: clock))
        do {
            try await primary.run(path: normalizedPath, autoConfirm: autoConfirm)
        } catch let error as InjectionError {
            guard case .timeout(let step) = error, Self.fallbackSteps.contains(step) else {
                throw error
            }
            try Task.checkCancellation()
            try await secondary.run(path: normalizedPath, autoConfirm: autoConfirm, fallingBackFrom: error)
        }
    }
}
