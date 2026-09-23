import AppKit
import ApplicationServices

import OpenPathCore

/// NSOpenPanel へのパス注入（ARCH-001 §4 PanelInjector）。
///
/// 主方式（⌘⇧G + ペースト、DSN-001 §3.1）の手順・待機・タイムアウト・ペーストボードの復元は
/// OpenPathCore の `GoToFolderPasteSequencer` が持ち、ここでは NSPasteboard / CGEvent / AX のアダプタを組み立てて渡すだけにする。
///
/// 全体のタイムアウト（1.5 秒）は AppCoordinator が持ち、超えたら注入の Task をキャンセルする。
/// ここではキャンセルに応じてキー操作を止め、ペーストボードを戻して `CancellationError` で戻る。
@MainActor
public final class PanelInjector: PathInjecting {
    private let sequencer: GoToFolderPasteSequencer

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
        sequencer = GoToFolderPasteSequencer(
            pasteboard: SystemPasteboard(pasteboard: pasteboard),
            keyboard: KeyboardEventPoster(),
            sheetDetector: GoToSheetDetector(),
            hooks: PathInjectionHooks(
                prepareForKeyEvents: prepareForKeyEvents,
                // TODO: #25 で auto_confirm 時に 300ms 待ってパネルの「開く」ボタンを AXPress する処理を差し込む
                didSubmitGoToSheet: { _ in }
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
        try await sequencer.run(path: path, autoConfirm: autoConfirm)
    }
}
