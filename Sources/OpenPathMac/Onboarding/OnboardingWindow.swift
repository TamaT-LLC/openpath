import AppKit
import SwiftUI

import OpenPathCore

/// 初回起動の案内のウインドウ（UX-001 §7）。ページの内容を出すだけの薄いアダプタで、遷移は OnboardingController が決める。
///
/// ボタン・Esc・クローズボタンはすべて `onCommand` で知らせる（クローズボタンは `.close`）。
/// クローズボタンでもウインドウは自分では閉じず、`dismiss()` で閉じる（閉じるかどうかは OnboardingFlow が決める）。
@MainActor
final class OnboardingWindow: NSObject {
    /// ボタンが選ばれた・クローズボタンで閉じられたときに呼ばれる
    var onCommand: ((OnboardingCommand) -> Void)?

    private let window: NSWindow
    private let hostingView: NSHostingView<OnboardingView?>
    private var hasBeenPositioned = false

    override init() {
        hostingView = NSHostingView(rootView: nil)
        window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: true)
        super.init()
        window.title = OnboardingPage.windowTitle
        // 閉じた後も同じウインドウを出し直すため、閉じても解放させない
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.delegate = self
    }

    /// ページを出して前面に出す。表示中なら内容を差し替える。
    func present(_ page: OnboardingPage) {
        hostingView.rootView = OnboardingView(page: page) { [weak self] command in
            self?.onCommand?(command)
        }
        // setContentSize は左下を基準に大きさを変えるため、ページを替えても上端が動かないよう左上を保つ
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(hostingView.fittingSize)
        if hasBeenPositioned {
            window.setFrameTopLeftPoint(topLeft)
        } else {
            window.center()
            hasBeenPositioned = true
        }
        // 常駐アプリ（accessory）は前面にいないため、前面に出さないと他のウインドウの裏に隠れる。
        // 権限の付与を待つ間はシステム設定が前面にあり、アクティブにできないことがあるため orderFrontRegardless でも出す
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    /// ウインドウを閉じる。
    func dismiss() {
        window.orderOut(nil)
    }
}

extension OnboardingWindow: NSWindowDelegate {
    /// 利用者がクローズボタンを押したときだけ呼ばれる。windowWillClose はアプリの終了で閉じられるときにも届き、
    /// 案内を終えたと誤って記録してしまうため使わない
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCommand?(.close)
        return false
    }
}
