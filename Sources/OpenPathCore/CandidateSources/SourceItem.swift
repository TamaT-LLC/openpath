/// 候補ソースが返す 1 件。表示用の Candidate（表示名・frecency 等）は CandidateIndex がこれから組み立てる。
public struct SourceItem: Sendable, Hashable {
    /// 絶対パス。末尾に `/` を付けない。roots の候補は設定したルートの表記を起点にする
    public let path: String
    /// パネルでディレクトリとして移動できるか。シンボリックリンクはリンク先の種別で決める。
    /// パッケージ（`.app` 等）は NSOpenPanel が既定でファイルとして扱うため false
    public let isDirectory: Bool

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }
}
