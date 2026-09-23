import AppKit
import SwiftUI

import OpenPathCore

/// NSOpenPanel に重ねて表示する検索パレットのウィンドウ（ARCH-001 §4 PaletteWindow）。
///
/// フォーカスの扱い:
/// - `show(near:)` はパレットをキーウィンドウにするが、`NSApp.activate` は呼ばない。
///   non-activating panel なので最前面のアプリ（メニューバーの持ち主）はホストのまま変わらず、
///   ホストの `NSApp.keyWindow` も NSOpenPanel のまま残る。キー入力だけがパレットに届き、
///   その間は NSOpenPanel の `isKeyWindow` のみが false になる。
/// - `hide()` するとキー入力はホストのキーウィンドウ（NSOpenPanel）へ戻る。ホストの再アクティブ化は不要。
/// - PanelInjector が CGEvent（Cmd+Shift+G など）を送る前には必ず `hide()` すること。
///   パレットがキーのままだとイベントがパレットに届いてしまう。
/// - ユーザーが NSOpenPanel をクリックすればキー入力はパネルへ移り、パレットは表示されたまま残る。
///   パレットを再度クリックすればまたパレットがキーになる。
///
/// 位置とサイズは `PalettePlacement` で計算する。入力の矩形は NSScreen 座標系（左下原点）。
@MainActor
public final class PaletteWindow<Content: View> {
    public let metrics: PaletteMetrics

    private let panel: PalettePanel
    private let hostingView: NSHostingView<Content>
    /// 行数の変更時に再配置するため、直近の配置基準（NSOpenPanel のフレーム）を保持する
    private var anchorPanelFrame: CGRect?

    /// パレット内に表示する SwiftUI ビュー。差し替えるとその場で再描画される。
    public var rootView: Content {
        get { hostingView.rootView }
        set { hostingView.rootView = newValue }
    }

    /// 表示中の候補数。高さの計算に使い、変更すると上端を保ったまま高さを変える。
    public var rowCount: Int = 0 {
        didSet {
            guard rowCount != oldValue, let anchorPanelFrame else { return }
            applyFrame(near: anchorPanelFrame)
        }
    }

    /// パレットが画面に表示されているか。
    public var isVisible: Bool { panel.isVisible }

    /// パレットがキー入力を受け取っているか。
    public var isKeyWindow: Bool { panel.isKeyWindow }

    /// キーイベントの監視で、イベントの送り先がパレットかどうかを判定するためのウィンドウ参照。
    public var window: NSWindow { panel }

    public init(rootView: Content, metrics: PaletteMetrics = .standard) {
        self.metrics = metrics
        panel = PalettePanel()
        hostingView = NSHostingView(rootView: rootView)
        // ウィンドウのサイズは PalettePlacement で決めるため、SwiftUI 側の内容サイズで上書きさせない
        hostingView.sizingOptions = []
        panel.contentView = PaletteChrome.makeContentView(containing: hostingView)
    }

    /// NSOpenPanel の近くにパレットを表示し、キー入力を受け取れる状態にする。
    /// openpath はアクティブにならないため、ホストアプリと NSOpenPanel は最前面のまま残る。
    public func show(near panelFrame: CGRect) {
        applyFrame(near: panelFrame)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    /// NSOpenPanel が移動・リサイズしたときに位置を合わせ直す。キーの状態と表示状態は変えない。
    public func reposition(near panelFrame: CGRect) {
        applyFrame(near: panelFrame)
    }

    /// パレットを隠す。キー入力はホストアプリのキーウィンドウ（NSOpenPanel）へ戻る。
    public func hide() {
        panel.orderOut(nil)
    }

    private func applyFrame(near panelFrame: CGRect) {
        anchorPanelFrame = panelFrame
        let frame = PalettePlacement.frame(
            panelFrame: panelFrame,
            visibleScreenFrame: PaletteChrome.visibleScreenFrame(for: panelFrame),
            rowCount: rowCount,
            metrics: metrics
        )
        panel.setFrame(frame, display: panel.isVisible)
        // 角丸の形状に合わせた影をサイズ変更後に作り直す
        panel.invalidateShadow()
    }
}

extension PaletteWindow where Content == PalettePlaceholderView {
    /// 本実装のビュー（#21）ができるまでの仮ビューで生成する。
    public convenience init(metrics: PaletteMetrics = .standard) {
        self.init(rootView: PalettePlaceholderView(metrics: metrics), metrics: metrics)
    }
}

/// パレットの見た目（角丸の半透明背景）と配置先の画面を扱う。
/// ジェネリック型には static stored property を置けないため、PaletteWindow から切り出している。
@MainActor
private enum PaletteChrome {
    private static let cornerRadius: CGFloat = 10
    private static let backgroundMaterial: NSVisualEffectView.Material = .popover

    static func visibleScreenFrame(for panelFrame: CGRect) -> CGRect {
        let screens = NSScreen.screens
        guard let index = PalettePlacement.screenIndex(for: panelFrame, screenFrames: screens.map(\.frame)) else {
            // 画面情報が取れない場合はパネル自身をクランプの基準にする
            return panelFrame
        }
        return screens[index].visibleFrame
    }

    static func makeContentView(containing hostingView: NSView) -> NSView {
        let background = NSVisualEffectView()
        background.material = backgroundMaterial
        background.blendingMode = .behindWindow
        // openpath は常に非アクティブなので、ウィンドウのアクティブ状態に追従させると常に淡色表示になる
        background.state = .active
        background.maskImage = roundedCornerMaskImage(cornerRadius: cornerRadius)

        hostingView.frame = background.bounds
        hostingView.autoresizingMask = [.width, .height]
        background.addSubview(hostingView)
        return background
    }

    /// 伸縮しても角の半径が変わらない角丸マスク（capInsets で四隅を固定する 9 スライス画像）。
    private static func roundedCornerMaskImage(cornerRadius: CGFloat) -> NSImage {
        // 四隅の円弧に加えて、伸縮させる中央の 1pt 分
        let stretchableCenterLength: CGFloat = 1
        let edgeLength = cornerRadius * 2 + stretchableCenterLength
        let image = NSImage(size: NSSize(width: edgeLength, height: edgeLength), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: cornerRadius, left: cornerRadius, bottom: cornerRadius, right: cornerRadius)
        image.resizingMode = .stretch
        return image
    }
}
