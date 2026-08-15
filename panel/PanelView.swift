// PanelView.swift —— 灵动岛面板的 SwiftUI 视图。
// 借鉴 CodeIsland 的 NotchPanelView 深色像素风，精简为单卡片。
import SwiftUI

struct PanelView: View {
    @ObservedObject var model: PanelModel

    private let colors: [String: Color] = [
        "SessionStart": .green, "SessionEnd": .gray, "PreToolUse": .blue,
        "PostToolUse": .green, "PostToolUseFailure": .red,
        "PermissionRequest": .yellow, "Notification": .secondary,
    ]
    private let icons: [String: String] = [
        "SessionStart": "🟢", "SessionEnd": "⚫", "PreToolUse": "🔧",
        "PostToolUse": "✅", "PostToolUseFailure": "❌",
        "PermissionRequest": "🛡️", "SubagentStart": "🧩", "SubagentStop": "🧩",
        "Notification": "💬",
    ]

    private var statusColor: Color {
        switch model.status {
        case "running": return .blue
        case "waitingApproval": return .yellow
        case "processing": return .blue
        default: return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if model.approval != nil {
                approvalCard
            }
            eventList
        }
        .padding(14)
        .frame(width: 420)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.13))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color(red: 0.17, green: 0.17, blue: 0.22), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 18, y: 8)
    }

    // MARK: 头部：标识 + 名称 + 状态灯
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.55, blue: 1.0),
                                                  Color(red: 0.48, green: 0.36, blue: 1.0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Text("D").font(.system(size: 16, weight: .heavy, design: .monospaced)).foregroundColor(.white)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("DeepSeek Harness").font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                Text(model.cwd)
                    .font(.system(size: 9))
                    .foregroundColor(Color(red: 0.48, green: 0.48, blue: 0.56))
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                Text(model.status).font(.system(size: 9)).foregroundColor(.secondary)
            }
        }
    }

    // MARK: 审批卡
    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🛡️ 需要授权").font(.system(size: 11, weight: .bold)).foregroundColor(.yellow)
            Text(model.approval?.tool ?? "tool")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(.white)
            Text(model.approval?.reason ?? "")
                .font(.system(size: 10))
                .foregroundColor(Color(red: 0.66, green: 0.60, blue: 0.47))
            HStack(spacing: 8) {
                Button { ModelResponder.approve() } label: {
                    Text("允许").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(PlainButtonStyle())
                .background(RoundedRectangle(cornerRadius: 8).fill(.green))
                .foregroundColor(.black)

                Button { ModelResponder.deny() } label: {
                    Text("拒绝").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(PlainButtonStyle())
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.17, green: 0.17, blue: 0.22)))
                .foregroundColor(.red)
            }
            .font(.system(size: 11, weight: .bold))
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.14, green: 0.11, blue: 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.29, green: 0.23, blue: 0.09), lineWidth: 1))
    }

    // MARK: 事件流
    private var eventList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.events) { row in
                HStack(spacing: 6) {
                    Text(row.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 8)).foregroundColor(Color(red: 0.33, green: 0.33, blue: 0.41))
                    Text(icons[row.name] ?? "·").font(.system(size: 9))
                    Text(row.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(colors[row.name] ?? .secondary)
                    if let tool = row.tool {
                        Text(tool).font(.system(size: 8)).foregroundColor(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.12, green: 0.12, blue: 0.17)))
                    }
                    if let q = row.question {
                        Text(q).font(.system(size: 8)).foregroundColor(.yellow).lineLimit(1)
                    }
                    if let m = row.message, !m.hasPrefix("Agent status:") {
                        Text(m).font(.system(size: 8)).foregroundColor(.secondary).lineLimit(1)
                    }
                }
            }
            if model.events.isEmpty {
                Text("等待 DSH 事件…").font(.system(size: 10)).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
        }
    }
}

/// 审批按钮的静态回调（避免 SwiftUI View 持有循环引用）
enum ModelResponder {
    nonisolated(unsafe) static weak var server: SocketServer?
    @MainActor static func approve() { server?.respondApproval("allow") }
    @MainActor static func deny() { server?.respondApproval("deny") }
}
