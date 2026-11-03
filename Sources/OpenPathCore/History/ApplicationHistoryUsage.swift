import Foundation

/// あるパスを 1 アプリから使った回数と日時。全体の使用回数とは別に保持する。
public struct ApplicationHistoryUsage: Codable, Sendable, Equatable {
    public var count: Int
    public var lastUsed: Date

    private enum CodingKeys: String, CodingKey {
        case count
        case lastUsed = "last_used"
    }

    public init(count: Int, lastUsed: Date) {
        self.count = count
        self.lastUsed = lastUsed
    }
}
