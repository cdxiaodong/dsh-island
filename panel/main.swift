// main.swift —— dsh-island-panel 入口。
// 无 Dock 图标的辅助进程：监听 Unix socket，DSH 状态显示为 macOS 菜单栏灵动岛。
import AppKit
import SwiftUI

// 顶层代码运行在主线程；用 assumeIsolated 让 @MainActor 的组件安全初始化
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)

    let model = PanelModel()
    let server = SocketServer(model: model)
    ModelResponder.server = server
    server.start()

    let controller = StatusBarController(model: model)
    controller.show()

    app.run()
}
