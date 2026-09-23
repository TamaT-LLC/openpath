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
