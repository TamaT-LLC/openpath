import OpenPathCore

/// AppLifecycle からの呼び出しを順番どおりに記録する。
/// 設定の読み込みはテストが `finishLoadingConfiguration()` を呼ぶまで終わらないようにもできる。
@MainActor
final class AppLifecycleServicesSpy: AppLifecycleServices {
    enum Call: Equatable {
        case loadConfiguration
        case startCandidateIndexing
        case setPanelWatching(Bool)
        case setHotkeyRegistered(Bool)
        case shutDown
    }

    private(set) var calls: [Call] = []
    private let holdsConfigurationLoading: Bool
    private var loadingContinuation: CheckedContinuation<Void, Never>?
    private let waiter = ConditionWaiter()

    /// - Parameter holdsConfigurationLoading: true なら設定の読み込みを `finishLoadingConfiguration()` まで終えない。
    init(holdsConfigurationLoading: Bool = false) {
        self.holdsConfigurationLoading = holdsConfigurationLoading
    }

    /// 設定の読み込みが始まるまで待つ。
    func waitForConfigurationLoading() async {
        await waiter.wait { self.loadingContinuation != nil }
    }

    func finishLoadingConfiguration() {
        loadingContinuation?.resume()
        loadingContinuation = nil
    }

    func loadConfiguration() async {
        calls.append(.loadConfiguration)
        guard holdsConfigurationLoading else { return }
        await withCheckedContinuation { continuation in
            loadingContinuation = continuation
            waiter.notify()
        }
    }

    func startCandidateIndexing() {
        calls.append(.startCandidateIndexing)
    }

    func setPanelWatching(_ isActive: Bool) {
        calls.append(.setPanelWatching(isActive))
    }

    func setHotkeyRegistered(_ isRegistered: Bool) {
        calls.append(.setHotkeyRegistered(isRegistered))
    }

    func shutDown() {
        calls.append(.shutDown)
    }
}
