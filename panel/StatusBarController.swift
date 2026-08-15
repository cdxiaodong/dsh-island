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
    /// 其他插件注册的菜单项（DSH 侧通过 socket 推送）
    private var pluginItems: [PluginMenuItem] = []
    /// DSH 运行时插件列表（动态监测）
    private var pluginList: [IslandPlugin] = []
    // 托盘鲸鱼娘动画
    private var whaleTimer: AnyCancellable?
    private var whaleFrameIndex = 0
    private var whaleAction = "idle"
    private var whaleWigglePhase: CGFloat = 0
    private var whaleFrameAccum: Double = 0
    private let whaleTickInterval: Double = 0.1

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
            button.sendAction(on: [.leftMouseUp])   // 左键触发 action，右键弹 menu
            button.toolTip = "dsh-island — DeepSeek Harness 灵动岛"
            button.menu = buildMenu()   // 右键菜单
        }
        self.statusItem = item

        // 模型变化 → 刷新菜单栏胶囊 + 右键菜单
        cancellable = model.objectWillChange.sink { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshButton()
                self?.statusItem?.button?.menu = self?.buildMenu()
            }
        }

        // 托盘鲸鱼娘动画：每 0.1s 推进一帧，重绘胶囊
        whaleTimer = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.tickWhale() }
            }

        // 预加载所有鲸鱼娘动作帧（避免首次打开面板时磁盘 I/O 导致延迟）
        Task { @MainActor in
            let states = Array(Whale2Assets.states.keys)
            for state in states {
                _ = Whale2Assets.frames(for: state)
                _ = Whale2Assets.halfFrames(for: state)
                await Task.yield()   // 分帧加载，不卡 UI
            }
        }
    }

    func hide() {
        panel?.orderOut(nil)
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
        panel = nil
    }

    /// 面板失去 key（点击外部/其他 app）→ 关闭展示框
    @objc private func panelDidResignKey(_ note: Notification) {
        fputs("[dsh-island-panel] panelDidResignKey → close\n", stderr)
        panel?.orderOut(nil)
    }

    // MARK: 按钮状态

    private func refreshButton() {
        guard let button = statusItem?.button else { return }
        let frames = Whale2Assets.halfFrames(for: whaleAction)
        let frame = frames.isEmpty ? nil : frames[min(whaleFrameIndex, max(frames.count - 1, 0))]
        let wiggle = wiggleOffset()
        button.image = Self.renderCapsule(text: model.trayText, status: model.status,
                                          whaleFrame: frame, wiggleX: wiggle.0, wiggleY: wiggle.1)
        button.imageScaling = .scaleNone
    }

    // MARK: 托盘鲸鱼娘动画

    private func tickWhale() {
        let action = currentWhaleAction()
        if action != whaleAction { whaleAction = action; whaleFrameIndex = 0; whaleWigglePhase = 0; whaleFrameAccum = 0 }
        let frames = Whale2Assets.halfFrames(for: whaleAction)
        // 按动作 fps 控制帧速度：idle 慢眨眼 / walk 快 / error 抖
        whaleFrameAccum += whaleTickInterval
        let fps = Whale2Assets.fps(for: whaleAction)
        if frames.count > 1, whaleFrameAccum >= 1.0 / max(fps, 0.1) {
            whaleFrameAccum = 0
            whaleFrameIndex = (whaleFrameIndex + 1) % frames.count
        }
        // 单帧动作（wait/think/error）用位置动画让它动起来
        whaleWigglePhase += 0.35
        refreshButton()
    }

    /// 根据 DSH 状态/情绪决定协调的鲸鱼娘动作
    private func currentWhaleAction() -> String {
        if let mood = model.mood { return mood == "celebrate" ? "celebrate" : "error" }
        switch model.status {
        case "waitingApproval": return "wait"            // 等待审批 → wait 摆动
        case "running", "processing": return Bool.random() ? "working" : "think"
        default: return "idle"
        }
    }

    /// 单帧动作的位置动效（whale-girl 的 wiggle/float/shake）
    private func wiggleOffset() -> (CGFloat, CGFloat) {
        let p = whaleWigglePhase
        switch whaleAction {
        case "wait": return (sin(p) * 3, 0)         // 水平摆动（等待）
        case "think": return (0, sin(p) * 2)        // 上下浮动（思考）
        case "error": return (sin(p * 3) * 3, 0)    // 抖动（出错）
        default: return (0, 0)
        }
    }

    // MARK: 插件菜单

    /// 更新插件注册的菜单项（由 SocketServer 收到 menu_set 时调用）
    func updatePluginMenu(_ items: [PluginMenuItem]) {
        pluginItems = items
        statusItem?.button?.menu = buildMenu()
    }

    /// 更新插件列表（由 SocketServer 收到 plugin_list 时调用）
    func updatePluginList(_ plugins: [IslandPlugin]) {
        pluginList = plugins
        statusItem?.button?.menu = buildMenu()
        fputs("[dsh-island-panel] plugins: \(plugins.map(\.title).joined(separator: ", "))\n", stderr)
    }

    @objc private func pluginMenuItemClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        sendCtlCommand("menu_click", id)
    }

    /// 点击插件管理项 → 启用/关闭插件
    @objc private func pluginToggleClicked(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String,
              let plugin = pluginList.first(where: { $0.id == id }) else { return }
        sendCtlCommand(plugin.running ? "plugin_disable" : "plugin_enable", id)
    }

    /// 发命令到 DSH 插件的控制 socket
    private func sendCtlCommand(_ type: String, _ id: String) {
        let path = SocketServer.ctlSocketPath
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        let conn = NWConnection(to: .unix(path: path), using: params)
        conn.start(queue: .main)
        guard let body = try? JSONSerialization.data(withJSONObject: ["type": type, "id": id]) else { return }
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
        // 插件管理（动态监测 DSH 插件 + 启用/关闭）
        if !pluginList.isEmpty {
            let submenu = NSMenu()
            for p in pluginList {
                let mark = p.running ? "●" : "○"
                let mi = NSMenuItem(title: "\(mark) \(p.title)", action: #selector(pluginToggleClicked(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = p.id
                mi.state = p.running ? .on : .off
                submenu.addItem(mi)
            }
            let pluginMenu = NSMenuItem(title: "插件管理", action: nil, keyEquivalent: "")
            pluginMenu.submenu = submenu
            menu.addItem(pluginMenu)
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
        fputs("[dsh-island-panel] togglePanel\n", stderr)
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard let button = statusItem?.button, let window = button.window else {
            fputs("[dsh-island-panel] showPanel: no button/window\n", stderr)
            return
        }
        fputs("[dsh-island-panel] showPanel: opening\n", stderr)

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
        self.panel = p

        // 面板失去 key（点击外部/其他 app）→ 关闭
        NotificationCenter.default.addObserver(
            self, selector: #selector(panelDidResignKey),
            name: NSWindow.didResignKeyNotification, object: p
        )

        // 用按钮屏幕坐标定位：面板顶部紧贴按钮底部，水平居中
        let btnRect = window.convertToScreen(button.convert(button.bounds, to: nil))
        let x = btnRect.midX - panelSize.width / 2
        let y = btnRect.minY - panelSize.height
        p.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
        p.orderFrontRegardless()
        p.makeKey()
    }

    // MARK: 胶囊图

    /// 绘制 DSH 浅蓝胶囊图：浅蓝渐变底 + 深蓝粗字 + 状态点 + 鲸鱼娘半身，最小宽 155
    /// - Parameters:
    ///   - whaleFrame: 半身鲸鱼娘动画帧（完整 PNG，aspect-fit 绘制）；nil 用静态半身图标
    ///   - wiggleX/Y: 鲸鱼娘位置偏移（单帧动作的摆动/浮动/抖动动效）
    static func renderCapsule(text: String, status: String, whaleFrame: NSImage? = nil,
                              wiggleX: CGFloat = 0, wiggleY: CGFloat = 0) -> NSImage {
        let font = NSFont.systemFont(ofSize: 12.5, weight: .bold)
        let textSize = (text as NSString).size(withAttributes: [.font: font])
        let iconW: CGFloat = 38
        let dotW: CGFloat = 11
        let padding: CGFloat = 14
        let height: CGFloat = 24
        let width = max(155, iconW + textSize.width + dotW + padding * 2)

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

        // 鲸鱼娘半身（完整 PNG，aspect-fit 不裁剪）
        if let frame = whaleFrame {
            let target = NSRect(x: padding, y: 1, width: iconW, height: 22)
            let fw = max(frame.size.width, 1), fh = max(frame.size.height, 1)
            let scale = min(target.width / fw, target.height / fh)
            let dw = fw * scale, dh = fh * scale
            let rect = NSRect(x: target.midX - dw / 2 + wiggleX,
                              y: target.midY - dh / 2 + wiggleY,
                              width: dw, height: dh)
            frame.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        } else if let icon = Self.loadMenuIcon() {
            icon.draw(in: NSRect(x: padding, y: 2, width: 22, height: 22))
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
