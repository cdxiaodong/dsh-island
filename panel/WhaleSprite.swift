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

struct WhaleSpriteView: NSViewRepresentable {
    let status: String
    let mood: String?
    var width: CGFloat = 34
    var height: CGFloat = 70

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        var nsView: NSImageView?
        var frameTimer: Timer?
        var idleTimer: Timer?
        var currentAction = ""
        var frameIndex = 0
        var direction = 1

        func attach(_ v: NSImageView) { nsView = v }

        func play(_ action: String) {
            guard let nsView else { return }
            let frames = Whale2Assets.frames(for: action)
            guard !frames.isEmpty else { return }
            let cfg = Whale2Assets.state(action)

            frameTimer?.invalidate()
            frameTimer = nil
            frameIndex = 0
            direction = 1
            nsView.image = frames[0]

            guard frames.count > 1 else { return } // 单帧动作（think/wait/drag）保持

            let interval = 1.0 / max(cfg.fps, 0.1)
            switch cfg.playback {
            case .loop:
                frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    guard let self, let nsView = self.nsView else { return }
                    self.frameIndex = (self.frameIndex + 1) % frames.count
                    nsView.image = frames[self.frameIndex]
                }
            case .pingpong:
                frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    guard let self, let nsView = self.nsView else { return }
                    let next = self.frameIndex + self.direction
                    if next >= frames.count { self.direction = -1 }
                    if next < 0 { self.direction = 1 }
                    self.frameIndex = min(max(next, 0), frames.count - 1)
                    nsView.image = frames[self.frameIndex]
                }
            case .once:
                frameTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                    guard let self, let nsView = self.nsView else { return }
                    self.frameIndex += 1
                    if self.frameIndex < frames.count {
                        nsView.image = frames[self.frameIndex]
                    } else {
                        self.frameTimer?.invalidate()
                        self.frameTimer = nil
                        nsView.image = frames[0]
                    }
                }
            }
        }

        /// 空闲日常随机：每 4~7s 随机轮播一个日常动作
        func startIdleRandom() {
            guard idleTimer == nil else { return }
            idleTimer = Timer.scheduledTimer(withTimeInterval: 4.5, repeats: true) { [weak self] _ in
                guard let self else { return }
                let action = Whale2Assets.idlePlaylist.randomElement() ?? "idle"
                self.currentAction = action
                self.play(action)
            }
        }

        func stopIdleRandom() {
            idleTimer?.invalidate()
            idleTimer = nil
        }
    }

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.frame.size = NSSize(width: width, height: height)
        context.coordinator.attach(v)
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let c = context.coordinator
        c.nsView = nsView
        nsView.frame.size = NSSize(width: width, height: height)

        // 瞬时情绪（庆祝/失败）优先
        let target: String
        if let mood {
            target = mood == "celebrate" ? "celebrate" : "error"
            c.stopIdleRandom()
        } else if status == "idle" {
            // 空闲：保持当前动作，启动日常随机轮播
            target = c.currentAction.isEmpty ? "idle" : c.currentAction
            c.startIdleRandom()
        } else {
            target = WhaleBehavior.primaryAction(status: status)
            c.stopIdleRandom()
        }

        if target != c.currentAction {
            c.currentAction = target
            c.play(target)
        }
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        coordinator.frameTimer?.invalidate()
        coordinator.idleTimer?.invalidate()
    }
}
