import Foundation
import ServiceManagement

import OpenPathCore

/// `SMAppService.mainApp` によるログイン時に起動（FR-CONFIG-03）。
///
/// SMAppService.mainApp は .app バンドルを登録するため、`swift run` のようにバンドル外の実行ファイルでは機能しない。
/// その場合は SMAppService に問い合わせず `.unavailable` を返し、メニューの項目を選べないようにする。
/// 登録状態はシステム設定で利用者が変えることもあるため保持せず、読むたびに問い合わせる。
public final class SMAppServiceLoginItem: LoginItemRegistering {
    private let service: SMAppService
    private let isAvailable: Bool

    /// - Parameter bundleURL: 実行中のバンドルの場所。.app でなければ登録・解除は行わない
    public init(service: SMAppService = .mainApp, bundleURL: URL = Bundle.main.bundleURL) {
        self.service = service
        isAvailable = LoginItemAvailability.isAppBundle(bundleURL)
    }

    public var status: LoginItemStatus {
        guard isAvailable else { return .unavailable }
        switch service.status {
        case .enabled: return .enabled
        case .notRegistered: return .notRegistered
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    public func register() throws {
        try service.register()
    }

    public func unregister() throws {
        try service.unregister()
    }

    public func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
