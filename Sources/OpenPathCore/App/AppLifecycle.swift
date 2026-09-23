/// AppLifecycle が起動・終了の段階ごとに呼ぶ、各モジュールの開始と停止（実体は OpenPathMac の AppComposition）。
@MainActor
public protocol AppLifecycleServices: AnyObject {
    /// 設定ファイルを読み込む（ConfigStore.start）。候補の構築やホットキーは読み込んだ設定で始めるため、最初に待つ。
    func loadConfiguration() async
    /// 候補の構築と、設定の変更の反映を始める。
    func startCandidateIndexing()
    /// パネルの監視（PanelWatcher）を始める・止める。
    func setPanelWatching(_ isActive: Bool)
    /// パレットを再表示するホットキーを登録する・解除する。
    func setHotkeyRegistered(_ isRegistered: Bool)
    /// 終了処理（履歴の保存、候補の構築と設定の監視の停止）。1 度だけ呼ぶ。
    func shutDown()
}

/// アプリの起動から終了までの段階と、各モジュールを始める・止める順番（ARCH-001 §3、DSN-001 §6）。
///
/// - 起動: 設定の読み込み → 候補の構築 → パネルの監視 → ホットキー。
///   パネルの監視はアクセシビリティ権限があるときだけ始め、権限の付与・取り消しに合わせて始める・止める。
///   権限が無いまま AX を呼んでも失敗するだけで、パレットを出せないため（UX-001 §5）。
/// - 終了: パネルの監視 → ホットキーを止めてから終了処理をする。設定の読み込み中に終了した場合は、読み込み後に何も始めない。
///
/// 各モジュールへの呼び出しは状態が変わったときだけ行い、同じ開始・停止を重ねない。
@MainActor
public final class AppLifecycle {
    public enum Phase: Equatable, Sendable {
        case notLaunched
        /// 設定の読み込み中
        case launching
        case running
        case terminated
    }

    public private(set) var phase = Phase.notLaunched
    /// 最後に知らされたアクセシビリティ権限の状態
    public private(set) var permission: AccessibilityPermissionStatus
    /// パネルを監視中か
    public private(set) var isPanelWatching = false
    /// ホットキーを登録中か
    public private(set) var isHotkeyRegistered = false

    /// 所有者（AppComposition）が services を兼ねるため、循環参照にならないよう弱参照にする
    private weak var services: (any AppLifecycleServices)?

    /// - Parameters:
    ///   - services: 各モジュールの開始と停止。弱参照で持つため、呼び出し側で保持すること。
    ///   - permission: 起動時のアクセシビリティ権限の状態。
    public init(services: any AppLifecycleServices, permission: AccessibilityPermissionStatus) {
        self.services = services
        self.permission = permission
    }

    private var shouldWatchPanels: Bool {
        phase == .running && permission.isGranted
    }

    private var shouldRegisterHotkey: Bool {
        phase == .running
    }

    /// 起動する。設定の読み込みを待ってから、候補の構築・パネルの監視・ホットキーを始める。2 回目以降は何もしない。
    public func launch() async {
        guard phase == .notLaunched else { return }
        phase = .launching
        await services?.loadConfiguration()
        // 読み込みを待つ間に終了した場合は何も始めない
        guard phase == .launching else { return }
        services?.startCandidateIndexing()
        phase = .running
        Log.info("起動処理を終えました（アクセシビリティ権限: \(permission.isGranted ? "あり" : "なし")）")
        reconcile()
    }

    /// アクセシビリティ権限の変化を反映する（`AccessibilityPermissionMonitor.onChange` から呼ぶ）。
    public func permissionDidChange(_ newPermission: AccessibilityPermissionStatus) {
        guard phase != .terminated, newPermission != permission else { return }
        permission = newPermission
        Log.info(newPermission.isGranted ? "アクセシビリティ権限が付与されました" : "アクセシビリティ権限が取り消されました")
        reconcile()
    }

    /// 終了する。パネルの監視とホットキーを止めてから終了処理をする。2 回目以降は何もしない。
    public func terminate() {
        guard phase != .terminated else { return }
        phase = .terminated
        reconcile()
        services?.shutDown()
    }

    /// あるべき状態との差だけ、パネルの監視 → ホットキーの順に始める・止める。
    private func reconcile() {
        if isPanelWatching != shouldWatchPanels {
            isPanelWatching = shouldWatchPanels
            services?.setPanelWatching(isPanelWatching)
        }
        if isHotkeyRegistered != shouldRegisterHotkey {
            isHotkeyRegistered = shouldRegisterHotkey
            services?.setHotkeyRegistered(isHotkeyRegistered)
        }
    }
}
