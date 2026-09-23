import Testing

import OpenPathCore

@Suite("PaletteEvent")
struct PaletteEventTests {
    @Test("確定は AppCoordinator の confirm に対応する", arguments: [false, true])
    func confirmMapsToCoordinatorConfirm(openImmediately: Bool) {
        let event = PaletteEvent.confirm(path: "/Users/example/repos/fern", openImmediately: openImmediately)

        #expect(event.coordinatorEvent == .confirm(path: "/Users/example/repos/fern", openImmediately: openImmediately))
    }

    @Test("閉じる操作は AppCoordinator の escape に対応する")
    func dismissMapsToCoordinatorEscape() {
        #expect(PaletteEvent.dismiss.coordinatorEvent == .escape)
    }
}
