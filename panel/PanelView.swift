// PanelView.swift —— 菜单栏灵动岛展开面板（NSPopover 内容）。
// 深色毛玻璃卡片：DSH 标识 + 状态 + 当前工具 + 事件流 + 审批卡。
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
        case "running", "processing": return .blue
        case "waitingApproval": return .yellow
        default: return .gray
        }
    }
    private var statusLabel: String {
        switch model.status {
        case "running": return "运行中"
        case "processing": return "处理中"
        case "waitingApproval": return "等待授权"
        case "idle": return "空闲"
        default: return model.status
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.approval != nil {
                approvalCard
            }
            eventList
        }
        .padding(16)
        .frame(width: 400)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.ultraThinMaterial)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
    }

    // MARK: 头部
    private var header: some View {
        HStack(spacing: 10) {
            // DSH 鲸鱼图标
            Text("🐋")
                .font(.system(size: 22))
                .frame(width: 38, height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(colors: [Color(red: 0.31, green: 0.55, blue: 1.0),
                                                      Color(red: 0.48, green: 0.36, blue: 1.0)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("DeepSeek Harness")
                    .font(.system(size: 13, weight: .bold))
                Text(model.cwd)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            // 状态胶囊
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.08)))
        }
    }

    // MARK: 审批卡
    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("🛡️").font(.system(size: 14))
                Text("需要授权")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.yellow)
            }
            Text(model.approval?.reason ?? "")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button { ModelResponder.approve() } label: {
                    Label("允许", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(.green)

                Button { ModelResponder.deny() } label: {
                    Label("拒绝", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
                .tint(.red)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.yellow.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.yellow.opacity(0.25), lineWidth: 1))
    }

    // MARK: 事件流
    private var eventList: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(model.events) { row in
                HStack(spacing: 6) {
                    Text(row.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 8)).foregroundStyle(.tertiary)
                    Text(icons[row.name] ?? "·").font(.system(size: 9))
                    Text(row.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(colors[row.name] ?? .secondary)
                    if let tool = row.tool {
                        Text(tool)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.07)))
                    }
                    if let q = row.question {
                        Text(q).font(.system(size: 8)).foregroundStyle(.yellow).lineLimit(1)
                    }
                    if let m = row.message, !m.hasPrefix("Agent status:") {
                        Text(m).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            if model.events.isEmpty {
                Text("等待 DSH 事件…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
        .padding(.top, 2)
    }
}

/// 审批按钮的静态回调（避免 SwiftUI View 持有循环引用）
enum ModelResponder {
    nonisolated(unsafe) static weak var server: SocketServer?
    @MainActor static func approve() { server?.respondApproval("allow") }
    @MainActor static func deny() { server?.respondApproval("deny") }
}
