import Testing

import OpenPathCore

@Suite("CandidateBuildProgress")
struct CandidateBuildProgressTests {
    @Test("構築が始まる前は構築中を表示しない")
    func hiddenBeforeBuild() {
        var progress = CandidateBuildProgress()

        let finished = progress.update(isRebuilding: false)

        #expect(finished == false)
        #expect(progress.showsBuildingStatus == false)
    }

    @Test("最初の構築の間は構築中を表示し、終えたら消して引き直しを知らせる")
    func showsDuringFirstBuild() {
        var progress = CandidateBuildProgress()

        let started = progress.update(isRebuilding: true)
        let showsWhileBuilding = progress.showsBuildingStatus
        let finished = progress.update(isRebuilding: false)

        #expect(started == false)
        #expect(showsWhileBuilding)
        #expect(finished)
        #expect(progress.showsBuildingStatus == false)
    }

    @Test("2 回目以降の構築（周期・手動・設定の変更）では構築中を表示しないが、終えたら引き直しを知らせる")
    func laterBuildsAreSilent() {
        var progress = CandidateBuildProgress()
        _ = progress.update(isRebuilding: true)
        _ = progress.update(isRebuilding: false)

        _ = progress.update(isRebuilding: true)
        let showsWhileBuilding = progress.showsBuildingStatus
        let finished = progress.update(isRebuilding: false)

        #expect(showsWhileBuilding == false)
        #expect(finished)
    }

    @Test("同じ値が続いても終了を重ねて知らせない")
    func repeatedValuesAreIgnored() {
        var progress = CandidateBuildProgress()
        _ = progress.update(isRebuilding: true)

        let repeatedStart = progress.update(isRebuilding: true)
        _ = progress.update(isRebuilding: false)
        let repeatedFinish = progress.update(isRebuilding: false)

        #expect(repeatedStart == false)
        #expect(repeatedFinish == false)
    }
}
