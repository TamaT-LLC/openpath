import CoreGraphics
import Testing

import OpenPathCore

@Suite("PanelContext: 候補の絞り込み")
struct PanelContextCandidateFilterTests {
    private static func panel(isDirectoriesOnly: Bool) -> PanelContext {
        PanelContext(
            id: PanelContext.ID(rawValue: "panel"),
            isDirectoriesOnly: isDirectoriesOnly,
            frame: CGRect(x: 0, y: 0, width: 800, height: 600)
        )
    }

    @Test(
        "フォルダのみのパネルは include_files に関わらずディレクトリだけ、それ以外は include_files に従う",
        arguments: [
            (isDirectoriesOnly: true, includeFiles: true, expected: true),
            (isDirectoriesOnly: true, includeFiles: false, expected: true),
            (isDirectoriesOnly: false, includeFiles: true, expected: false),
            (isDirectoriesOnly: false, includeFiles: false, expected: true),
        ]
    )
    func directoriesOnly(isDirectoriesOnly: Bool, includeFiles: Bool, expected: Bool) {
        let context = Self.panel(isDirectoriesOnly: isDirectoriesOnly)

        #expect(context.showsDirectoriesOnly(includeFiles: includeFiles) == expected)
    }
}
