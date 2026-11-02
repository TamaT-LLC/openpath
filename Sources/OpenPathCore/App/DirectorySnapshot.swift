import Foundation

/// Tab で開いた 1 フォルダの直下だけを保持する。共有 CandidateIndex には登録しない。
/// 名前の前処理は列挙時に一度だけ行い、絞り込みではフォルダのパスをマッチ対象にしない。
public struct DirectorySnapshot: Sendable {
    private struct Entry: Sendable {
        let item: SourceItem
        let name: String
        let target: FuzzyTarget
    }

    private let entries: [Entry]
    private let matcher = FuzzyMatcher()
    public let message: String?

    public init(items: [SourceItem], message: String? = nil) {
        let matcher = FuzzyMatcher()
        var seen: Set<String> = []
        entries = items.filter { seen.insert($0.path).inserted }.map { item in
            let name = CandidatePath.name(of: item.path)
            return Entry(item: item, name: name, target: matcher.prepareTarget(name))
        }
        self.message = message
    }

    /// 非隔離の async 関数なので、呼び出し元の MainActor ではファイルシステムを読まない。
    public static func load(directory: String, ignoredNames: Set<String>) async throws -> DirectorySnapshot {
        let options = RootScanOptions(depth: 1, includeFiles: true, ignoredNames: ignoredNames)
        let snapshot = try RootDirectoryScanner(options: options).scan(root: directory)
        try Task.checkCancellation()
        var message: String?
        for warning in snapshot.warnings {
            switch warning {
            case .rootUnavailable(_, let reason):
                let message: String = switch reason {
                case .notFound: PaletteText.directoryNotFound
                case .notDirectory: PaletteText.directoryNotDirectory
                case .unreadable: PaletteText.directoryUnreadable
                }
                return DirectorySnapshot(items: [], message: message)
            case .rootTruncated:
                message = PaletteText.directoryTruncated
            case .ghqFailed:
                break
            }
        }
        return DirectorySnapshot(items: snapshot.items.filter { $0.path != directory }, message: message)
    }

    /// 直下の名前だけをファジー検索。通常検索と同じく履歴を加味し、最大 limit 件返す。
    public func search(
        _ text: String, directoriesOnly: Bool, limit: Int,
        history: [HistoryEntry] = [], now: Date = Date()
    ) async throws -> DirectorySearchResult {
        let query = matcher.prepareQuery(text)
        let usage = Dictionary(history.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
        var matches: [(entry: Entry, match: FuzzyMatch, score: Double)] = []
        for entry in entries {
            try Task.checkCancellation()
            guard !directoriesOnly || entry.item.isDirectory,
                  let match = matcher.score(query: query, in: entry.target) else { continue }
            let frecency = usage[entry.item.path]?.frecency(now: now) ?? 0
            let score = query.codes.isEmpty ? frecency : Double(match.score) * (1 + log1p(frecency))
            matches.append((entry, match, score))
        }
        matches.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            let lhsDate = usage[$0.entry.item.path]?.lastUsed ?? .distantPast
            let rhsDate = usage[$1.entry.item.path]?.lastUsed ?? .distantPast
            if lhsDate != rhsDate { return lhsDate > rhsDate }
            return $0.entry.item.path < $1.entry.item.path
        }
        var rows: [PaletteRow] = []
        for (entry, match, _) in matches {
            try Task.checkCancellation()
            guard rows.count < max(0, limit) else { break }
            // 列挙後に削除された候補や、種別が変わった候補を確定させない。
            guard let kind = FileSystemItemKind.ofItem(atPath: entry.item.path),
                  !directoriesOnly || kind == .directory else { continue }
            rows.append(PaletteRow(
                name: entry.name, path: entry.item.path, lastUsed: usage[entry.item.path]?.lastUsed,
                isDirectory: kind == .directory, nameHighlights: match.positions
            ))
        }
        let emptyMessage = query.codes.isEmpty && rows.isEmpty ? PaletteText.emptyDirectory : nil
        return DirectorySearchResult(rows: rows, message: message ?? emptyMessage)
    }
}

public struct DirectorySearchResult: Sendable {
    public let rows: [PaletteRow]
    public let message: String?
}
