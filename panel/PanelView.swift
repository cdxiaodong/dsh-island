// PanelView.swift —— 菜单栏灵动岛展开面板（NSPopover 内容）。
// 设计借鉴经典 Dynamic Island 规范 + MioIsland 主题色板：
//   近黑胶囊背景 #0A0A0B · 高亮语义色（working 青 / needsYou 琥珀 / done 绿 / error 红 / idle 荧光绿）
import SwiftUI

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255, blue: Double(b)/255, opacity: Double(a)/255)
    }
}

struct PanelView: View {
    @ObservedObject var model: PanelModel
    /// 进入动画：从顶部小胶囊弹性展开（像 iPhone 灵动岛）
    @State private var appeared = false

    // MioIsland Classic 主题色板 + DSH 蓝灰（dsh-web-ui 调调）
    private let chromeBg = Color(hex: "0E0E0E")   // DSH 深色底
    private let chromeOverlay = Color(hex: "1A1A1A")
    private let chromeBorder = Color(hex: "232833")
    private let textPrimary = Color(hex: "EDEDEE")
    private let textSecondary = Color(hex: "C7C7CB")
    private let textMuted = Color(hex: "8B8B90")
    // 语义状态色
    private let cWorking = Color(hex: "67E8F9")    // 青
    private let cNeedsYou = Color(hex: "FBBF24")   // 琥珀
    private let cDone = Color(hex: "4ADE80")       // 绿
    private let cError = Color(hex: "F87171")      // 红
    private let cIdle = Color(hex: "CCFF00")       // 荧光绿
    private let cThinking = Color(hex: "B794F6")   // 紫

    private let icons: [String: String] = [
        "SessionStart": "▶︎", "SessionEnd": "■", "PreToolUse": "⚙︎",
        "PostToolUse": "✓", "PostToolUseFailure": "✕",
        "PermissionRequest": "◉", "SubagentStart": "◇", "SubagentStop": "◇",
        "Notification": "●",
    ]

    private var statusColor: Color {
        switch model.status {
        case "waitingApproval": return cNeedsYou
        case "running", "processing": return cWorking
        case "idle": return cIdle
        default: return textMuted
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
    private func eventColor(_ name: String) -> Color {
        switch name {
        case "SessionStart", "PostToolUse": return cDone
        case "PostToolUseFailure": return cError
        case "PermissionRequest": return cNeedsYou
        case "PreToolUse", "SubagentStart", "SubagentStop": return cWorking
        case "Notification": return textMuted
        default: return textSecondary
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶部浅蓝品牌区（呼应托盘胶囊）
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: "AFC0EA"), Color(hex: "7F96D2")],
                                   startPoint: .top, endPoint: .bottom)
                )
            Divider().overlay(Color(hex: "6E83C4").opacity(0.6))
            // 用量行（工具/耗时/子代理/token）
            usageRow
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            Divider().overlay(chromeBorder)
            // 深色内容区
            VStack(alignment: .leading, spacing: 0) {
                if model.approval != nil {
                    approvalCard
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Divider().overlay(chromeBorder).padding(.vertical, 10)
                }
                eventList
            }
            .padding(14)
        }
        .frame(width: 392)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(chromeBg)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(chromeBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.45), radius: 30, y: 14)
        // 灵动岛弹性展开：从顶部小胶囊 spring 放大到完整面板
        .scaleEffect(appeared ? 1 : 0.35, anchor: .top)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.38, dampingFraction: 0.6), value: appeared)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.6)) {
                appeared = true
            }
        }
    }

    // MARK: 用量行

    private var usageRow: some View {
        HStack(spacing: 10) {
            Label("\(model.toolCount) 工具", systemImage: "hammer.fill")
            Label(elapsedText, systemImage: "clock")
            if model.subagentCount > 0 {
                Label("\(model.subagentCount) 子代理", systemImage: "person.2.fill")
            }
            if model.usageTokens > 0 {
                Label(formatTokens(model.usageTokens), systemImage: "flame.fill")
            }
            Spacer()
        }
        .font(.system(size: 9.5, weight: .medium))
        .foregroundStyle(Color(hex: "0E1835"))
    }

    private var elapsedText: String {
        guard let start = model.sessionStart else { return "—" }
        return PanelModel.formatElapsed(since: start)
    }

    private func formatTokens(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    // MARK: 头部（浅蓝品牌区，文字深蓝）
    private var header: some View {
        HStack(spacing: 11) {
            // 鲸鱼娘桌宠动画
            WhaleSpriteView(status: model.status, mood: model.mood, width: 46, height: 52)
                .frame(width: 46, height: 52)
                .padding(.trailing, 4)

            VStack(alignment: .leading, spacing: 3) {
                Text("DeepSeek Harness")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(hex: "0E1835"))
                Text(model.cwd)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color(hex: "0E1835").opacity(0.55))
                    .lineLimit(1)
                    .truncationMode(.middle)
                // 当前工具（运行中显示）
                if let tool = model.currentTool, statusColor == cWorking {
                    HStack(spacing: 4) {
                        Image(systemName: "hammer.fill").font(.system(size: 8.5))
                        Text(tool).font(.system(size: 10, design: .monospaced))
                    }
                    .foregroundStyle(Color(hex: "0E1835"))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.white.opacity(0.55)))
                }
            }

            Spacer()

            // 状态胶囊（白底深蓝字，浅蓝 header 上清晰）
            HStack(spacing: 5) {
                Circle().fill(statusColor).frame(width: 7, height: 7)
                    .shadow(color: statusColor.opacity(0.8), radius: 3)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color(hex: "0E1835"))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.85)))
            .overlay(Capsule().stroke(Color.white.opacity(0.5), lineWidth: 1))
        }
    }

    // MARK: 审批卡
    private var approvalCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 13))
                    .foregroundStyle(cNeedsYou)
                Text("需要授权")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(cNeedsYou)
                Spacer()
                Text(model.approval?.tool ?? "")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(textSecondary)
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(chromeOverlay))
            }
            Text(model.approval?.reason ?? "")
                .font(.system(size: 10.5))
                .foregroundStyle(textSecondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button { ModelResponder.approve() } label: {
                    Label("允许", systemImage: "checkmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedProminentButtonStyle())
                .tint(cDone)

                Button { ModelResponder.deny() } label: {
                    Label("拒绝", systemImage: "xmark").frame(maxWidth: .infinity)
                }
                .buttonStyle(BorderedButtonStyle())
                .tint(cError)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(cNeedsYou.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(cNeedsYou.opacity(0.28), lineWidth: 1))
    }

    // MARK: 事件流
    private var eventList: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(model.events) { row in
                HStack(spacing: 7) {
                    Text(icons[row.name] ?? "·")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(eventColor(row.name))
                        .frame(width: 12)
                    Text(row.name)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(eventColor(row.name))
                    if let tool = row.tool {
                        Text(tool)
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(textSecondary)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 4).fill(chromeOverlay))
                    }
                    if let q = row.question {
                        Text(q).font(.system(size: 8)).foregroundStyle(cNeedsYou).lineLimit(1)
                    }
                    if let m = row.message, !m.hasPrefix("Agent status:") {
                        Text(m).font(.system(size: 8)).foregroundStyle(textMuted).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Text(row.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 7.5)).foregroundStyle(textMuted.opacity(0.6))
                }
                .padding(.vertical, 2)
            }
            if model.events.isEmpty {
                VStack(spacing: 6) {
                    Text("🐋").font(.system(size: 20))
                    Text("等待 DSH 事件…")
                        .font(.system(size: 10.5))
                        .foregroundStyle(textMuted)
                }
                .frame(maxWidth: .infinity, minHeight: 90)
            }
        }
        .animation(.spring(duration: 0.35), value: model.events.count)
    }
}

/// 审批按钮的静态回调（避免 SwiftUI View 持有循环引用）
enum ModelResponder {
    nonisolated(unsafe) static weak var server: SocketServer?
    @MainActor static func approve() { server?.respondApproval("allow") }
    @MainActor static func deny() { server?.respondApproval("deny") }
}
