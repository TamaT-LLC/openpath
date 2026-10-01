import Testing

@testable import OpenPathCore

/// ソースの候補をすぐ取り除き、それより前に始めた収集の差し替えを反映しない（Issue #92）。
/// 履歴のクリアで、走査中の再構築を待たずに履歴の候補を消すために使う。
@Suite("CandidateIndex: ソースの候補の無効化")
struct CandidateIndexInvalidateTests {
    private typealias F = IndexFixtures

    private static let root = CandidateSourceKind.root("/Users/me/repos")
    private static let historyItem = F.directory("/Users/me/history-only")
    private static let rootItem = F.directory("/Users/me/repos/app")
    /// 無効化と並行させる差し替えの件数
    private static let raceItemCount = 2_000
    /// 差し替えを始めてから無効にするまでの時間
    private static let raceDelays: [Duration] = [.zero, .milliseconds(1), .milliseconds(2), .milliseconds(5), .milliseconds(10)]

    private static func allPaths(in index: CandidateIndex) async throws -> [String] {
        try await index.query("", directoriesOnly: false, limit: F.generousLimit).map(\.candidate.path).sorted()
    }

    @Test("無効にしたソースの候補だけを取り除き、他のソースの候補は残す")
    func invalidateRemovesOnlyThatSource() async throws {
        let index = F.makeIndex()
        await index.replace(source: .history, with: [Self.historyItem])
        await index.replace(source: Self.root, with: [Self.rootItem])

        await index.invalidate(source: .history).value

        #expect(try await Self.allPaths(in: index) == [Self.rootItem.path])
        #expect(index.count == 1)
    }

    @Test("続けて無効にしても、後の呼び出しの Task が終わった時点で、先に取り除いた候補がクエリに反映されている")
    func repeatedInvalidateWaitsForEarlierRemoval() async {
        // 統合し直しに時間がかかる程度の候補を持たせ、先の無効化の反映が後の無効化より遅れる状況を作る
        let index = F.makeIndex()
        let rootItems = (0..<Self.raceItemCount).map { F.directory("/Users/me/repos/app/\($0)") }
        await index.replace(source: Self.root, with: rootItems)
        await index.replace(source: .history, with: [Self.historyItem])

        index.invalidate(source: .history)
        await index.invalidate(source: .history).value

        #expect(index.count == rootItems.count)
    }

    @Test("無効にする前に取った世代での差し替えは反映しない（消す前の履歴を読んだ収集で候補を戻さない）")
    func replaceWithStaleGenerationIsSuperseded() async throws {
        let index = F.makeIndex()
        await index.replace(source: .history, with: [Self.historyItem])
        let generation = index.generation(of: .history)

        // 世代は呼んだ時点で進む（統合し直した候補の反映を待たずに差し替えても反映されない）
        let removal = index.invalidate(source: .history)
        let outcome = await index.replace(source: .history, with: [Self.historyItem], generation: generation)
        await removal.value

        #expect(outcome == .superseded)
        #expect(try await Self.allPaths(in: index).isEmpty)
    }

    @Test("候補がまだ無いソースを無効にしても世代を進める（起動時の最初の差し替えより前に消した場合）")
    func invalidateBeforeFirstReplaceAdvancesGeneration() async throws {
        let index = F.makeIndex()
        let generation = index.generation(of: .history)

        await index.invalidate(source: .history).value
        let outcome = await index.replace(source: .history, with: [Self.historyItem], generation: generation)

        #expect(outcome == .superseded)
        #expect(try await Self.allPaths(in: index).isEmpty)
    }

    @Test("無効にした後に取った世代での差し替えは反映する")
    func replaceWithCurrentGenerationIsApplied() async throws {
        let index = F.makeIndex()
        await index.replace(source: .history, with: [Self.historyItem])
        await index.invalidate(source: .history).value

        let generation = index.generation(of: .history)
        let confirmed = F.directory("/Users/me/confirmed")
        let outcome = await index.replace(source: .history, with: [confirmed], generation: generation)

        #expect(outcome == .replaced)
        #expect(try await Self.allPaths(in: index) == [confirmed.path])
    }

    @Test("世代を指定した差し替えでも、候補が今と同じなら差し替えない")
    func replaceWithGenerationReportsUnchanged() async {
        let index = F.makeIndex()
        await index.replace(source: Self.root, with: [Self.rootItem])

        let outcome = await index.replace(source: Self.root, with: [Self.rootItem], generation: index.generation(of: Self.root))

        #expect(outcome == .unchanged)
    }

    @Test("無効にしても他のソースの世代は進めない")
    func invalidateDoesNotAffectOtherSources() async throws {
        let index = F.makeIndex()
        let rootGeneration = index.generation(of: Self.root)

        await index.invalidate(source: .history).value
        let outcome = await index.replace(source: Self.root, with: [Self.rootItem], generation: rootGeneration)

        #expect(outcome == .replaced)
        #expect(try await Self.allPaths(in: index) == [Self.rootItem.path])
    }

    @Test("無効にする前に取った世代での差し替えが、前処理の途中で無効にされても、取り除いた候補が戻らない")
    func staleReplaceRacingWithInvalidateNeverRestoresCandidates() async throws {
        let index = F.makeIndex()
        await index.replace(source: Self.root, with: [Self.rootItem])
        // 前処理（1 件あたり数十 µs）の途中で無効にできるよう件数を多くし、無効にする時刻をずらして繰り返す
        let items = (0..<Self.raceItemCount).map { F.directory("/Users/me/history/\($0)") }

        for delay in Self.raceDelays {
            let generation = index.generation(of: .history)
            let staleReplace = Task.detached {
                await index.replace(source: .history, with: items, generation: generation)
            }
            try await Task.sleep(for: delay)
            await index.invalidate(source: .history).value
            _ = await staleReplace.value

            // 差し替えが先に書き込まれれば無効化で取り除かれ、後になれば書き込まれない。どちらの順でも履歴の候補は残らない
            #expect(try await Self.allPaths(in: index) == [Self.rootItem.path])
        }
    }
}
