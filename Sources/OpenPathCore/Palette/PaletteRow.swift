import Foundation

/// パレットの候補 1 行分の表示用モデル（FR-PALETTE-03）。
///
/// 候補インデックスの `Candidate`（#13）とファジーマッチの positions から作る。
/// ビューに必要な値だけを持ち、候補ソースや frecency には依存しない。
public struct PaletteRow: Identifiable, Equatable, Sendable {
    /// 表示名（ディレクトリ名、ファイルの場合はファイル名）
    public let name: String
    /// 正規化済みの絶対パス。確定時に NSOpenPanel へ注入する値でもある
    public let path: String
    /// 最終使用日時。履歴にない候補は nil
    public let lastUsed: Date?
    /// 候補の種類。行のアイコンをフォルダと書類で描き分ける
    public let isDirectory: Bool
    /// `name` 内のマッチ位置（Character オフセット）
    public let nameHighlights: [Int]
    /// `path` 内のマッチ位置（Character オフセット）
    public let pathHighlights: [Int]

    /// 候補インデックスで同一パスは 1 件に統合されるため、パスで識別する。
    public var id: String { path }

    public init(
        name: String,
        path: String,
        lastUsed: Date?,
        isDirectory: Bool = true,
        nameHighlights: [Int] = [],
        pathHighlights: [Int] = []
    ) {
        self.name = name
        self.path = path
        self.lastUsed = lastUsed
        self.isDirectory = isDirectory
        self.nameHighlights = nameHighlights
        self.pathHighlights = pathHighlights
    }
}
