// StatusBarController.swift —— 菜单栏灵动岛托盘。
// 常驻 macOS 顶部菜单栏（NSStatusItem）：鲸鱼娘半身 + 状态文字的宽胶囊，
// 点击弹出 NSPopover 灵动岛面板（SwiftUI 弹性展开），审批直接在面板上点。
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
        // DSH 浅蓝胶囊托盘：合成胶囊图（button.image），完全可控
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.toolTip = "dsh-island — DeepSeek Harness 灵动岛"
            button.imagePosition = .imageOnly
            refreshButton()
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false   // 用 SwiftUI 弹性动画，不用系统淡入
        popover.contentSize = NSSize(width: 400, height: 340)
        self.popover = popover

        // 模型变化 → 刷新菜单栏按钮（重绘胶囊图）
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

    /// 加载半身鲸鱼娘图标（<exec>/whale2/menu-icon.png，开发时回退源码目录）
    static func loadMenuIcon() -> NSImage? {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundled = execDir.appendingPathComponent("whale2/menu-icon.png")
        let source = execDir.deletingLastPathComponent().appendingPathComponent("panel/resources/whale2/menu-icon.png")
        let url = FileManager.default.fileExists(atPath: bundled.path) ? bundled : source
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 20)
        return img
    }

    // MARK: 按钮状态

    private func refreshButton() {
        guard let button = statusItem?.button else { return }
        let text: String
        switch model.status {
        case "waitingApproval": text = "等待授权"
        case "running", "processing": text = model.currentTool.map { "\($0)" } ?? "运行中"
        case "idle": text = "空闲"
        default: text = "DSH"
        }
        button.image = Self.renderCapsule(text: text)
        button.imageScaling = .scaleNone
    }

    /// 绘制 DSH 浅蓝胶囊图（配色取自 dsh-web-ui blue-fantasy 皮肤）：
    /// 浅蓝 #7f96d2 底 + 深蓝 #2c3765 字 + 鲸鱼娘半身，最小宽度保证够宽
    static func renderCapsule(text: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let iconW: CGFloat = 20
        let padding: CGFloat = 16
        let height: CGFloat = 22
        // 最小宽度 108：文字短也保持宽胶囊
        let width = max(108, iconW + textSize.width + padding * 2)

        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        defer { img.unlockFocus() }

        // blue-fantasy 浅蓝 #7f96d2 胶囊
        let capsule = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                   xRadius: height / 2, yRadius: height / 2)
        NSColor(calibratedRed: 0.498, green: 0.588, blue: 0.824, alpha: 1).setFill()  // #7f96d2
        capsule.fill()
        // 顶部细高光
        NSColor(calibratedWhite: 1, alpha: 0.30).setFill()
        NSBezierPath(roundedRect: NSRect(x: 1.5, y: height - 9, width: width - 3, height: 6),
                     xRadius: 3, yRadius: 3).fill()

        // 鲸鱼娘半身（左侧）
        if let icon = Self.loadMenuIcon() {
            icon.draw(in: NSRect(x: padding, y: 2, width: 18, height: 18))
        }
        // 深蓝 #2c3765 状态文字
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.173, green: 0.216, blue: 0.396, alpha: 1),
        ]
        let textX = padding + iconW + 5
        (text as NSString).draw(at: NSPoint(x: textX, y: 3.5), withAttributes: attrs)

        return img
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
