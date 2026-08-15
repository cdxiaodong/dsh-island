// StatusBarController.swift —— 菜单栏灵动岛托盘 + NSPanel 面板。
// 菜单栏按钮：浅蓝胶囊（鲸鱼娘 + 状态点 + 文字）。
// 点击 → NSPanel 无边框面板，用「按钮屏幕坐标」精确定位到按钮正下方，
// 修复 NSPopover 在 NSSceneStatusItem 下的坐标偏移问题；NSPanel 保证可交互。
import AppKit
import SwiftUI
import Combine
import Network

private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// borderless 窗口第一次点击会被系统拿去激活，导致按钮点不中 —— 借鉴 CodeIsland：
/// mouseDown 先 makeKey + acceptsFirstMouse，让第一次点击直接触达 SwiftUI。
private class IslandHostingView<Content: View>: NSHostingView<Content> {
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        super.mouseDown(with: event)
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class StatusBarController: NSObject {
    private let model: PanelModel
    private var statusItem: NSStatusItem?
    private var panel: KeyablePanel?
    private var cancellable: AnyCancellable?
    private var clickMonitor: Any?
    /// 其他插件注册的菜单项（DSH 侧通过 socket 推送）
    private var pluginItems: [PluginMenuItem] = []

    private let panelSize = NSSize(width: 400, height: 360)

    init(model: PanelModel) {
        self.model = model
        super.init()
    }

    func show() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = Self.renderCapsule(text: "空闲", status: "idle")
            button.imageScaling = .scaleNone
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.toolTip = "dsh-island — DeepSeek Harness 灵动岛"
            button.menu = buildMenu()   // 右键菜单
        }
        self.statusItem = item

        // 点击面板外部关闭
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel, panel.isVisible else { return event }
            // 点在面板内 → 放行（可交互）；点在托盘按钮 → 放行（toggle 处理）；其他 → 关闭
            if event.window === panel { return event }
            if event.window === self.statusItem?.button?.window { return event }
            panel.orderOut(nil)
            return event
        }

        // 模型变化 → 刷新菜单栏胶囊 + 右键菜单
        cancellable = model.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshButton()
                self?.statusItem?.button?.menu = self?.buildMenu()
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        panel = nil
    }

    // MARK: 按钮状态

    private func refreshButton() {
        guard let button = statusItem?.button else { return }
        button.image = Self.renderCapsule(text: model.trayText, status: model.status)
        button.imageScaling = .scaleNone
    }

    // MARK: 插件菜单

    /// 更新插件注册的菜单项（由 SocketServer 收到 menu_set 时调用）
    func updatePluginMenu(_ items: [PluginMenuItem]) {
        pluginItems = items
        statusItem?.button?.menu = buildMenu()
    }

    @objc private func pluginMenuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        sendMenuClick(id)
    }

    /// 点击插件菜单项 → 连接 DSH 插件的控制 socket，发 menu_click
    private func sendMenuClick(_ id: String) {
        let path = SocketServer.ctlSocketPath
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        let conn = NWConnection(to: .unix(path: path), using: params)
        conn.start(queue: .main)
        guard let body = try? JSONSerialization.data(withJSONObject: ["type": "menu_click", "id": id]) else { return }
        conn.send(content: body, completion: .contentProcessed { _ in
            Task { @MainActor in conn.cancel() }
        })
    }

    // MARK: 右键菜单

    /// 构建托盘右键菜单（状态 + 动态统计 + 打开面板 + 退出）
    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // 状态标题
        let statusItem = NSMenuItem(
            title: "dsh-island · \(statusLabel)",
            action: nil, keyEquivalent: ""
        )
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())
        // 动态统计
        let stats = NSMenuItem(
            title: "工具 \(model.toolCount) 次 · 子代理 \(model.subagentCount) · \(elapsedText)",
            action: nil, keyEquivalent: ""
        )
        stats.isEnabled = false
        menu.addItem(stats)
        menu.addItem(.separator())
        // 打开面板
        let openItem = NSMenuItem(title: "打开灵动岛面板", action: #selector(togglePanel(_:)), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        // 会话信息
        if model.sessionStart != nil {
            let session = NSMenuItem(
                title: "会话 \(model.sessionId)", action: nil, keyEquivalent: ""
            )
            session.isEnabled = false
            menu.addItem(session)
        }
        // 其他插件注册的菜单项（注册接口：DSH 插件 ctx.island.registerMenuItem）
        if !pluginItems.isEmpty {
            menu.addItem(.separator())
            for item in pluginItems {
                let title = item.icon.map { "\($0) \(item.title)" } ?? item.title
                let mi = NSMenuItem(title: title, action: #selector(pluginMenuItemClicked(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = item.id
                menu.addItem(mi)
            }
        }
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 dsh-island", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        return menu
    }

    private var statusLabel: String {
        switch model.status {
        case "running", "processing": return "运行中"
        case "waitingApproval": return "等待授权"
        case "idle": return "空闲"
        default: return model.status
        }
    }

    private var elapsedText: String {
        guard let start = model.sessionStart else { return "无会话" }
        return "\(PanelModel.formatElapsed(since: start))"
    }

    // MARK: 面板显示

    @objc private func togglePanel(_ sender: Any?) {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button, let window = button.window else { return }

        // 重建面板（每次打开 → PanelView @State 重置 → 弹性动画重播）
        let hosting = IslandHostingView(rootView: PanelView(model: model))
        hosting.frame = NSRect(origin: .zero, size: panelSize)

        let p = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.contentView = hosting
        p.hidesOnDeactivate = false
        self.panel = p

        // 用按钮屏幕坐标定位：面板顶部紧贴按钮底部，水平居中
        let btnRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let x = btnRect.midX - panelSize.width / 2
        let y = btnRect.minY - panelSize.height
        p.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
        p.orderFrontRegardless()
        p.makeKey()
    }

    // MARK: 胶囊图

    /// 绘制 DSH 浅蓝胶囊图：浅蓝渐变底 + 深蓝粗字 + 状态点 + 鲸鱼娘，最小宽 130
    static func renderCapsule(text: String, status: String) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let iconW: CGFloat = 24
        let dotW: CGFloat = 11
        let padding: CGFloat = 18
        let height: CGFloat = 24
        let width = max(130, iconW + textSize.width + dotW + padding * 2)

        let img = NSImage(size: NSSize(width: width, height: height))
        img.lockFocus()
        defer { img.unlockFocus() }

        let capsule = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: width, height: height),
                                   xRadius: height / 2, yRadius: height / 2)
        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.659, green: 0.800, blue: 1.0, alpha: 1),    // #A8CCFF
            NSColor(calibratedRed: 0.498, green: 0.659, blue: 0.941, alpha: 1),  // #7FA8F0
        ])
        gradient?.draw(in: capsule, angle: -90)
        NSColor(calibratedRed: 0.35, green: 0.47, blue: 0.75, alpha: 0.9).setStroke()
        capsule.lineWidth = 1
        capsule.stroke()
        NSColor(calibratedWhite: 1, alpha: 0.45).setFill()
        NSBezierPath(roundedRect: NSRect(x: 2, y: height - 10, width: width - 4, height: 7),
                     xRadius: 3, yRadius: 3).fill()

        if let icon = Self.loadMenuIcon() {
            icon.draw(in: NSRect(x: padding, y: 2, width: 20, height: 20))
        }
        let dotX = padding + iconW + 2
        let dotColor: NSColor
        switch status {
        case "waitingApproval": dotColor = NSColor(calibratedRed: 0.96, green: 0.72, blue: 0.10, alpha: 1)
        case "running", "processing": dotColor = NSColor(calibratedRed: 0.05, green: 0.62, blue: 0.72, alpha: 1)
        default: dotColor = NSColor(calibratedRed: 0.30, green: 0.42, blue: 0.62, alpha: 1)
        }
        dotColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: dotX, y: height / 2 - 3, width: 6, height: 6)).fill()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(calibratedRed: 0.09, green: 0.19, blue: 0.37, alpha: 1),
        ]
        let textX = dotX + dotW + 1
        (text as NSString).draw(at: NSPoint(x: textX, y: 4), withAttributes: attrs)

        return img
    }

    /// 加载半身鲸鱼娘图标
    static func loadMenuIcon() -> NSImage? {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundled = execDir.appendingPathComponent("whale2/menu-icon.png")
        let source = execDir.deletingLastPathComponent().appendingPathComponent("panel/resources/whale2/menu-icon.png")
        let url = FileManager.default.fileExists(atPath: bundled.path) ? bundled : source
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 20, height: 20)
        return img
    }
}
