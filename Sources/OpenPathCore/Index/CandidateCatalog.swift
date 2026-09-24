/// 全ソースの候補を統合した、ある時点の候補一覧（不変の値）。
///
/// CandidateIndex は差し替えのたびにこれを作り直して丸ごと入れ替え、クエリはロックの外でこの値を読む。
/// 候補はパスの昇順に並べ、添字の昇順をそのまま「パスの昇順」の同点処理に使う。
struct CandidateCatalog: Sendable {
    struct Entry: Sendable {
        let path: String
        /// 同じパスを持つソースのうち、最も優先度の高いもの
        let source: CandidateSourceKind
        /// すべてのソースがディレクトリとした場合だけ true
        fileprivate(set) var isDirectory: Bool
        let targets: CandidateTargets
    }

    /// 前置フィルタに使うクエリの先頭の文字数（DSN-002 §5）
    static let prefilterCharacterCount = 2
    static let empty = CandidateCatalog(entries: [], indexByPath: [:])

    /// パスの昇順
    let entries: [Entry]
    /// パスから `entries` の添字を引く表。履歴の表引きと、差し替え時の前処理の使い回しに使う
    private let indexByPath: [String: Int]

    /// - Parameters:
    ///   - entries: パスの昇順・重複なし
    ///   - indexByPath: `entries` の各パスから添字を引く表
    private init(entries: [Entry], indexByPath: [String: Int]) {
        self.entries = entries
        self.indexByPath = indexByPath
    }

    /// ソースごとの候補を、同じパスは 1 件にまとめて統合する（DSN-002 §3）。
    ///
    /// source は優先度 history > ghq > roots（`CandidateSourceKind.mergesBefore`）で最も高いものにする。
    /// isDirectory が食い違う場合はファイルとして扱う。種別が走査の間に変わった可能性があり、
    /// フォルダ選択のパネル（FR-SOURCE-05）にファイルを出すより、ディレクトリを 1 件出し損ねる方が害が小さいため。
    init(merging sources: [CandidateSourceKind: [PreparedCandidate]]) {
        // 伸ばしながら作り直すと、途中の大きさの配列・表が一時的に重なり、再構築の間のメモリのピークを
        // 押し上げるため（候補 20,000 件で数 MB。Issue #78）、上限（重複が無い場合の件数）で先に確保する
        let maximumCount = sources.values.reduce(0) { $0 + $1.count }
        var entries: [Entry] = []
        entries.reserveCapacity(maximumCount)
        var indexByPath: [String: Int] = [:]
        indexByPath.reserveCapacity(maximumCount)
        for (kind, candidates) in sources.sorted(by: { CandidateSourceKind.mergesBefore($0.key, $1.key) }) {
            for candidate in candidates {
                if let index = indexByPath[candidate.path] {
                    entries[index].isDirectory = entries[index].isDirectory && candidate.isDirectory
                    continue
                }
                indexByPath[candidate.path] = entries.count
                entries.append(Entry(path: candidate.path, source: kind, isDirectory: candidate.isDirectory, targets: candidate.targets))
            }
        }
        entries.sort { $0.path < $1.path }
        // 統合に使った表を、並べ替えた後の添字に書き換えて使い回す（作り直すと一時的に表が 2 つ重なるため）
        for (position, entry) in entries.enumerated() {
            indexByPath[entry.path] = position
        }
        self.init(entries: entries, indexByPath: indexByPath)
    }

    /// 前置フィルタを通る候補の添字（昇順）。
    /// クエリの先頭 2 文字（正規化後）のどちらかを name / path に含まない候補はマッチしないため、マッチ処理の前に外す。
    func prefilteredIndices(for query: FuzzyQuery) -> [Int] {
        let required = CharacterSignature(query.codes.prefix(Self.prefilterCharacterCount))
        return entries.indices.filter { entries[$0].targets.signature.mayContainAll(of: required) }
    }

    /// 正規化済みのパス `path` の候補の添字。無ければ nil
    func index(ofPath path: String) -> Int? {
        indexByPath[path]
    }

    /// 正規化済みのパス `path` の前処理済みの対象。差し替えのときに同じパスの前処理を使い回すために使う
    func targets(forPath path: String) -> CandidateTargets? {
        index(ofPath: path).map { entries[$0].targets }
    }
}
