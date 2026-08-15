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
        button.image = Self.renderCapsule(text: text, status: model.status)
        button.imageScaling = .scaleNone
    }

    /// 绘制 DSH 浅蓝胶囊图：亮浅蓝渐变底 + 深蓝粗字 + 状态点 + 鲸鱼娘，最小宽 140
    static func renderCapsule(text: String, status: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let iconW: CGFloat = 24
        let dotW: CGFloat = 11
        let padding: CGFloat = 18
        let height: CGFloat = 24
        let width = max(140, iconW + textSize.width + dotW + padding * 2)

        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        defer { img.unlockFocus() }

        // 亮浅蓝渐变胶囊（上 #A8CCFF → 下 #7FA8F0）
        let capsule = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                   xRadius: height / 2, yRadius: height / 2)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.659, green: 0.800, blue: 1.0, alpha: 1),    // #A8CCFF
            NSColor(calibratedRed: 0.498, green: 0.659, blue: 0.941, alpha: 1),  // #7FA8F0
        ])
        gradient?.draw(in: capsule, angle: -90)
        // 细边框（深一档）
        NSColor(calibratedRed: 0.35, green: 0.47, blue: 0.75, alpha: 0.9).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        // 顶部细高光
        NSColor(calibratedWhite: 1, alpha: 0.45).setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: height - 10, width: width - 4, height: 7),
                     xRadius: 3, yRadius: 3).fill()

        // 鲸鱼娘半身（左侧）
        if let icon = Self.loadMenuIcon() {
            icon.draw(in: NSRect(x: padding, y: 2, width: 20, height: 20))
        }
        // 状态点（文字前）
        let dotX = padding + iconW + 2
        let dotColor: NSColor
        switch status {
        case "waitingApproval": dotColor = NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.10, alpha: 1)
        case "running", "processing": dotColor = NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.72, alpha: 1)
        default: dotColor = NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.62, alpha: 1)
        }
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotX, y: height / 2 - 3, width: 6, height: 6)).fill()

        // 深蓝粗体状态文字
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.37, alpha: 1),
        ]
        let textX = dotX + dotW + 1
        (text as NSString).draw(at: NSPoint(x: textX, y: 4), withAttributes: attrs)

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
