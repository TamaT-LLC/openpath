/// 1 ルート分の候補を上限件数までためる。上限を超える候補が見つかった時点で打ち切りとして記録する。
struct RootItemCollector {
    let root: String
    let limit: Int
    private(set) var items: [SourceItem] = []
    private(set) var isTruncated = false

    init(root: String, limit: Int) {
        self.root = root
        self.limit = limit
    }

    /// 追加できたら true。上限に達していて追加できなければ打ち切りとして記録し false を返す。
    mutating func append(_ item: SourceItem) -> Bool {
        guard items.count < limit else {
            isTruncated = true
            return false
        }
        items.append(item)
        return true
    }

    func snapshot() -> CandidateSourceSnapshot {
        let warnings: [CandidateSourceWarning] = isTruncated ? [.rootTruncated(root: root, limit: limit)] : []
        return CandidateSourceSnapshot(items: items, warnings: warnings)
    }
}

/// 列挙された項目の名前と深さから、設定したルートの表記を起点にパスを組み立てる。
///
/// 列挙で得られる URL は `/var` が `/private/var` に解決されていたり、ルートのシンボリックリンクが解決されていたりして
/// 設定の表記と一致しないため、URL のパスはそのまま使わない。
/// 列挙は行きがけ順なので、深さ n の項目の親は直前に現れた深さ n-1 の項目になる。
struct DescendantPathBuilder {
    private static let separator = "/"

    private let root: String
    /// 添字 i に、直前に現れた深さ i+1 の項目のパスを持つ
    private var pathsByLevel: [String] = []

    init(root: String) {
        self.root = root
    }

    /// - Parameters:
    ///   - name: 項目の名前（パスの最後の要素）
    ///   - level: ルート直下を 1 とした深さ
    mutating func path(forName name: String, level: Int) -> String {
        let parentLevel = level - 1
        pathsByLevel.removeLast(max(pathsByLevel.count - parentLevel, 0))
        let path = Self.join(pathsByLevel.last ?? root, name)
        pathsByLevel.append(path)
        return path
    }

    /// ルートが `/` のときに `//` にならないよう結合する。
    private static func join(_ parent: String, _ name: String) -> String {
        parent.hasSuffix(separator) ? parent + name : parent + separator + name
    }
}
