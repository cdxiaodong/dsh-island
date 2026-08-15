// StatusBarController.swift —— 菜单栏灵动岛。
// 常驻 macOS 顶部菜单栏（NSStatusItem），按钮文案随 DSH 状态动态变化：
//   空闲  🐋
//   运行  🔧 <当前工具> / 🔧 运行中
//   审批  🛡️ 需要授权
// 点击按钮弹出 NSPopover 灵动岛面板（SwiftUI），审批直接在面板上点。
import AppKit
import SwiftUI
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let model: PanelModel
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var cancellable: AnyCancellable?

    init(model: PanelModel) {
        self.model = model
        super.init()
    }

    func show() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "dsh-island — DeepSeek Harness 灵动岛"
            refreshButton()
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
        popover.contentSize = NSSize(width: 400, height: 340)
        self.popover = popover

        // 模型变化 → 刷新菜单栏按钮文案
        cancellable = model.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshButton() }
        }
    }

    func hide() {
        popover?.performClose(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    // MARK: 按钮状态

    private func refreshButton() {
        guard let button = statusItem?.button else { return }
        let text: String
        switch model.status {
        case "waitingApproval":
            text = "🛡️ 需要授权"
        case "running", "processing":
            if let tool = model.currentTool {
                text = "🔧 \(tool)"
            } else {
                text = "🔧 运行中"
            }
        default:
            text = "🐋 DSH"
        }
        button.title = text
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
