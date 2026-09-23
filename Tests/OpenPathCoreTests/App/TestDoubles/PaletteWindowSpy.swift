import CoreGraphics

import OpenPathCore

/// パレットのウィンドウへの操作を順番どおりに記録する。
@MainActor
final class PaletteWindowSpy: PaletteWindowControlling {
    enum Call: Equatable {
        /// 表示した。rowCount はその時点の高さの計算に使う行数
        case show(near: CGRect, rowCount: Int)
        case hide
        case releaseKey
        case reclaimKey
    }

    private(set) var calls: [Call] = []
    var rowCount = 0

    func show(near panelFrame: CGRect) {
        calls.append(.show(near: panelFrame, rowCount: rowCount))
    }

    func hide() {
        calls.append(.hide)
    }

    func releaseKey() {
        calls.append(.releaseKey)
    }

    func reclaimKey() {
        calls.append(.reclaimKey)
    }
}
