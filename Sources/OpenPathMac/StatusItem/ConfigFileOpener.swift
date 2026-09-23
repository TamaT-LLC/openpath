import AppKit

import OpenPathCore

/// 「設定ファイルを開く…」（FR-CONFIG-02）。
///
/// ファイルが無ければ既定の内容で作り直し（`ConfigFilePreparer`）、.toml に関連付けられたアプリで開く。
/// 関連付けが無い環境では NSWorkspace.open が失敗するため、テキストエディットで開く。
@MainActor
struct ConfigFileOpener {
    private static let fallbackEditorBundleIdentifier = "com.apple.TextEdit"

    let fileURL: URL
    let defaultContents: () -> String
    let workspace: NSWorkspace

    /// - Parameter onFailure: 開けなかったときに、利用者に見せるダイアログの内容とともに MainActor で呼ばれる
    func open(onFailure: @escaping @MainActor (StatusItemDialog) -> Void) {
        do throws(ConfigFilePreparationError) {
            if try ConfigFilePreparer.prepare(fileURL: fileURL, defaultContents: defaultContents) == .created {
                Log.info("設定ファイルが無かったため既定の内容で作成しました")
            }
        } catch {
            Log.warning("設定ファイルを作成できませんでした")
            onFailure(.configFileOpenFailure(reason: error.description))
            return
        }

        Log.debugPath("設定ファイルを開きます", path: fileURL.path(percentEncoded: false))
        if workspace.urlForApplication(toOpen: fileURL) != nil, workspace.open(fileURL) {
            return
        }
        openWithFallbackEditor(onFailure: onFailure)
    }

    private func openWithFallbackEditor(onFailure: @escaping @MainActor (StatusItemDialog) -> Void) {
        guard let editorURL = workspace.urlForApplication(withBundleIdentifier: Self.fallbackEditorBundleIdentifier) else {
            Log.warning("設定ファイルを開くアプリが見つかりません")
            onFailure(.configFileApplicationNotFound)
            return
        }
        let workspace = workspace
        let fileURL = fileURL
        Task { @MainActor in
            do {
                _ = try await workspace.open([fileURL], withApplicationAt: editorURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                // アプリはあるので「見つからない」ではなく起動・オープンの失敗理由を見せる。理由はパスを含み得るためログには残さない
                Log.warning("テキストエディットで設定ファイルを開けませんでした")
                onFailure(.configFileOpenFailure(reason: error.localizedDescription))
            }
        }
    }
}
