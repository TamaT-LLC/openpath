import Foundation

/// 確定したパス 1 件分の使用履歴（FR-HISTORY-01）。`history.json` の要素になる。
public struct HistoryEntry: Codable, Sendable, Equatable {
    /// 呼び出し側で正規化済みのパス。履歴のキーとして文字列のまま比較する。
    public var path: String
    public var count: Int
    public var lastUsed: Date
    /// 各パスで直近に使った最大 8 アプリ。旧形式には無いので空として読む。
    public var applications: [String: ApplicationHistoryUsage]
    public static let maxApplicationCount = 8

    // ARCH-001 §8 の `{ path, count, last_used }` に合わせる
    private enum CodingKeys: String, CodingKey {
        case path
        case count
        case applications
        case lastUsed = "last_used"
    }

    public init(path: String, count: Int, lastUsed: Date, applications: [String: ApplicationHistoryUsage] = [:]) {
        self.path = path
        self.count = count
        self.lastUsed = lastUsed
        self.applications = applications
        boundApplications()
    }

    /// 全体の使用実績に呼び出し元の実績を加味する。未知のアプリや旧履歴は全体スコアで答える。
    public func frecency(now: Date, applicationBundleID: String? = nil) -> Double {
        let global = Frecency.score(count: count, lastUsed: lastUsed, now: now)
        guard let applicationBundleID, let usage = applications[applicationBundleID] else { return global }
        return global + 4 * Frecency.score(count: usage.count, lastUsed: usage.lastUsed, now: now)
    }

    /// 全体とアプリ別の実績を同時に更新し、古いアプリの記録を上限まで削る。
    mutating func record(applicationBundleID: String?, now: Date) {
        count += 1
        lastUsed = now
        guard let applicationBundleID = PanelContext.historyApplicationID(applicationBundleID) else { return }
        var usage = applications[applicationBundleID] ?? ApplicationHistoryUsage(count: 0, lastUsed: now)
        usage.count += 1
        usage.lastUsed = now
        applications[applicationBundleID] = usage
        boundApplications(protecting: applicationBundleID)
    }

    /// 手編集や重複パスの統合後も、直近 8 アプリだけを決定的な順序で残す。
    mutating func boundApplications(protecting applicationBundleID: String? = nil) {
        applications = applications.filter { PanelContext.historyApplicationID($0.key) != nil }
        guard applications.count > Self.maxApplicationCount else { return }
        let retained = applications.sorted {
            if $0.key == applicationBundleID { return $1.key != applicationBundleID }
            if $1.key == applicationBundleID { return false }
            return $0.value.lastUsed != $1.value.lastUsed ? $0.value.lastUsed > $1.value.lastUsed : $0.key < $1.key
        }.prefix(Self.maxApplicationCount)
        applications = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }

    /// 旧 history.json の配列形式とキーを維持し、applications が無い要素は空として移行する。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            path: try container.decode(String.self, forKey: .path),
            count: try container.decode(Int.self, forKey: .count),
            lastUsed: try container.decode(Date.self, forKey: .lastUsed),
            applications: try container.decodeIfPresent([String: ApplicationHistoryUsage].self, forKey: .applications) ?? [:]
        )
    }

    /// アプリ実績の無い要素は従来と同じ JSON にし、不要な移行差分を作らない。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(path, forKey: .path)
        try container.encode(count, forKey: .count)
        try container.encode(lastUsed, forKey: .lastUsed)
        if !applications.isEmpty { try container.encode(applications, forKey: .applications) }
    }
}
