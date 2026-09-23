import Foundation

/// ログイン時に起動（`SMAppService.mainApp`）の登録状態（FR-CONFIG-03）。
/// Core から ServiceManagement に依存しないよう、`SMAppService.Status` を写した値で扱う。
public enum LoginItemStatus: Sendable, Equatable {
    /// 登録済みで、ログイン時に起動する
    case enabled
    /// 未登録
    case notRegistered
    /// 登録済みだが、システム設定の「ログイン項目」で利用者の許可が必要
    case requiresApproval
    /// サービスが見つからない（未登録の一形態として扱い、登録を試せるようにする）
    case notFound
    /// .app バンドル外（`swift run` 等）で動いており、SMAppService.mainApp を使えない
    case unavailable

    /// メニューのチェック表示
    public var checkState: StatusMenuCheckState {
        switch self {
        case .enabled: .on
        case .requiresApproval: .mixed
        case .notRegistered, .notFound, .unavailable: .off
        }
    }

    /// メニューで選んだときに行う操作。操作できなければ nil
    public var toggleCommand: LoginItemCommand? {
        switch self {
        // 承認待ちは登録済みの一形態なので、選んだら登録を取り消す
        case .enabled, .requiresApproval: .unregister
        case .notRegistered, .notFound: .register
        case .unavailable: nil
        }
    }

    /// メニュー項目に添える補足
    var note: String? {
        switch self {
        case .requiresApproval: StatusMenuText.loginItemRequiresApproval
        case .unavailable: StatusMenuText.loginItemUnavailable
        case .enabled, .notRegistered, .notFound: nil
        }
    }
}

/// ログイン時に起動の登録・解除。
public enum LoginItemCommand: Sendable, Equatable {
    case register
    case unregister
}

/// SMAppService.mainApp を使えるかの判定。
public enum LoginItemAvailability {
    private static let appBundleExtension = "app"

    /// `Bundle.main.bundleURL` が .app バンドルか。
    /// SMAppService.mainApp は .app バンドルを登録するため、`swift run` のようにバンドル外の実行ファイルでは機能しない。
    public static func isAppBundle(_ bundleURL: URL) -> Bool {
        bundleURL.pathExtension.lowercased() == appBundleExtension
    }
}
