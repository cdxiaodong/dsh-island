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
            // 半身鲸鱼娘常驻在按钮左边
            button.image = Self.loadMenuIcon()
            button.imagePosition = .imageLeading
            button.imageScaling = .scaleProportionallyDown
            refreshButton()
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false   // 用 SwiftUI 弹性动画，不用系统淡入
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

    // MARK: 菜单栏图标（半身鲸鱼娘）

    /// 加载半身鲸鱼娘图标（<exec>/whale/menu-icon.png，开发时回退源码目录）
    static func loadMenuIcon() -> NSImage? {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundled = execDir.appendingPathComponent("whale/menu-icon.png")
        let source = execDir.deletingLastPathComponent().appendingPathComponent("panel/resources/whale/menu-icon.png")
        let url = FileManager.default.fileExists(atPath: bundled.path) ? bundled : source
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 17, height: 19)
        return img
    }

    // MARK: 按钮状态

    private func refreshButton() {
        guard let button = statusItem?.button else { return }
        let text: String
        let color: NSColor
        switch model.status {
        case "waitingApproval":
            text = "等待授权"
            color = .systemYellow
        case "running", "processing":
            text = model.currentTool.map { "\($0)" } ?? "运行中"
            color = .systemCyan
        case "idle":
            text = "DSH"
            color = .labelColor
        default:
            text = "DSH"
            color = .labelColor
        }
        button.attributedTitle = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .medium),
                .foregroundColor: color,
            ]
        )
    }

    // MARK: Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            // 每次打开重建视图 → PanelView 的 @State 重置 → 弹性展开动画重播
            popover.contentViewController = NSHostingController(rootView: PanelView(model: model))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
