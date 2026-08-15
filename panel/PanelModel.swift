// PanelModel.swift —— 灵动岛面板的状态模型（ObservableObject）。
// 由 SocketServer 解析 DSH 事件后驱动更新，SwiftUI 视图订阅渲染。
import Foundation
import SwiftUI
import Network

/// 事件流里的一行
struct EventRow: Identifiable {
    let id = UUID()
    let name: String
    let tool: String?
    let question: String?
    let message: String?
    let timestamp = Date()
}

/// 待审批卡片
struct ApprovalCard: Identifiable {
    let id = UUID()
    let tool: String
    let reason: String
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var cwd: String = "DeepSeek Harness"
    @Published var sessionId: String = "-"
    @Published var status: String = "idle"
    @Published var currentTool: String?
    @Published var events: [EventRow] = []
    @Published var approval: ApprovalCard?

    /// PermissionRequest 保持的连接，审批后由 SocketServer 回写决策
    var pendingConnection: NWConnection?

    private let maxEvents = 8

    /// 处理一帧 DSH 事件（已解析为字典）
    func handle(_ raw: [String: Any]) {
        let name = raw["hook_event_name"] as? String ?? ""
        let tool = raw["tool_name"] as? String
        let question = raw["question"] as? String
        let message = raw["message"] as? String
        let session = raw["session_id"] as? String

        if let s = raw["cwd"] as? String, !s.isEmpty { cwd = s }
        if let s = session, !s.isEmpty { sessionId = s }
        if let m = message, m.hasPrefix("Agent status:") {
            status = String(m.dropFirst("Agent status:".count)).trimmingCharacters(in: .whitespaces)
        }

        switch name {
        case "SessionStart":
            status = "running"
            events.removeAll()
        case "SessionEnd":
            status = "idle"
            currentTool = nil
        case "PreToolUse":
            status = "running"
            currentTool = tool ?? "tool"
        case "PostToolUse", "PostToolUseFailure":
            currentTool = nil
        case "PermissionRequest":
            status = "waitingApproval"
            currentTool = tool ?? "tool"
        default:
            break
        }

        events.insert(EventRow(name: name, tool: tool, question: question, message: message), at: 0)
        if events.count > maxEvents { events.removeLast() }
    }
}
