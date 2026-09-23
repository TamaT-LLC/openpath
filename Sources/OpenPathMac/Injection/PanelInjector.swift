import AppKit
import ApplicationServices

import OpenPathCore

/// NSOpenPanel へのパス注入（ARCH-001 §4 PanelInjector）。
///
/// 手順・待機・タイムアウト・フォールバック・ペーストボードの復元は OpenPathCore の `PathInjectionFlow` が持ち、
/// ここでは NSPasteboard / CGEvent / AX / NSWorkspace のアダプタを組み立てて渡すだけにする。
/// - パスの正規化（DSN-001 §4）
/// - 主方式（⌘⇧G + ペースト、§3.1）と、シートが出ない・貼り付けられない場合の副方式（AX 直接セット、§3.2）
/// - auto_confirm / Cmd+Enter の「開く」の押下（§3.1 ステップ 8）
/// - キー操作・AX 操作の直前ごとの注入先の確認（別のアプリへの誤送出の防止）
///
/// 全体のタイムアウト（1.5 秒）は AppCoordinator が持ち、超えたら注入の Task をキャンセルする。
/// ここではキャンセルに応じてキー操作を止め、ペーストボードを戻して `CancellationError` で戻る。
@MainActor
public final class PanelInjector: PathInjecting {
    private let flow: PathInjectionFlow

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
        let autoConfirm = OpenButtonAutoConfirm(
            locator: OpenButtonLocator(targetWindow: targetWindow),
            targetGuard: targetGuard,
            clock: clock
        )
        flow = PathInjectionFlow(
            targetGuard: targetGuard,
            primary: GoToFolderPasteSequencer(
                pasteboard: SystemPasteboard(pasteboard: pasteboard),
                keyboard: KeyboardEventPoster(),
                sheetDetector: GoToSheetDetector(frontmostProcessID: targetProcessID),
                targetGuard: targetGuard,
                hooks: PathInjectionHooks(prepareForKeyEvents: prepareForKeyEvents, didSubmitGoToSheet: autoConfirm.hook),
                clock: clock
            ),
            secondary: GoToFieldDirectEntry(
                locator: GoToFieldLocator(targetWindow: targetWindow),
                targetGuard: targetGuard,
                didSubmit: autoConfirm.hook,
                clock: clock
            ),
            clock: clock
        )
    }

    public func inject(path: String, autoConfirm: Bool) async throws {
        // 権限が無いと CGEvent は黙って捨てられ、600ms 待った末にシート待ちのタイムアウトになってしまうため先に判定する。
        // 他アプリへの AX 呼び出しは権限が無くても apiDisabled ではなく cannotComplete を返すため、エラーコードでなく状態で判定する。
        guard AccessibilityPermission.currentStatus().isGranted else {
            throw InjectionError.axError(code: AXError.apiDisabled.rawValue)
        }
        try await flow.run(path: path, autoConfirm: autoConfirm)
    }
}
