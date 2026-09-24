import Testing

import OpenPathCore

@Suite("PanelSelectionModeEstimator: 先頭と末尾の行からの推定と、行の内訳（Issue #73）")
struct PanelSelectionEstimateTests {
    private typealias Estimator = PanelSelectionModeEstimator

    private static let directory = FileListRow(isDirectory: true)
    private static let selectableFile = FileListRow(isDirectory: false, textOpacity: 0.85)
    private static let dimmedFile = FileListRow(isDirectory: false, textOpacity: 0.25)
    private static let unknownKindRow = FileListRow(isDirectory: nil)
    private static let undeterminedFile = FileListRow(isDirectory: false, isEnabled: true)

    private static func directories(_ count: Int) -> [FileListRow] {
        Array(repeating: directory, count: count)
    }

    @Test(
        "先頭の行がディレクトリだけでも、末尾の行のファイルから推定する",
        arguments: [
            ("末尾のファイルがすべて選べない", [Self.directory, Self.dimmedFile, Self.dimmedFile], PanelSelectionMode.directoriesOnly),
            ("末尾に選べるファイルがある", [Self.dimmedFile, Self.selectableFile], .filesSelectable),
            ("末尾もディレクトリだけ", [Self.directory, Self.directory], .undetermined),
            ("末尾に選べるか分からないファイルがある", [Self.dimmedFile, Self.undeterminedFile], .undetermined),
            ("末尾を読んでいない", [FileListRow](), .undetermined),
        ]
    )
    func usesTrailingRows(label: String, trailing: [FileListRow], expected: PanelSelectionMode) {
        let sample = FileListSample(leadingRows: Self.directories(15), trailingRows: trailing)

        #expect(Estimator.estimate(sample).mode == expected, "\(label)")
    }

    @Test("先頭の行の選べるファイルと末尾の行の選べないファイルを合わせて推定する（種類で絞り込むパネル）")
    func combinesLeadingAndTrailingRows() {
        let sample = FileListSample(leadingRows: [Self.directory, Self.selectableFile], trailingRows: [Self.dimmedFile])

        #expect(Estimator.estimate(sample).mode == .filesSelectable)
    }

    @Test("先頭の行は sampledRowCount 行、末尾の行は trailingSampledRowCount 行までしか見ない")
    func limitsLeadingAndTrailingRows() {
        let leading = Self.directories(Estimator.sampledRowCount) + [Self.selectableFile]
        let trailing = Self.directories(Estimator.trailingSampledRowCount) + [Self.selectableFile]

        let estimate = Estimator.estimate(FileListSample(leadingRows: leading, trailingRows: trailing))

        #expect(estimate.mode == .undetermined)
        #expect(estimate.sampledRowCount == Estimator.sampledRowCount + Estimator.trailingSampledRowCount)
    }

    @Test("推定に使った行の内訳（行・ディレクトリ・ディレクトリ以外）を数える。種類の分からない行は行にだけ数える")
    func countsSampledRows() {
        let sample = FileListSample(
            leadingRows: [Self.unknownKindRow, Self.directory, Self.directory, Self.undeterminedFile],
            trailingRows: [Self.directory, Self.dimmedFile]
        )

        let estimate = Estimator.estimate(sample)

        #expect(estimate == PanelSelectionEstimate(
            mode: .undetermined,
            sampledRowCount: 6,
            sampledDirectoryCount: 3,
            sampledFileCount: 2
        ))
    }

    @Test("行を読めなかった推定は、内訳がすべて 0 の「推定できない」")
    func undeterminedWithoutRows() {
        #expect(Estimator.estimate(FileListSample(leadingRows: [], trailingRows: [])) == .notSampled)
        #expect(PanelSelectionEstimate.notSampled.mode == .undetermined)
        #expect(PanelSelectionEstimate.notSampled.sampledRowCount == 0)
    }

    @Test("先頭の行だけの推定は、これまでの estimate(_ rows:) と同じ結果になる")
    func leadingOnlyMatchesRowEstimate() {
        let cases: [[FileListRow]] = [
            [Self.directory, Self.dimmedFile],
            [Self.directory, Self.selectableFile],
            Self.directories(3),
            [],
            Self.directories(Estimator.sampledRowCount) + [Self.dimmedFile],
        ]
        for rows in cases {
            #expect(Estimator.estimate(FileListSample(leadingRows: rows, trailingRows: [])).mode == Estimator.estimate(rows))
        }
    }
}
