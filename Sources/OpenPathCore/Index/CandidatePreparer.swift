/// マッチに使う前処理済みの対象（name / path）と、前置フィルタ用の文字集合。
/// パスだけで決まるため、同じパスを持つ別のソースや再走査の結果で共有する。
struct CandidateTargets: Sendable {
    let name: FuzzyTarget
    let path: FuzzyTarget
    let signature: CharacterSignature
}

/// ソースから受け取った 1 件を、統合とマッチに使える形にしたもの。
struct PreparedCandidate: Sendable {
    /// 正規化済みの絶対パス（CandidatePath）
    let path: String
    let isDirectory: Bool
    let targets: CandidateTargets
}

/// ソースの候補を前処理する。候補の前処理（正規化）は 1 件あたり数十 µs かかるため、
/// 差し替え前の候補に同じパスがあれば作り直さずに使い回す（5 分ごとの再走査ではほぼすべてが使い回しになる）。
struct CandidatePreparer: Sendable {
    let matcher: FuzzyMatcher

    /// パスを正規化し、絶対パスでないものを除き、ソース内の重複を 1 件にまとめる。
    /// 重複で isDirectory が食い違う場合は、統合時（CandidateCatalog）と同じくファイルとして扱う。
    func prepare(_ items: [SourceItem], reusing previous: CandidateCatalog = .empty) -> [PreparedCandidate] {
        var prepared: [PreparedCandidate] = []
        prepared.reserveCapacity(items.count)
        var indexByPath: [String: Int] = [:]
        for item in items {
            guard let path = CandidatePath.normalized(item.path) else {
                // 手編集された履歴など想定外の入力として記録する
                Log.debugPath("正規化できないパスをスキップしました", path: item.path)
                continue
            }
            if let index = indexByPath[path] {
                let existing = prepared[index]
                prepared[index] = PreparedCandidate(
                    path: existing.path,
                    isDirectory: existing.isDirectory && item.isDirectory,
                    targets: existing.targets
                )
                continue
            }
            indexByPath[path] = prepared.count
            let targets = previous.targets(forPath: path) ?? makeTargets(path: path)
            prepared.append(PreparedCandidate(path: path, isDirectory: item.isDirectory, targets: targets))
        }
        return prepared
    }

    private func makeTargets(path: String) -> CandidateTargets {
        let name = matcher.prepareTarget(CandidatePath.name(of: path))
        let pathTarget = matcher.prepareTarget(path)
        var signature = CharacterSignature(pathTarget.elements.lazy.map(\.code))
        // 表示名はパスの末尾要素なので通常はパスの文字に含まれるが、書記素の区切りが変わる場合に備えて合わせる
        signature.formUnion(CharacterSignature(name.elements.lazy.map(\.code)))
        return CandidateTargets(name: name, path: pathTarget, signature: signature)
    }
}
