/// ファイル一覧の行から、パネルの選択モードを推定する（DSN-001 §2.3）。
///
/// `canChooseDirectories` のみのパネル（Claude Desktop の「フォルダを追加」など）では、ディレクトリ以外の行が選べなくなる。
/// ファイルを選べるパネルでも、種類で絞り込むパネル（`allowedContentTypes`）では一部のファイルが選べなくなるため、
/// 選べるファイルが 1 つでもあれば「ファイルも選べる」とする。
public enum PanelSelectionModeEstimator {
    /// 推定に使う先頭の行数（DSN-001 §2.3）。
    public static let sampledRowCount = 20
    /// 推定に使う末尾の行数（DSN-001 §2.3）。先頭の行がディレクトリばかりで推定できないときに、一覧の末尾から読む。
    /// 「フォルダを先頭に表示」の並びや、サブフォルダの多いフォルダでは、ファイルは一覧の末尾に並ぶため。
    public static let trailingSampledRowCount = 10

    /// 先頭 `sampledRowCount` 行のうち、ディレクトリ以外の行（URL を読めず種類の分からない行は除く）を調べる。
    /// - 選べる行が 1 つでもあれば `.filesSelectable`
    /// - すべて選べなければ `.directoriesOnly`
    /// - ディレクトリ以外の行がない、または選べるか分からない行があれば `.undetermined`
    public static func estimate(_ rows: [FileListRow]) -> PanelSelectionMode {
        mode(of: rows.prefix(sampledRowCount))
    }

    /// 先頭 `sampledRowCount` 行と末尾 `trailingSampledRowCount` 行を合わせて、`estimate(_ rows:)` と同じ規則で推定する。
    /// 推定に使った行の内訳も返す（ログで「推定できない」理由を見分けるため）。
    public static func estimate(_ sample: FileListSample) -> PanelSelectionEstimate {
        let rows = Array(sample.leadingRows.prefix(sampledRowCount)) + sample.trailingRows.prefix(trailingSampledRowCount)
        return PanelSelectionEstimate(
            mode: mode(of: rows),
            sampledRowCount: rows.count,
            sampledDirectoryCount: rows.count(where: { $0.isDirectory == true }),
            sampledFileCount: rows.count(where: { $0.isDirectory == false })
        )
    }

    private static func mode(of rows: some Sequence<FileListRow>) -> PanelSelectionMode {
        var hasUnselectableFile = false
        var hasUndeterminedFile = false
        for row in rows where row.isDirectory == false {
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
