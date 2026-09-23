import Testing

@testable import OpenPathCore

/// 候補の前処理の使い回し（5 分ごとの再走査で前処理をやり直さない）。
@Suite("CandidatePreparer")
struct CandidatePreparerTests {
    private typealias F = IndexFixtures

    private let preparer = CandidatePreparer(matcher: FuzzyMatcher())

    /// 前処理済みの対象が同じバッファを指すか（作り直していないか）
    private static func sharesStorage(_ lhs: FuzzyTarget, _ rhs: FuzzyTarget) -> Bool {
        lhs.elements.withUnsafeBufferPointer { lhsBuffer in
            rhs.elements.withUnsafeBufferPointer { rhsBuffer in
                lhsBuffer.baseAddress == rhsBuffer.baseAddress
            }
        }
    }

    @Test("差し替え前の候補に同じパスがあれば、前処理を作り直さずに使い回す")
    func reusesTargetsOfSamePath() throws {
        let previous = CandidateCatalog(merging: [.ghq: preparer.prepare([F.directory("/repos/app")])])
        let previousTargets = try #require(previous.targets(forPath: "/repos/app"))

        // 別のソースから、正規化前の表記で同じパスが来た場合も使い回す
        let prepared = preparer.prepare([F.directory("/repos/app/"), F.directory("/repos/new")], reusing: previous)

        #expect(prepared.map(\.path) == ["/repos/app", "/repos/new"])
        #expect(Self.sharesStorage(prepared[0].targets.path, previousTargets.path))
        #expect(Self.sharesStorage(prepared[0].targets.name, previousTargets.name))
    }

    @Test("使い回した候補と作り直した候補でマッチ結果は変わらない")
    func reusedTargetsMatchLikeFreshOnes() throws {
        let matcher = FuzzyMatcher()
        let previous = CandidateCatalog(merging: [.ghq: preparer.prepare([F.directory("/Users/me/repos/fern")])])

        let reused = try #require(preparer.prepare([F.directory("/Users/me/repos/fern")], reusing: previous).first)
        let fresh = try #require(preparer.prepare([F.directory("/Users/me/repos/fern")]).first)

        let query = matcher.prepareQuery("rf")
        #expect(
            matcher.scoreCandidate(query: query, name: reused.targets.name, path: reused.targets.path)
                == matcher.scoreCandidate(query: query, name: fresh.targets.name, path: fresh.targets.path)
        )
    }
}
