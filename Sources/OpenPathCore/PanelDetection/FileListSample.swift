/// 選択モードの推定に読んだファイル一覧の行（DSN-001 §2.3）。`FileListRowSampler.sample` が返す。
public struct FileListSample: Equatable, Sendable {
    /// 先頭の行（表示中の行を先頭から）。
    public let leadingRows: [FileListRow]
    /// 一覧の末尾の行。先頭の行がディレクトリばかりで、一覧に続きがあるときだけ読む。
    public let trailingRows: [FileListRow]

    public init(leadingRows: [FileListRow], trailingRows: [FileListRow]) {
        self.leadingRows = leadingRows
        self.trailingRows = trailingRows
    }
}
