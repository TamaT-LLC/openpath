import Foundation

/// NSOpenPanel へのパス注入の全体（DSN-001 §3〜§4）。
///
/// 1. パスを正規化する（§4）
/// 2. 最前面アプリとそのウィンドウを注入先として記録する（以降のキー操作・AX 操作の直前ごとに確かめる）
/// 3. 主方式（⌘⇧G + ペースト、§3.1）
/// 4. 主方式が移動先シートを見つけられない（waitSheet）か、貼り付けの操作に失敗した（waitPaste）か、
///    Return を送っても移動先シートが閉じなかった（waitSheetClose、Issue #95）ら、副方式（AX 直接セット、§3.2）
///
/// 前の注入が副方式まで終えるまで、次の注入は始めない。
/// autoConfirm で「開く」を押す前にパネルが消えたら `.panelGoneBeforeConfirm` を投げ、押した後の消滅（成功）と区別する。
/// 注入するパス（正規化の前後）・使った方式・結果を debug ログに残す（Issue #74 の切り分け用。パスは `Log.debugPath`）。
@MainActor
public final class PathInjectionFlow {
    /// 副方式へ切り替える主方式の失敗。waitSheet と waitPaste はシートの確定（Return）を送る前の失敗で、パネルはまだ移動していない。
    /// waitSheetClose は Return を送ったがシートが閉じなかった・閉じたことを確かめられなかった失敗で（Issue #95）、
    /// シートが残っていればパネルは移動していない（副方式は、シートが見つからなければ確定し直さない）。
    /// ペーストボードも、waitSheet では触れておらず、waitPaste と waitSheetClose では主方式が戻し終えている。
    static let fallbackSteps: Set<InjectionStep> = [.waitSheet, .waitPaste, .waitSheetClose]

    private let targetGuard: any InjectionTargetGuarding
    private let primary: GoToFolderPasteSequencer
    private let secondary: GoToFieldDirectEntry
    private let normalizer: InjectionPathNormalizer
    private let clock: any Clock<Duration>
    private let gate = InjectionSerialGate()
    private let saveFilename: SaveFilenamePreservation?

    /// - Parameters:
    ///   - targetGuard: primary・secondary と同じものを渡す。ここで記録した注入先を、それぞれが確かめる。
    ///   - clock: 注入先の記録の期限の計測に使う。
    public init(
        targetGuard: any InjectionTargetGuarding,
        primary: GoToFolderPasteSequencer,
        secondary: GoToFieldDirectEntry,
        normalizer: InjectionPathNormalizer = InjectionPathNormalizer(),
        saveFilename: SaveFilenamePreservation? = nil,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        self.targetGuard = targetGuard
        self.primary = primary
        self.secondary = secondary
        self.normalizer = normalizer
        self.saveFilename = saveFilename
        self.clock = clock
    }

    /// NSOpenPanel を path へ移動させ、autoConfirm なら「開く」も押す。
    /// - Throws: 失敗時は `InjectionError`、キャンセル時は `CancellationError`。
    ///   autoConfirm で「開く」を押す前にパネルが消えた場合は、`.panelGone` ではなく `.panelGoneBeforeConfirm`。
    public func run(path: String, autoConfirm: Bool, panelKind: PanelKind = .open) async throws {
        let autoConfirm = panelKind == .open && autoConfirm
        await gate.enter()
        defer { gate.leave() }
        do {
            try await inject(path: path, autoConfirm: autoConfirm, panelKind: panelKind)
        } catch InjectionError.panelGone where autoConfirm {
            // 自動確定中の panelGone は、AppCoordinator が「開く」で閉じた成功とみなして履歴に残す。
            // 「開く」を押した後の消滅はここまで届かず成功で返るため、届いたものは押す前の消滅として区別する
            throw InjectionError.panelGoneBeforeConfirm
        }
    }

    /// 保存先の実在と種別を確かめ、保存時は名前を退避して移動前後の復元まで行う。
    /// 移動失敗・キャンセル時にも同じ注入先への復元を試み、元の失敗理由を保持する。
    private func inject(path: String, autoConfirm: Bool, panelKind: PanelKind) async throws {
        try Task.checkCancellation()

        let normalizedPath = normalizer.normalize(path)
        Log.debugPath("注入するパス（確定されたパス）", path: path)
        if normalizedPath != path {
            Log.debugPath("注入するパス（正規化後）", path: normalizedPath)
        }
        if panelKind == .save {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: normalizedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw InjectionError.saveDestinationNotDirectory
            }
        }
        let timeline = ElapsedTimeline(clock: self.clock)
        try await InjectionTargetCheck.capture(targetGuard, on: timeline)
        var snapshot: (any PanelElementOperating, String)?
        if panelKind == .save {
            guard let saveFilename else { throw InjectionError.saveFilenameUnavailable }
            snapshot = try await saveFilename.capture(on: timeline)
        }
        do {
            try await navigate(path: normalizedPath, autoConfirm: autoConfirm, panelKind: panelKind, timeline: timeline)
        } catch {
            if let snapshot {
                // 後処理の失敗でペーストボード復元失敗など、元のエラーを上書きしない。
                try? await restoreFilename(snapshot, on: timeline)
            }
            throw error
        }
        if let snapshot {
            try await restoreFilename(snapshot, on: timeline)
            try Task.checkCancellation()
        }
    }

    /// キャンセルを引き継がない後処理で名前を戻す。完了まで直列化ゲートを保持し、注入先は毎回確認する。
    private func restoreFilename(_ snapshot: (any PanelElementOperating, String), on timeline: ElapsedTimeline) async throws {
        guard let saveFilename else { return }
        let cleanup = Task { @MainActor in
            try await saveFilename.restore(snapshot, targetGuard: targetGuard, on: timeline)
        }
        try await cleanup.value
    }

    /// 主方式で移動し、シート出現・貼り付け・閉鎖のタイムアウトだけ副方式へ切り替える。
    private func navigate(path normalizedPath: String, autoConfirm: Bool, panelKind: PanelKind, timeline: ElapsedTimeline) async throws {
        do {
            Log.debug("注入を主方式（⌘⇧G + ペースト）で始めます（auto_confirm: \(autoConfirm)）")
            try await primary.run(path: normalizedPath, autoConfirm: autoConfirm, panelKind: panelKind)
            Log.debug("主方式で注入しました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        } catch let error as InjectionError {
            guard case .timeout(let step) = error, Self.fallbackSteps.contains(step) else {
                Log.debug("主方式の注入に失敗しました（\(error)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
                throw error
            }
            try Task.checkCancellation()
            Log.info("主方式が \(step.rawValue) で失敗したため、副方式（AX 直接セット）へ切り替えます")
            do {
                try await secondary.run(
                    path: normalizedPath,
                    autoConfirm: autoConfirm,
                    fallingBackFrom: error,
                    keyRoute: primary.lastKeyRoute,
                    panelKind: panelKind
                )
            } catch {
                Log.debug("副方式の注入に失敗しました（\(error)、+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
                throw error
            }
            Log.debug("副方式で注入しました（+\(InjectionLogFormat.milliseconds(timeline.elapsed))）")
        }
    }
}
