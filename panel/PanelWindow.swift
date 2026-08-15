// PanelWindow.swift —— 无边框 NSPanel，附着在屏幕顶部居中（notch 区域）。
// 借鉴 CodeIsland 的 PanelWindowController：constrainFrameRect 返回原 frame，
// 防止 AppKit 把面板 clamp 到菜单栏下方导致脱离刘海。
import AppKit
import SwiftUI

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}

/// borderless + nonactivatingPanel 的窗口第一次点击会被系统拿去激活窗口，
/// 导致按钮点不中。借鉴 CodeIsland：mouseDown 先 makeKey，acceptsFirstMouse=true，
/// 让第一次点击就直接触达 SwiftUI 视图。
private class NotchHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class PanelWindowController: NSObject, NSWindowDelegate {
    private let model: PanelModel
    private var panel: KeyablePanel?

    init(model: PanelModel) {
        self.model = model
    }

    func show() {
        guard let screen = NSScreen.main else { return }
        let width: CGFloat = 448
        let height: CGFloat = 340

        let hosting = NotchHostingView(rootView: PanelView(model: model))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: height)

        let p = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: NSSize(width: width, height: height)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.contentView = hosting
        p.delegate = self
        self.panel = p

        // 屏幕顶部居中
        let x = screen.frame.midX - width / 2
        let y = screen.frame.maxY - height
        p.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        p.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }
}
