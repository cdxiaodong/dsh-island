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

    /// 瞬时情绪：celebrate（成功）/ error（失败），2s 后自动清空
    @Published var mood: String?

    // —— 动态统计（托盘可显示）——
    @Published var toolCount: Int = 0          // 本次会话工具调用数
    @Published var subagentCount: Int = 0     // 活跃子代理数
    @Published var sessionStart: Date?        // 会话开始时间（会话时长用）

    /// 托盘显示文本：状态 + 动态后缀
    var trayText: String {
        switch status {
        case "waitingApproval":
            return "等待授权"
        case "running", "processing":
            if let t = currentTool {
                return toolCount > 0 ? "\(t) ·\(toolCount)" : t
            }
            return "运行中"
        case "idle":
            if let start = sessionStart {
                return "空闲 \(Self.formatElapsed(since: start))"
            }
            return "空闲"
        default:
            return "DSH"
        }
    }

    /// 会话时长格式化：<1m → "Xs"，否则 "Xm"，>1h → "XhYm"
    static func formatElapsed(since start: Date) -> String {
        let s = max(0, Int(Date().timeIntervalSince(start)))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h\((s % 3600) / 60)m"
    }

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
            sessionStart = Date()
            toolCount = 0
            subagentCount = 0
        case "SessionEnd":
            status = "idle"
            currentTool = nil
            sessionStart = nil
        case "PreToolUse":
            status = "running"
            currentTool = tool ?? "tool"
        case "PostToolUse", "PostToolUseFailure":
            currentTool = nil
            toolCount += 1
        case "SubagentStart":
            subagentCount += 1
        case "SubagentStop":
            subagentCount = max(0, subagentCount - 1)
        case "PermissionRequest":
            status = "waitingApproval"
            currentTool = tool ?? "tool"
        default:
            break
        }

        events.insert(EventRow(name: name, tool: tool, question: question, message: message), at: 0)
        if events.count > maxEvents { events.removeLast() }

        // 瞬时情绪（鲸鱼娘庆祝/失败）
        if name == "PostToolUse" { setMood("celebrate") }
        if name == "PostToolUseFailure" { setMood("error") }
    }

    private func setMood(_ m: String) {
        mood = m
        let marker = m
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if mood == marker { mood = nil }
        }
    }
}
