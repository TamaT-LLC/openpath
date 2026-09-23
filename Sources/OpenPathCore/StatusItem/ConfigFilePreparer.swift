import Foundation

/// 「設定ファイルを開く…」の前に設定ファイルを用意する（FR-CONFIG-02）。
///
/// 設定ファイルは起動時に ConfigStore が生成するが、生成に失敗した場合や起動後に削除された場合は存在しない。
/// その状態で開こうとしたときに何も起きないと利用者が困るため、既定の内容で作り直してから開く。
/// 作り直したファイルは ConfigStore の監視が拾って読み込み直す。
public enum ConfigFilePreparer {
    /// ファイルが無ければディレクトリごと作り、`defaultContents` の内容で生成する。既存のファイルは上書きしない。
    /// - Parameters:
    ///   - fileURL: 設定ファイルの場所（`ConfigStore.fileURL`）
    ///   - defaultContents: 生成するときの内容。ファイルがあれば呼ばない
    public static func prepare(
        fileURL: URL,
        defaultContents: () -> String
    ) throws(ConfigFilePreparationError) -> ConfigFilePreparation {
        let path = fileURL.path(percentEncoded: false)
        guard !FileManager.default.fileExists(atPath: path) else { return .existing }

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            throw .creationFailed(path: path, reason: error.localizedDescription)
        }
        do {
            // 存在確認の後に作られたファイルや、リンク先の無いシンボリックリンクを上書きしない
            try Data(defaultContents().utf8).write(to: fileURL, options: .withoutOverwriting)
        } catch CocoaError.fileWriteFileExists {
            return .existing
        } catch {
            throw .creationFailed(path: path, reason: error.localizedDescription)
        }
        return .created
    }
}

/// `ConfigFilePreparer.prepare(fileURL:defaultContents:)` の結果。
public enum ConfigFilePreparation: Sendable, Equatable {
    /// もともとあった
    case existing
    /// 既定の内容で生成した
    case created
}

/// 設定ファイルを用意できなかった理由。
public enum ConfigFilePreparationError: Error, Sendable, Equatable {
    /// 設定ファイルが無く、生成しようとして失敗した
    case creationFailed(path: String, reason: String)
}

extension ConfigFilePreparationError: CustomStringConvertible {
    /// ダイアログに出す説明。利用者が場所を確かめられるようパスを含める（ログには出さないこと）
    public var description: String {
        switch self {
        case .creationFailed(let path, let reason):
            "設定ファイル \(path) を作成できません（\(reason)）"
        }
    }
}
