// main.swift —— dsh-island-panel 入口。
// 一个无 Dock 图标的辅助进程：监听 Unix socket，把 DSH 事件渲染成 macOS 刘海灵动岛。
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

    let controller = PanelWindowController(model: model)
    controller.show()

    app.run()
}
