import CoreGraphics
import Foundation
import Testing

import OpenPathCore

@Suite("PanelWatchLogMessage（パネルの検知のログの文言）")
struct PanelWatchLogMessageTests {
    private static let panelID = PanelContext.ID(rawValue: "open-panel-3")

    private static func context(isDirectoriesOnly: Bool) -> PanelContext {
        PanelContext(id: panelID, isDirectoriesOnly: isDirectoriesOnly, frame: CGRect(x: 10, y: 20, width: 800, height: 500))
    }

    @Test(
        "panel detected に、選択モードと推定に使った行の内訳を続ける",
        arguments: [
            (
                PanelSelectionEstimate(mode: .directoriesOnly, sampledRowCount: 4, sampledDirectoryCount: 2, sampledFileCount: 2),
                "panel detected (id: open-panel-3, directoriesOnly: true, selectionMode: directoriesOnly, "
                    + "sampledRows: 4, sampledDirectories: 2, sampledFiles: 2)"
            ),
            (
                PanelSelectionEstimate(mode: .undetermined, sampledRowCount: 15, sampledDirectoryCount: 15, sampledFileCount: 0),
                "panel detected (id: open-panel-3, directoriesOnly: false, selectionMode: undetermined, "
                    + "sampledRows: 15, sampledDirectories: 15, sampledFiles: 0)"
            ),
            (
                PanelSelectionEstimate(mode: .filesSelectable, sampledRowCount: 2, sampledDirectoryCount: 1, sampledFileCount: 1),
                "panel detected (id: open-panel-3, directoriesOnly: false, selectionMode: filesSelectable, "
                    + "sampledRows: 2, sampledDirectories: 1, sampledFiles: 1)"
            ),
        ]
    )
    func panelDetected(estimate: PanelSelectionEstimate, expected: String) {
        let context = Self.context(isDirectoriesOnly: estimate.mode.isDirectoriesOnly)

        #expect(PanelWatchLogMessage.panelDetected(context, estimate: estimate) == expected)
    }

    @Test("推定の結果が分からなければ、これまでどおり directoriesOnly までを出す")
    func panelDetectedWithoutEstimate() {
        #expect(
            PanelWatchLogMessage.panelDetected(Self.context(isDirectoriesOnly: false), estimate: nil)
                == "panel detected (id: open-panel-3, directoriesOnly: false)"
        )
    }

    @Test("panel updated も同じ書式で出す")
    func panelUpdated() {
        let estimate = PanelSelectionEstimate(mode: .directoriesOnly, sampledRowCount: 3, sampledDirectoryCount: 1, sampledFileCount: 2)

        #expect(
            PanelWatchLogMessage.panelUpdated(Self.context(isDirectoriesOnly: true), estimate: estimate)
                == "panel updated (id: open-panel-3, directoriesOnly: true, selectionMode: directoriesOnly, "
                + "sampledRows: 3, sampledDirectories: 1, sampledFiles: 2)"
        )
        #expect(PanelWatchLogMessage.panelGone == "panel gone")
    }

    @Test("スモークスクリプトが読む部分（先頭の「panel detected (id: …,」と「directoriesOnly: true」）を保つ")
    func keepsSmokeScriptContract() throws {
        let estimate = PanelSelectionEstimate(mode: .directoriesOnly, sampledRowCount: 1, sampledDirectoryCount: 0, sampledFileCount: 1)
        let message = PanelWatchLogMessage.panelDetected(Self.context(isDirectoriesOnly: true), estimate: estimate)

        // scripts/smoke-open-panel.sh の panel_id_of と同じ正規表現 `\(id: ([^,)]+)`
        let regex = try NSRegularExpression(pattern: #"\(id: ([^,)]+)"#)
        let match = try #require(regex.firstMatch(in: message, range: NSRange(message.startIndex..., in: message)))
        let idRange = try #require(Range(match.range(at: 1), in: message))

        #expect(message.hasPrefix("panel detected (id: open-panel-3, directoriesOnly: "))
        #expect(message[idRange] == "open-panel-3")
        #expect(message.contains("directoriesOnly: true"))
        // 推定できない・ファイルも選べる場合に「directoriesOnly: true」を含まない
        let undetermined = PanelWatchLogMessage.panelDetected(
            Self.context(isDirectoriesOnly: false),
            estimate: PanelSelectionEstimate(mode: .undetermined, sampledRowCount: 0, sampledDirectoryCount: 0, sampledFileCount: 0)
        )
        #expect(!undetermined.contains("directoriesOnly: true"))
    }
}
