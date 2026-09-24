/// roots の 1 ルートを走査した時点の、中身を読んだディレクトリの状態の記録（Issue #78）。
///
/// 走査で中身を読むのはルートと depth 未満の各ディレクトリ（除外・隠し・パッケージ・シンボリックリンクを除く）で、
/// 候補はそれらの直下の一覧だけで決まる。どのディレクトリも状態（DirectoryStamp）が変わっていなければ、
/// 同じ条件で走査し直しても同じ候補になるため、周期の再構築ではこれらを stat し直すだけで走査を省ける。
/// 記録するディレクトリの数は候補の数以下（ルートあたりの上限 20,000 件）で、stat は 1 件あたり数 µs のため、
/// 走査し直す（全項目の列挙と種別の問い合わせ）より十分軽い。
///
/// 検知しない変化: シンボリックリンクのリンク先の中身や種別の変化（リンク自体の作成・削除・張り替えは、
/// 親ディレクトリの更新日時で検知する）、depth の階層の項目の隠し属性の変化。手動の「候補を再構築」で反映する。
public struct RootScanMarker: Sendable, Equatable {
    struct Directory: Sendable, Equatable {
        let path: String
        let stamp: DirectoryStamp
    }

    /// 走査したルート（設定の表記）
    let root: String
    /// 走査の条件。条件が変わると同じディレクトリでも候補が変わるため、別の条件の記録は使わない
    let options: RootScanOptions
    /// 中身を読む前に記録した状態。先頭はルート
    let directories: [Directory]

    /// 記録したディレクトリの数（ルートを含む）。変更の確認で stat する回数
    public var directoryCount: Int {
        directories.count
    }

    /// 記録した後に、いずれかのディレクトリの状態が変わった（消えた・読めなくなったを含む）か。
    /// ファイルシステムを同期的に読むため、メインスレッドから呼ばないこと。
    public func hasChanges() -> Bool {
        directories.contains { DirectoryStamp.read(atPath: $0.path) != $0.stamp }
    }

    /// `root` を `options` で走査した記録か
    func isRecorded(root: String, options: RootScanOptions) -> Bool {
        self.root == root && self.options == options
    }
}

/// 変更の検知の記録を添えた、1 ルートの走査の結果（Issue #78）。
public struct RootScanResult: Sendable {
    public let snapshot: CandidateSourceSnapshot
    /// ルートを走査できなかった（存在しない・ディレクトリでない・読めない）ときは nil
    public let marker: RootScanMarker?
}

/// 走査の途中で、中身を読むディレクトリの状態を読む前に記録していく。
struct RootScanMarkerRecorder {
    private let root: String
    private let options: RootScanOptions
    private var directories: [RootScanMarker.Directory] = []
    /// ルートの状態を読めなかった（走査を始める前に消えた等）ときは記録を作らない
    private var isRootRecorded = false

    init(root: String, options: RootScanOptions) {
        self.root = root
        self.options = options
    }

    /// ルートの状態を記録する。列挙（ルートの中身を読む）より前に呼ぶ
    mutating func recordRoot() {
        guard let stamp = DirectoryStamp.read(atPath: root) else { return }
        directories.append(RootScanMarker.Directory(path: root, stamp: stamp))
        isRootRecorded = true
    }

    /// 中身を読むディレクトリの状態を記録する。列挙がそのディレクトリに潜る（中身を読む）より前に呼ぶ。
    /// 読めなければ記録しない。その間に消えたのなら、親の状態が変わっているため次の確認で検知できる
    mutating func recordDirectory(atPath path: String) {
        guard let stamp = DirectoryStamp.read(atPath: path) else { return }
        directories.append(RootScanMarker.Directory(path: path, stamp: stamp))
    }

    func marker() -> RootScanMarker? {
        guard isRootRecorded else { return nil }
        return RootScanMarker(root: root, options: options, directories: directories)
    }
}
