// WhaleSprite.swift —— 鲸鱼娘桌宠行为引擎（15 动作 + 日常随机 + 状态联动）。
// 资源来自 vlln/whale-girl（MIT，角色 credit ZipZipPipe）：15 种动作 spritesheet，
// 随面板二进制分发在 bin/whale2/。帧序列 + Timer 播放，不依赖 NSImage GIF 动画。
//
// 行为模型（借鉴 Codex 桌宠 / whale-girl）：
//   - DSH 状态联动：运行→working/think、审批→wait、成功→celebrate、失败→error
//   - 空闲日常随机：idle 时每 4~7s 随机轮播 walk/play/joy/welcome/disappointed 等
import AppKit
import SwiftUI

// MARK: - 资源与配置

enum Whale2Assets {
    enum Playback { case loop, once, pingpong }
    struct State { let frames: Int; let fps: Double; let playback: Playback }

    static let states: [String: State] = [
        "idle": .init(frames: 3, fps: 2, playback: .pingpong),
        "working": .init(frames: 3, fps: 3, playback: .loop),
        "celebrate": .init(frames: 3, fps: 4, playback: .once),
        "error": .init(frames: 2, fps: 8, playback: .once),
        "disappointed": .init(frames: 2, fps: 2, playback: .loop),
        "joy": .init(frames: 2, fps: 5, playback: .loop),
        "eat": .init(frames: 3, fps: 8, playback: .loop),
        "play": .init(frames: 3, fps: 4, playback: .loop),
        "drag": .init(frames: 1, fps: 5, playback: .loop),
        "walk": .init(frames: 3, fps: 6, playback: .pingpong),
        "sleep": .init(frames: 2, fps: 1, playback: .loop),
        "wake": .init(frames: 2, fps: 3, playback: .once),
        "welcome": .init(frames: 2, fps: 3, playback: .loop),
        "think": .init(frames: 1, fps: 2, playback: .loop),
        "wait": .init(frames: 1, fps: 2, playback: .loop),
    ]

    /// 空闲日常随机动作池（持续几秒后回 idle）
    static let idlePlaylist = ["idle", "walk", "play", "joy", "welcome", "disappointed"]

    private static var frameCache: [String: [NSImage]] = [:]
    private static var resourceDir: URL? = {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundled = execDir.appendingPathComponent("whale2")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return execDir.deletingLastPathComponent().appendingPathComponent("panel/resources/whale2")
    }()

    static func frames(for state: String) -> [NSImage] {
        if let hit = frameCache[state] { return hit }
        guard let dir = resourceDir else { return [] }
        let frameDir = dir.appendingPathComponent("frames/\(state)")
        let urls = (try? FileManager.default.contentsOfDirectory(at: frameDir, includingPropertiesForKeys: nil)) ?? []
        let images = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { NSImage(contentsOf: $0) }
        frameCache[state] = images
        return images
    }

    static func state(_ name: String) -> State { states[name] ?? .init(frames: 1, fps: 2, playback: .loop) }

    /// 半身鲸鱼娘图标（菜单栏胶囊用）
    static var menuIcon: NSImage? {
        guard let dir = resourceDir else { return nil }
        let url = dir.appendingPathComponent("menu-icon.png")
        guard let img = NSImage(contentsOf: url) else { return nil }
        img.size = NSSize(width: 18, height: 20)
        return img
    }
}

// MARK: - 行为决策

enum WhaleBehavior {
    /// DSH 状态 → 主动作
    static func primaryAction(status: String) -> String {
        switch status {
        case "waitingApproval": return "wait"
        case "running", "processing": return Bool.random() ? "working" : "think"
        case "idle": return "idle"
        default: return "idle"
        }
    }
}

// MARK: - 动画视图

/// 鲸鱼娘桌宠视图：SwiftUI Image + aspectRatio(.fit) 完整显示（不裁剪头部），
/// 帧序列 + Timer 播放，按 DSH 状态联动 + 空闲日常随机。
struct WhaleSpriteView: View {
    let status: String
    let mood: String?
    var width: CGFloat = 40
    var height: CGFloat = 46

    @State private var action = "idle"
    @State private var frameIndex = 0
    @State private var direction = 1
    @State private var frameTimer: Timer?
    @State private var idleTimer: Timer?

    var body: some View {
        let frames = Whale2Assets.frames(for: action)
        Group {
            if let img = frames.isEmpty ? nil : frames[min(frameIndex, frames.count - 1)] {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)   // 完整显示（头不裁剪）
            } else {
                Rectangle().fill(Color.clear)
            }
        }
        .frame(width: width, height: height)
        .onAppear {
            updateAction()
        }
        .onChange(of: status) { _, _ in updateAction() }
        .onChange(of: mood) { _, _ in updateAction() }
        .onDisappear { stopAll() }
    }

    // MARK: 行为决策

    private func updateAction() {
        let target: String
        if let mood {
            target = mood == "celebrate" ? "celebrate" : "error"
            stopIdleRandom()
        } else if status == "idle" {
            target = action.isEmpty ? "idle" : action   // 保持当前，交给随机轮播
            startIdleRandom()
        } else {
            target = WhaleBehavior.primaryAction(status: status)
            stopIdleRandom()
        }
        if target != action { play(target) }
    }

    // MARK: 播放

    private func play(_ newAction: String) {
        action = newAction
        frameIndex = 0
        direction = 1
        frameTimer?.invalidate()
        let frames = Whale2Assets.frames(for: newAction)
        guard frames.count > 1 else { return }
        let cfg = Whale2Assets.state(newAction)
        let interval = 1.0 / max(cfg.fps, 0.1)
        frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            switch cfg.playback {
            case .loop:
                frameIndex = (frameIndex + 1) % frames.count
            case .pingpong:
                let next = frameIndex + direction
                if next >= frames.count { direction = -1 }
                if next < 0 { direction = 1 }
                frameIndex = min(max(next, 0), frames.count - 1)
            case .once:
                if frameIndex < frames.count - 1 { frameIndex += 1 }
                else { frameIndex = 0 }   // 播放完回第一帧
            }
        }
    }

    private func startIdleRandom() {
        guard idleTimer == nil else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { _ in
            let next = Whale2Assets.idlePlaylist.randomElement() ?? "idle"
            if next != action { play(next) }
        }
    }

    private func stopIdleRandom() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    private func stopAll() {
        frameTimer?.invalidate()
        idleTimer?.invalidate()
        frameTimer = nil
        idleTimer = nil
    }
}
