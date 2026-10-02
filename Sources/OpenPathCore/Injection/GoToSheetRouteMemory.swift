/// 注入先のアプリの識別。経路の記憶（`GoToSheetRouteMemory`）の鍵にする。
/// bundle id があればそれで見分け（アプリを再起動しても同じ注入先とみなす）、無ければ pid で見分ける。
public struct InjectionTargetIdentity: Hashable, Sendable {
    private enum Key: Hashable, Sendable {
        case bundleIdentifier(String)
        case processID(Int32)
    }

    private let key: Key

    /// - Parameters:
    ///   - bundleIdentifier: 注入先のアプリの bundle id。nil か空なら pid で見分ける。
    ///   - processID: 注入先のアプリのプロセス ID。
    public init(bundleIdentifier: String?, processID: Int32) {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            key = .bundleIdentifier(bundleIdentifier)
        } else {
            key = .processID(processID)
        }
    }
}

/// 注入先のプロセスへ送った ⌘⇧G（`GoToSheetOpener` の ①）で移動先シートが出なかった注入先を、プロセスの中で覚える（Issue #29）。
///
/// macOS 26 の VS Code のリモートのパネルでは、注入先のプロセスへ送ったキーがパネルに届かない。毎回 ① の待ちを払わないよう、
/// 次の注入では ① を飛ばして ②（システム経由の /）・③（システム経由の ⌘⇧G）から始める。
/// 覚えた注入先で ②・③ でもシートが出なければ忘れ、次の注入はまた ① から試す。① の待ちの後に遅れて出たシートを
/// ②・③ の待ちで拾った場合（① は届いていた）にも覚えてしまうため、覚えたままシステム経由のキーが横取りされ続けないようにする。
/// 永続化はしない（アプリやパネルの更新で振る舞いが変わりうるため、起動のたびに ① から確かめ直す）。
@MainActor
public final class GoToSheetRouteMemory {
    private var targetsMissingTargetProcessRoute: Set<InjectionTargetIdentity> = []

    public init() {}

    /// ① を飛ばして ②・③ から始めるか。識別できない注入先（nil）では飛ばさない。
    public func skipsTargetProcessRoute(for target: InjectionTargetIdentity?) -> Bool {
        guard let target else { return false }
        return targetsMissingTargetProcessRoute.contains(target)
    }

    /// ① でシートが出なかったことを覚える。識別できない注入先（nil）は覚えない。
    public func recordTargetProcessRouteMissed(for target: InjectionTargetIdentity?) {
        guard let target else { return }
        targetsMissingTargetProcessRoute.insert(target)
    }

    /// 覚えた注入先を忘れる（次の注入は ① から試す）。
    public func forget(_ target: InjectionTargetIdentity?) {
        guard let target else { return }
        targetsMissingTargetProcessRoute.remove(target)
    }
}
