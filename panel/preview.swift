// preview.swift —— 离屏渲染 PanelView 为 PNG（开发预览用，不入插件包）。
// 编译：swiftc -swift-version 5 panel/PanelModel.swift panel/SocketServer.swift panel/PanelView.swift panel/preview.swift -o /tmp/preview
import AppKit
import SwiftUI

@main
struct PreviewMain {
    @MainActor static func main() {
        let m = PanelModel()
        m.cwd = "/Users/cdxd/projects/awesome-agent"
        m.status = "waitingApproval"
        m.handle(["hook_event_name": "SessionStart", "session_id": "s-1", "cwd": m.cwd, "_source": "dsh"])
        m.handle(["hook_event_name": "Notification", "session_id": "s-1", "message": "Agent status: processing", "_source": "dsh"])
        m.handle(["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Bash", "tool_input": ["command": "git status --short"], "_source": "dsh"])
        m.handle(["hook_event_name": "PostToolUse", "session_id": "s-1", "tool_name": "Bash", "_source": "dsh"])
        m.handle(["hook_event_name": "PreToolUse", "session_id": "s-1", "tool_name": "Bash", "tool_input": ["command": "rm -rf node_modules"], "_source": "dsh"])
        m.handle(["hook_event_name": "PermissionRequest", "session_id": "s-1", "tool_name": "Bash", "question": "rm -rf node_modules — 高危命令，需要你确认", "_source": "dsh"])
        m.approval = ApprovalCard(tool: "Bash", reason: "rm -rf node_modules — 高危命令，需要你确认")

        let view = PanelView(model: m)
            .frame(width: 392, height: 360)
            .padding(28)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.isOpaque = false
        guard let nsImage = renderer.nsImage,
              let tiff = nsImage.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render/encode failed")
            exit(1)
        }
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/panel-preview.png"
        try? png.write(to: URL(fileURLWithPath: out))
        print("saved \(out) \(png.count) bytes")
    }
}
