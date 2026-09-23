import Testing

import OpenPathCore

@Suite("PanelSelectionModeEstimator（選択モードの推定）")
struct PanelSelectionModeEstimatorTests {
    private typealias Estimator = PanelSelectionModeEstimator

    private static let directory = FileListRow(isDirectory: true)
    private static let selectableFile = FileListRow(isDirectory: false, textOpacity: 0.85)
    private static let dimmedFile = FileListRow(isDirectory: false, textOpacity: 0.25)
    /// 名前の要素がない行（リスト表示の並べ替えの見出しなど）
    private static let unknownKindRow = FileListRow(isDirectory: nil)
    /// 選べるか分からないファイルの行（文字色を読めず、AXEnabled も false でない）
    private static let undeterminedFile = FileListRow(isDirectory: false, isEnabled: true)

    @Test("ディレクトリ以外の行がすべて選べなければ、フォルダのみと推定する")
    func allFilesUnselectableMeansDirectoriesOnly() {
        let rows = [Self.directory, Self.dimmedFile, Self.directory, Self.dimmedFile]

        #expect(Estimator.estimate(rows) == .directoriesOnly)
    }

    @Test("AXEnabled が false のファイル（アイコン表示）も選べない行として数える")
    func disabledFilesMeanDirectoriesOnly() {
        let rows = [Self.directory, FileListRow(isDirectory: false, isEnabled: false)]

        #expect(Estimator.estimate(rows) == .directoriesOnly)
    }

    @Test("選べるファイルの行が 1 つでもあれば、ファイルも選べると推定する（種類で絞り込むパネルを含む）")
    func anySelectableFileMeansFilesSelectable() {
        let rows = [Self.directory, Self.dimmedFile, Self.selectableFile, Self.dimmedFile]

        #expect(Estimator.estimate(rows) == .filesSelectable)
    }

    @Test(
        "ディレクトリ以外の行がなければ推定できない",
        arguments: [
            ("行 0", [FileListRow]()),
            ("ディレクトリのみ", [Self.directory, Self.directory]),
            ("種類の分からない行のみ", [Self.unknownKindRow]),
            ("見出しとディレクトリ", [Self.unknownKindRow, Self.directory]),
        ]
    )
    func noFilesMeansUndetermined(label: String, rows: [FileListRow]) {
        #expect(Estimator.estimate(rows) == .undetermined, "\(label)")
    }

    @Test("種類の分からない行（見出しの行）は数えない")
    func unknownKindRowsAreIgnored() {
        let rows = [Self.unknownKindRow, Self.dimmedFile, Self.directory]

        #expect(Estimator.estimate(rows) == .directoriesOnly)
    }

    @Test("選べるか分からないファイルの行があれば、ほかが選べなくても推定しない")
    func undeterminedFileBlocksDirectoriesOnly() {
        let rows = [Self.dimmedFile, Self.undeterminedFile, Self.dimmedFile]

        #expect(Estimator.estimate(rows) == .undetermined)
    }

    @Test("選べるか分からない行があっても、選べるファイルの行があればファイルも選べる")
    func selectableFileWinsOverUndeterminedFile() {
        let rows = [Self.undeterminedFile, Self.selectableFile]

        #expect(Estimator.estimate(rows) == .filesSelectable)
    }

    // MARK: - 先頭 20 行

    @Test("推定に使うのは先頭 20 行")
    func sampledRowCountIsTwenty() {
        #expect(Estimator.sampledRowCount == 20)
    }

    @Test("21 行目以降の選べるファイルは見ない")
    func rowsBeyondSampleAreIgnored() {
        let rows = Array(repeating: Self.dimmedFile, count: Estimator.sampledRowCount) + [Self.selectableFile]

        #expect(Estimator.estimate(rows) == .directoriesOnly)
    }

    @Test("20 行目の選べるファイルは見る")
    func lastSampledRowIsUsed() {
        let rows = Array(repeating: Self.dimmedFile, count: Estimator.sampledRowCount - 1) + [Self.selectableFile]

        #expect(Estimator.estimate(rows) == .filesSelectable)
    }

    @Test("先頭 20 行がディレクトリだけなら、21 行目以降にファイルがあっても推定しない")
    func filesBeyondSampleDoNotCount() {
        let rows = Array(repeating: Self.directory, count: Estimator.sampledRowCount) + [Self.dimmedFile]

        #expect(Estimator.estimate(rows) == .undetermined)
    }

    // MARK: - PanelSelectionMode

    @Test(
        "フォルダのみと推定したときだけ isDirectoriesOnly が true（それ以外は include_files に従う）",
        arguments: [
            (PanelSelectionMode.directoriesOnly, true),
            (.filesSelectable, false),
            (.undetermined, false),
        ]
    )
    func isDirectoriesOnly(mode: PanelSelectionMode, expected: Bool) {
        #expect(mode.isDirectoriesOnly == expected)
    }
}

@Suite("FileListRow（行が選べるか）")
struct FileListRowTests {
    @Test(
        "文字色の不透明度で選べるかを決める（通常 0.85 や不透明は選べる、淡色 0.25（ライト 0.26）は選べない）",
        arguments: [
            (0.847059, true),
            (1.0, true),
            (FileListRow.dimmedTextOpacityThreshold, true),
            (0.49, false),
            (0.247059, false),
            (0.258824, false),
            (0.0, false),
        ]
    )
    func textOpacityDecidesSelectability(opacity: Double, expected: Bool) {
        #expect(FileListRow(isDirectory: false, textOpacity: opacity).isSelectable == expected)
    }

    @Test("AXEnabled が false なら、文字色に関わらず選べない")
    func disabledIsUnselectable() {
        #expect(FileListRow(isDirectory: false, isEnabled: false, textOpacity: 0.85).isSelectable == false)
        #expect(FileListRow(isDirectory: false, isEnabled: false).isSelectable == false)
    }

    @Test("文字色を読めなければ、AXEnabled が true でも判断しない（リスト表示・カラム表示では選べない行も true のため）")
    func enabledWithoutTextOpacityIsUnknown() {
        #expect(FileListRow(isDirectory: false, isEnabled: true).isSelectable == nil)
        #expect(FileListRow(isDirectory: false).isSelectable == nil)
    }
}
