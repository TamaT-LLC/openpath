/// パネルの選択モードの推定結果（DSN-001 §2.3、FR-SOURCE-05）。
public enum PanelSelectionMode: Equatable, Sendable {
    /// ファイルも選べる（選べるファイルの行があった）。
    case filesSelectable
    /// フォルダのみ選べる（`canChooseDirectories` のみのパネル）。ディレクトリ以外の行がすべて選べなかった。
    case directoriesOnly
    /// 推定できない（行がない、ディレクトリしかない、行の状態を読めない）。
    case undetermined

    /// `PanelContext.isDirectoriesOnly` に入れる値。フォルダのみと推定できたときだけ true にし、
    /// それ以外（ファイルも選べる、推定できない）は設定 include_files に従わせる。
    public var isDirectoriesOnly: Bool {
        self == .directoriesOnly
    }
}

/// 選択モードの推定結果と、推定に使った行の内訳（DSN-001 §2.3）。
///
/// 「推定できない」の理由をログ（`panel detected` 等）で見分けるために内訳を持つ。
/// - 行が 0: 一覧が空・読み込み前・行を読めなかった（読み取りの失敗を含む）
/// - 行はあるがディレクトリ以外が 0: 今のフォルダに（読んだ範囲では）ディレクトリしかない
/// - ディレクトリ以外があるのに推定できない: 選べるかどうか（文字色・AXEnabled）を読めなかった
public struct PanelSelectionEstimate: Equatable, Sendable {
    /// 行を読めなかった（ファイル一覧がない、読み取りに失敗した）ときの結果。
    public static let notSampled = PanelSelectionEstimate(
        mode: .undetermined,
        sampledRowCount: 0,
        sampledDirectoryCount: 0,
        sampledFileCount: 0
    )

    public let mode: PanelSelectionMode
    /// 推定に使った行の数（種類の分からない行を含む）。
    public let sampledRowCount: Int
    /// そのうちディレクトリの行の数。
    public let sampledDirectoryCount: Int
    /// そのうちディレクトリ以外の行の数。
    public let sampledFileCount: Int

    public init(mode: PanelSelectionMode, sampledRowCount: Int, sampledDirectoryCount: Int, sampledFileCount: Int) {
        self.mode = mode
        self.sampledRowCount = sampledRowCount
        self.sampledDirectoryCount = sampledDirectoryCount
        self.sampledFileCount = sampledFileCount
    }
}
