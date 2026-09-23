/// ファイル一覧の先頭の行から、パネルの選択モードを推定する（DSN-001 §2.3）。
///
/// `canChooseDirectories` のみのパネル（Claude Desktop の「フォルダを追加」など）では、ディレクトリ以外の行が選べなくなる。
/// ファイルを選べるパネルでも、種類で絞り込むパネル（`allowedContentTypes`）では一部のファイルが選べなくなるため、
/// 選べるファイルが 1 つでもあれば「ファイルも選べる」とする。
public enum PanelSelectionModeEstimator {
    /// 推定に使う先頭の行数（DSN-001 §2.3）。
    public static let sampledRowCount = 20

    /// 先頭 `sampledRowCount` 行のうち、ディレクトリ以外の行（URL を読めず種類の分からない行は除く）を調べる。
    /// - 選べる行が 1 つでもあれば `.filesSelectable`
    /// - すべて選べなければ `.directoriesOnly`
    /// - ディレクトリ以外の行がない、または選べるか分からない行があれば `.undetermined`
    public static func estimate(_ rows: [FileListRow]) -> PanelSelectionMode {
        var hasUnselectableFile = false
        var hasUndeterminedFile = false
        for row in rows.prefix(sampledRowCount) where row.isDirectory == false {
            switch row.isSelectable {
            case true?:
                return .filesSelectable
            case false?:
                hasUnselectableFile = true
            case nil:
                hasUndeterminedFile = true
            }
        }
        guard hasUnselectableFile, !hasUndeterminedFile else { return .undetermined }
        return .directoriesOnly
    }
}
