/// AppCoordinator の注入の開始と、注入の失敗の記憶（#94・#101）の診断。debug ログに出す。
///
/// 実機 QA（INJ-01、表示中のタイムアウト）で、失敗を覚えた・同じパネルの再通知で出し直した・忘れた（理由）・
/// 再試行したことを、ログの行で判定するためのもの。パネル id・失敗の種類・理由だけを持ち、確定したパスは持たない。
public enum CoordinatorDiagnostic: Equatable, Sendable {
    /// 確定を受けて注入を始めた。isRetry は失敗を表示しているパレットからの確定（再試行）か
    case injectionStarted(panelID: PanelContext.ID, isAutoConfirm: Bool, isRetry: Bool)
    /// パネルを見失った（またはタイムアウトした）ため、同じパネルの再通知で出し直す失敗として覚えた
    case failureRemembered(panelID: PanelContext.ID, failure: FailureKind, cause: RememberCause)
    /// 同じパネルの再通知でパレットを出し直し、覚えていた失敗を出した
    case failureReshown(panelID: PanelContext.ID, failure: FailureKind)
    /// 覚えていた（または表示していた）失敗を忘れた
    case failureForgotten(panelID: PanelContext.ID, failure: FailureKind, reason: ForgetReason)

    /// 失敗の種類。エラーの説明文（パスを含み得る）は持たない。
    public enum FailureKind: Equatable, Sendable {
        /// 注入の失敗。AppCoordinator の全体タイムアウトは `.timeout(step: .overall)`
        case injection(InjectionError)
        /// InjectionError 以外の失敗
        case unknown

        public init(_ error: any Error) {
            self = (error as? InjectionError).map(Self.injection) ?? .unknown
        }

        /// ログに出す表記（例: `targetNotFrontmost`、`timeout(overall)`、`axError(-25204)`）
        public var logLabel: String {
            guard case .injection(let error) = self else { return "unknown" }
            switch error {
            case .timeout(let step):
                return "timeout(\(step.rawValue))"
            case .axError(let code):
                return "axError(\(code))"
            case .panelGone:
                return "panelGone"
            case .pasteboardRestoreFailed:
                return "pasteboardRestoreFailed"
            case .targetNotFrontmost:
                return "targetNotFrontmost"
            case .panelGoneBeforeConfirm:
                return "panelGoneBeforeConfirm"
            }
        }
    }

    /// 失敗を覚えた状況。
    public enum RememberCause: String, Equatable, Sendable {
        /// 注入の途中でパネルを見失い（アプリの切り替え等）、注入を打ち切った（#94）
        case panelGoneWhileInjecting
        /// 失敗を表示していたパレットのパネルを見失った（#94・#101）
        case panelGoneWhileShowingFailure
        /// パレットの表示中に注入が全体タイムアウトした。エラーを出したパレットは残る（#101）
        case timedOut
        /// 自動確定でパネルが消えた後、「開く」まで進まずに注入が終わった（失敗・タイムアウト。#94）
        case finishedAfterPanelGone
    }

    /// 失敗を忘れた理由。
    public enum ForgetReason: String, Equatable, Sendable {
        /// 別のパネルのパレットを出した
        case otherPanel
        /// ホットキーでパレットを出し直した
        case hotkey
        /// Esc でパレットを閉じた
        case escape
        /// 失敗を表示しているパレットから確定し、注入をやり直した
        case retry
        /// クリップボードを戻せなかった失敗を出したまま、パネルが閉じた（自動確定の「開く」で閉じたとみなす）
        case panelClosed
    }

    /// debug ログの文言。例:
    /// - `coordinator injection start (id: open-panel-3, autoConfirm: false, retry: false)`
    /// - `coordinator failure remembered (id: open-panel-3, failure: targetNotFrontmost, cause: panelGoneWhileInjecting)`
    /// - `coordinator failure reshown (id: open-panel-3, failure: targetNotFrontmost)`
    /// - `coordinator failure forgotten (id: open-panel-3, failure: targetNotFrontmost, reason: escape)`
    public var logMessage: String {
        switch self {
        case .injectionStarted(let panelID, let isAutoConfirm, let isRetry):
            "coordinator injection start (id: \(panelID.rawValue), autoConfirm: \(isAutoConfirm), retry: \(isRetry))"
        case .failureRemembered(let panelID, let failure, let cause):
            "coordinator failure remembered (id: \(panelID.rawValue), failure: \(failure.logLabel), cause: \(cause.rawValue))"
        case .failureReshown(let panelID, let failure):
            "coordinator failure reshown (id: \(panelID.rawValue), failure: \(failure.logLabel))"
        case .failureForgotten(let panelID, let failure, let reason):
            "coordinator failure forgotten (id: \(panelID.rawValue), failure: \(failure.logLabel), reason: \(reason.rawValue))"
        }
    }

    /// 既定の報告先。debug ログに出す（リリースビルドの既定の info では出さない）。
    public static func log(_ diagnostic: CoordinatorDiagnostic) {
        Log.debug(diagnostic.logMessage)
    }
}
