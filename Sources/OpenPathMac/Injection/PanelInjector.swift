import AppKit
import ApplicationServices

import OpenPathCore

/// NSOpenPanel へのパス注入（ARCH-001 §4 PanelInjector）。
///
/// 手順・待機・タイムアウト・フォールバック・ペーストボードの復元は OpenPathCore の `PathInjectionFlow` が持ち、
/// ここでは NSPasteboard / CGEvent / AX / NSWorkspace のアダプタを組み立てて渡すだけにする。
/// - パスの正規化（DSN-001 §4）
/// - 主方式（⌘⇧G + ペースト、§3.1）と、シートが出ない・貼り付けられない場合の副方式（AX 直接セット、§3.2）
/// - キー入力（⌘A / ⌘V / Return）の前の、移動先シートの入力欄のフォーカスの待ち合わせ（`GoToFieldFocusWait`、Issue #74）
/// - 確定（Return・「移動」）の前の、移動先シートの入力欄と候補の選択の確認（`GoToSheetSubmitGate`、Issue #74）
/// - auto_confirm / Cmd+Enter の「開く」の押下（§3.1 ステップ 8）
/// - キー操作・AX 操作の直前ごとの注入先の確認（別のアプリへの誤送出の防止）
///
/// 全体のタイムアウト（1.5 秒）は AppCoordinator が持ち、超えたら注入の Task をキャンセルする。
/// ここではキャンセルに応じてキー操作を止め、ペーストボードを戻して `CancellationError` で戻る。
@MainActor
public final class PanelInjector: PathInjecting {
    /// 注入を終えてから移動後の現在地を読むまでの待ち時間。移動先シートが閉じ、パネルの表示が移動先に変わるのを待つ。
    private static let locationReadDelay: Duration = .milliseconds(600)

    private let flow: PathInjectionFlow
    private let targetWindow: InjectionTargetWindow

    /// - Parameters:
    ///   - prepareForKeyEvents: キー操作を送る前に呼ぶ。パレットにキーウィンドウを手放させてから戻ること。
    ///     パレットがキーのままだと ⌘⇧G などがパレットに届いてしまうため、配線漏れを防ぐよう既定値を持たせない。
    ///   - pasteboard: 注入に使うペーストボード。
    ///   - clock: 待機に使う。
    public init(
        prepareForKeyEvents: @escaping PathInjectionHooks.PrepareForKeyEvents,
        pasteboard: NSPasteboard = .general,
        clock: any Clock<Duration> = ContinuousClock()
    ) {
        let targetGuard = InjectionTargetGuard()
        // シートの判定と要素探しは、注入の最初に記録した注入先に対して行う（途中でフォーカスが移っても別のアプリ・ウィンドウを走査しない）
        let targetProcessID: InjectionTargetProcessID = { [targetGuard] in targetGuard.targetProcessID }
        let targetWindow: InjectionTargetWindow = { [targetGuard] in targetGuard.targetWindow }
        let keyboard = KeyboardEventPoster()
        let goToFieldLocator = GoToFieldLocator(targetWindow: targetWindow)
        let submitGate = GoToSheetSubmitGate(locator: goToFieldLocator, clock: clock)
        let fieldFocus = GoToFieldFocusWait(locator: goToFieldLocator, clock: clock)
        let autoConfirm = OpenButtonAutoConfirm(
            locator: OpenButtonLocator(targetWindow: targetWindow),
            targetGuard: targetGuard,
            clock: clock
        )
        flow = PathInjectionFlow(
            targetGuard: targetGuard,
            primary: GoToFolderPasteSequencer(
                pasteboard: SystemPasteboard(pasteboard: pasteboard),
                keyboard: keyboard,
                sheetDetector: GoToSheetDetector(frontmostProcessID: targetProcessID),
                targetGuard: targetGuard,
                fieldFocus: fieldFocus,
                submitGate: submitGate,
                hooks: PathInjectionHooks(prepareForKeyEvents: prepareForKeyEvents, didSubmitGoToSheet: autoConfirm.hook),
                clock: clock
            ),
            secondary: GoToFieldDirectEntry(
                locator: goToFieldLocator,
                targetGuard: targetGuard,
                keyboard: keyboard,
                prepareForKeyEvents: prepareForKeyEvents,
                submitGate: submitGate,
                fieldFocus: fieldFocus,
                didSubmit: autoConfirm.hook,
                clock: clock
            ),
            clock: clock
        )
        self.targetWindow = targetWindow
    }

    public func inject(path: String, autoConfirm: Bool) async throws {
        // 権限が無いと CGEvent は黙って捨てられ、600ms 待った末にシート待ちのタイムアウトになってしまうため先に判定する。
        // 他アプリへの AX 呼び出しは権限が無くても apiDisabled ではなく cannotComplete を返すため、エラーコードでなく状態で判定する。
        guard AccessibilityPermission.currentStatus().isGranted else {
            throw InjectionError.axError(code: AXError.apiDisabled.rawValue)
        }
        try await flow.run(path: path, autoConfirm: autoConfirm)
        if Log.isDebugEnabled, !autoConfirm {
            logLocationAfterInjection()
        }
    }

    /// 移動後にパネルが表示している現在地（フォルダの表示名）を debug ログに残す（Issue #74 の切り分け用）。
    /// 注入の結果を待たせないよう、注入を終えてから別の Task で読む。自動確定ではパネルが閉じるため読まない。
    private func logLocationAfterInjection() {
        // 次の注入が注入先を記録し直す前に、この注入の注入先を控えておく
        guard let window = targetWindow() else { return }
        Task { @MainActor in
            try? await Task.sleep(for: Self.locationReadDelay)
            guard let name = await PanelLocationReader.displayedFolderName(in: window) else {
                Log.debug("移動後のパネルの現在地を読めませんでした")
                return
            }
            Log.debugPath("移動後のパネルの現在地（表示名）", path: name)
        }
    }
}
