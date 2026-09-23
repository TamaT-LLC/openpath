import Foundation

/// 履歴（HistoryStore.entries）の frecency と最終使用日時を、候補（CandidateCatalog の添字）から引ける形にしたもの。
///
/// frecency は経過時間で減衰するため、クエリのたびにその時点の `now` で作り直す。
/// 候補ごとにパスの文字列で辞書を引くと候補数ぶんのハッシュ計算になるため、
/// 履歴の側（最大 2,000 件）から候補の添字を引いて、添字で読める配列にしておく。
struct HistoryLookup: Sendable {
    struct Usage: Sendable {
        let frecency: Double
        let lastUsed: Date
    }

    /// 候補の添字ごとの履歴。履歴が無ければ空
    private let usages: [Usage?]
    /// 履歴のある候補の添字（順不同）
    let usedIndices: [Int]

    /// 履歴はパス文字列をそのままキーにしているため、候補と同じ正規化（CandidatePath）をかけてから候補を引く。
    /// 正規化すると同じパスになる履歴が複数あれば、frecency は合算し、最終使用日時は新しい方を採る。
    init(entries: [HistoryEntry], now: Date, catalog: CandidateCatalog) {
        var usagesByPath: [String: Usage] = [:]
        usagesByPath.reserveCapacity(entries.count)
        for entry in entries {
            guard let path = CandidatePath.normalized(entry.path) else { continue }
            let frecency = entry.frecency(now: now)
            if let existing = usagesByPath[path] {
                usagesByPath[path] = Usage(frecency: existing.frecency + frecency, lastUsed: max(existing.lastUsed, entry.lastUsed))
            } else {
                usagesByPath[path] = Usage(frecency: frecency, lastUsed: entry.lastUsed)
            }
        }

        var usages: [Usage?] = []
        var usedIndices: [Int] = []
        for (path, usage) in usagesByPath {
            guard let index = catalog.index(ofPath: path) else { continue }
            if usages.isEmpty {
                usages = Array(repeating: nil, count: catalog.entries.count)
            }
            usages[index] = usage
            usedIndices.append(index)
        }
        self.usages = usages
        self.usedIndices = usedIndices
    }

    /// 候補 `index` の履歴。履歴に無ければ nil
    func usage(at index: Int) -> Usage? {
        usages.isEmpty ? nil : usages[index]
    }
}
