/// 設定ファイルを読み込めなかった、または生成できなかった理由。
///
/// ConfigStore は読み込みに失敗しても直前の有効な設定を使い続け、この値を `lastError` に公開する。
/// `path` は設定ファイルの絶対パス。
public enum ConfigStoreError: Error, Equatable, Sendable {
    /// 設定ファイルが無い（起動後に削除された等）
    case fileNotFound(path: String)
    /// 設定ファイルを読めない（権限が無い、UTF-8 として解釈できない等）
    case readFailed(path: String, reason: String)
    /// TOML として解釈できない
    case parseFailed(path: String, TOMLParseError)
    /// TOML としては正しいが、値が設定として不正
    case decodeFailed(path: String, ConfigDecodingError)
    /// 設定ファイルが無く、既定値で生成しようとして失敗した
    case generationFailed(path: String, reason: String)
}

extension ConfigStoreError: CustomStringConvertible {
    /// StatusItem のバッジやログに出す説明。
    /// 失敗時に使い続ける設定は起動直後なら既定値、それ以降なら直前の有効な設定と異なるため、どちらとも書かない
    public var description: String {
        switch self {
        case .fileNotFound(let path):
            "設定ファイル \(path) が見つかりません"
        case .readFailed(let path, let reason):
            "設定ファイル \(path) を読めません（\(reason)）"
        case .parseFailed(let path, let error):
            "設定ファイル \(path) の書式が誤っているため反映していません（\(error.description)）"
        case .decodeFailed(let path, let error):
            "設定ファイル \(path) の値が誤っているため反映していません（\(error.description)）"
        case .generationFailed(let path, let reason):
            "設定ファイル \(path) を作成できません（\(reason)）。既定の設定で動作します"
        }
    }
}
