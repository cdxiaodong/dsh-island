// WhaleSprite.swift —— 鲸鱼娘桌宠行为引擎（15 动作 + 日常随机 + 状态联动）。
// 资源来自 vlln/whale-girl（MIT，角色 credit ZipZipPipe）：15 种动作 spritesheet，
// 随面板二进制分发在 bin/whale2/。帧序列 + Timer 播放，不依赖 NSImage GIF 动画。
//
// 行为模型（借鉴 Codex 桌宠 / whale-girl）：
//   - DSH 状态联动：运行→working/think、审批→wait、成功→celebrate、失败→error
//   - 空闲日常随机：idle 时每 4~7s 随机轮播 walk/play/joy/welcome/disappointed 等
import AppKit
import SwiftUI
import Combine

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
        // 镜像朝向变体（新增动作）
        "walk-left": .init(frames: 3, fps: 6, playback: .pingpong),
        "play-left": .init(frames: 3, fps: 4, playback: .loop),
        "welcome-left": .init(frames: 2, fps: 3, playback: .loop),
    ]

    /// 空闲日常随机动作池（十八套动作轮播）
    static let idlePlaylist = ["idle", "walk", "walk-left", "play", "play-left", "joy",
                               "welcome", "welcome-left", "disappointed", "sleep", "eat", "wake"]

    private static var frameCache: [String: [NSImage]] = [:]
    private static var halfFrameCache: [String: [NSImage]] = [:]
    /// 当前皮肤（default / pink / ocean / gold / violet）
    static var currentSkin = "default"
    static let skinNames = ["default", "pink", "ocean", "gold", "violet"]
    /// 当前角色（whale 像素鲸鱼娘 / chibi 二次元）
    static var currentCharacter = "whale"
    static let characterNames = ["whale", "chibi"]
    static let characterDisplayNames = ["🐋 像素鲸鱼娘", "✨ 二次元 Chibi"]

    /// 资源根目录：bin/ 含 whale2/whale2b/chibi/chibi2b
    private static var baseDir: URL? = {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        if FileManager.default.fileExists(atPath: execDir.appendingPathComponent("whale2").path) { return execDir }
        return execDir.deletingLastPathComponent().appendingPathComponent("panel/resources")
    }()

    /// chibi 动作映射：只有 idle/struggle，error→struggle，其余→idle（浮动）
    private static func resolvedState(_ state: String) -> String {
        if currentCharacter == "chibi" {
            return state == "error" ? "struggle" : "idle"
        }
        return state
    }

    /// 角色资源目录名（half=true 半身）
    private static func characterRoot(_ half: Bool) -> String {
        if currentCharacter == "chibi" { return half ? "chibi2b" : "chibi" }
        return half ? "whale2b" : "whale2"
    }

    /// 皮肤子路径：chibi 无皮肤；whale 的 default 用 frames/，其他用 skins/<skin>/frames/
    private static func skinSubpath() -> String {
        if currentCharacter == "chibi" { return "frames" }
        return currentSkin == "default" ? "frames" : "skins/\(currentSkin)/frames"
    }

    /// 切换皮肤（清缓存，重新加载）
    static func setSkin(_ skin: String) {
        guard skinNames.contains(skin) else { return }
        currentSkin = skin
        frameCache.removeAll()
        halfFrameCache.removeAll()
    }

    /// 切换角色（鲸鱼娘造型，清缓存）
    static func setCharacter(_ character: String) {
        guard characterNames.contains(character) else { return }
        currentCharacter = character
        frameCache.removeAll()
        halfFrameCache.removeAll()
    }

    static func frames(for rawState: String) -> [NSImage] {
        let state = resolvedState(rawState)
        let key = "\(currentCharacter)/\(currentSkin)/\(state)"
        if let hit = frameCache[key] { return hit }
        guard let dir = baseDir else { return [] }
        let frameDir = dir.appendingPathComponent("\(characterRoot(false))/\(skinSubpath())/\(state)")
        let urls = (try? FileManager.default.contentsOfDirectory(at: frameDir, includingPropertiesForKeys: nil)) ?? []
        let images = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { NSImage(contentsOf: $0) }
        frameCache[key] = images
        return images
    }

    /// 半身帧（托盘专用，头+上半身，完整 PNG 不裁剪）
    static func halfFrames(for rawState: String) -> [NSImage] {
        let state = resolvedState(rawState)
        let key = "\(currentCharacter)/\(currentSkin)/\(state)"
        if let hit = halfFrameCache[key] { return hit }
        guard let dir = baseDir else { return [] }
        let frameDir = dir.appendingPathComponent("\(characterRoot(true))/\(skinSubpath())/\(state)")
        let urls = (try? FileManager.default.contentsOfDirectory(at: frameDir, includingPropertiesForKeys: nil)) ?? []
        let images = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { NSImage(contentsOf: $0) }
        halfFrameCache[key] = images
        return images
    }

    static func state(_ name: String) -> State { states[name] ?? .init(frames: 1, fps: 2, playback: .loop) }

    /// 某动作的帧率（控制动画速度：idle 慢眨眼 / walk 快 / error 抖）
    static func fps(for state: String) -> Double {
        states[state]?.fps ?? 2
    }

    /// 半身鲸鱼娘图标（菜单栏胶囊用）
    static var menuIcon: NSImage? {
        guard let dir = baseDir else { return nil }
        let url = dir.appendingPathComponent("whale2/menu-icon.png")
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
/// Timer.publish 帧驱动（SwiftUI 原生，可靠），按 DSH 状态联动 + 空闲日常随机。
struct WhaleSpriteView: View {
    let status: String
    let mood: String?
    var width: CGFloat = 40
    var height: CGFloat = 46

    @State private var action = "idle"
    @State private var frameIndex = 0
    @State private var direction = 1
    @State private var idleTimer: Timer?
    @State private var frameAccum: Double = 0

    /// 全局帧时钟：每 0.1s 触发，按动作 fps 推进（idle 慢眨眼 / walk 快）
    private let ticker = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()

    var body: some View {
        let frames = Whale2Assets.frames(for: action)
        Group {
            if let img = frames.isEmpty ? nil : frames[min(frameIndex, max(frames.count - 1, 0))] {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)   // 完整显示（头不裁剪）
            } else {
                Rectangle().fill(Color.clear)
            }
        }
        .frame(width: width, height: height)
        .onReceive(ticker) { _ in tick() }
        .onAppear {
            updateAction()
            playRandomWelcome()   // 打开面板 → 随机欢迎动作
        }
        .onChange(of: status) { _, _ in updateAction() }
        .onChange(of: mood) { _, _ in updateAction() }
        .onDisappear { stopAll() }
    }

    /// 打开面板时随机一个欢迎/打招呼动作，短暂播放后回正常状态
    private func playRandomWelcome() {
        let welcomes = ["welcome", "welcome-left", "joy", "play"]
        let w = welcomes.randomElement() ?? "welcome"
        play(w)
        stopIdleRandom()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            self.updateAction()
        }
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

    // MARK: 帧推进

    private func tick() {
        let frames = Whale2Assets.frames(for: action)
        let fps = Whale2Assets.fps(for: action)
        frameAccum += 0.1
        guard frames.count > 1, frameAccum >= 1.0 / max(fps, 0.1) else { return }
        frameAccum = 0
        let cfg = Whale2Assets.state(action)
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

    private func play(_ newAction: String) {
        action = newAction
        frameIndex = 0
        direction = 1
        frameAccum = 0
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
        idleTimer?.invalidate()
        idleTimer = nil
    }
}
