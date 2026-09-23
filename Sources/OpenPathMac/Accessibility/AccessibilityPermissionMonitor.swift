import OpenPathCore

/// アクセシビリティ権限の変化を監視する（DSN-001 §6）。
///
/// 権限の付与・取り消しを通知するシステムイベントは無いため、`AccessibilityPermissionPolicy.pollingInterval`（5 秒）
/// ごとに状態を確認し、直前の状態から変化したときだけ `onChange` を呼ぶ。
/// 変化の判定とポーリングの間隔は OpenPathCore の `ValueChangePoller` でテストしている。
@MainActor
public final class AccessibilityPermissionMonitor {
    public typealias StatusProvider = @Sendable () -> AccessibilityPermissionStatus

    /// 最後に確認した権限の状態。
    public private(set) var status: AccessibilityPermissionStatus
    /// 状態が変化したときに MainActor で呼ばれる。
    public var onChange: ((AccessibilityPermissionStatus) -> Void)?

    public var isMonitoring: Bool {
        monitoringTask != nil
    }

    private let poller: ValueChangePoller<AccessibilityPermissionStatus>
    private var monitoringTask: Task<Void, Never>?

    /// 生成時に現在の状態を確認する。監視は `start()` で始める。
    /// - Parameters:
    ///   - interval: 状態を確認する間隔。
    ///   - statusProvider: 状態の確認方法。既定はシステムの許可ダイアログを出さない確認。
    public init(
        interval: Duration = AccessibilityPermissionPolicy.pollingInterval,
        statusProvider: @escaping StatusProvider = { AccessibilityPermission.currentStatus() }
    ) {
        status = statusProvider()
        poller = ValueChangePoller(interval: interval, read: statusProvider)
    }

    deinit {
        monitoringTask?.cancel()
    }

    /// 監視を始める。監視中なら何もしない。
    /// 停止中に状態が変わっていた場合も、再開後の最初の確認で通知する。
    public func start() {
        guard monitoringTask == nil else { return }
        let changes = poller.changes(from: status)
        monitoringTask = Task { [weak self] in
            for await newStatus in changes {
                self?.apply(newStatus)
            }
        }
    }

    /// 監視を止める。
    public func stop() {
        monitoringTask?.cancel()
        monitoringTask = nil
    }

    private func apply(_ newStatus: AccessibilityPermissionStatus) {
        status = newStatus
        onChange?(newStatus)
    }
}
