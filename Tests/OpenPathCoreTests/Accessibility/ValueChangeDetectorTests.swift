import Testing

import OpenPathCore

@Suite("ValueChangeDetector")
struct ValueChangeDetectorTests {
    @Test("初期値は current として保持する")
    func holdsInitialValue() {
        let detector = ValueChangeDetector(initial: false)

        #expect(detector.current == false)
    }

    @Test("前回値と同じ値では変化を報告しない")
    func ignoresSameValue() {
        var detector = ValueChangeDetector(initial: false)

        #expect(detector.update(false) == nil)
        #expect(detector.current == false)
    }

    @Test("前回値と異なる値は新しい値として報告し、current を更新する")
    func reportsChangedValue() {
        var detector = ValueChangeDetector(initial: false)

        #expect(detector.update(true) == true)
        #expect(detector.current == true)
    }

    @Test("比較は直前の値に対して行う（未付与→付与→付与→未付与）")
    func comparesWithPreviousValue() {
        var detector = ValueChangeDetector(initial: false)

        let reported = [false, true, true, false, false].map { detector.update($0) }

        #expect(reported == [nil, true, nil, false, nil])
    }
}
