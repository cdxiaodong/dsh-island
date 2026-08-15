// WhaleSprite.swift —— 鲸鱼娘动画组件（帧序列 + Timer 播放）。
// 资源来自 dsh-web-ui 的 dsh-pet（Apache-2.0）：每状态一组帧 PNG，
// 随面板二进制分发在 bin/whale/frames/<state>/。Timer 逐帧切换，
// 不依赖 NSImage 的 GIF 动画支持。
import AppKit
import SwiftUI

enum WhaleAssets {
    /// 每状态帧时长（ms），来自 pet.json
    static let tracks: [String: [Double]] = [
        "idle": [400, 400, 500, 400, 400, 500],
        "running-right": [225, 225, 225, 225, 225, 225, 225, 225],
        "running-left": [225, 225, 225, 225, 225, 225, 225, 225],
        "waving": [350, 350, 350, 350],
        "jumping": [300, 300, 300, 350, 350],
        "failed": [450, 450, 450, 500, 550, 600, 450, 450],
        "waiting": [450, 450, 500, 450, 450, 500],
        "running": [250, 250, 250, 250, 250, 250],
        "review": [550, 550, 550, 550, 550, 550],
    ]

    /// 状态 → 鲸鱼娘动画
    static func spriteState(for status: String) -> String {
        switch status {
        case "running", "processing": return "running"
        case "waitingApproval": return "waiting"
        case "failed", "error": return "failed"
        default: return "idle"
        }
    }

    private static var frameCache: [String: [NSImage]] = [:]
    private static var resourceDir: URL? = {
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundled = execDir.appendingPathComponent("whale")
        if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        // 开发/preview 回退到源码目录
        return execDir.deletingLastPathComponent().appendingPathComponent("panel/resources/whale")
    }()

    /// 加载某状态的全部帧 PNG（按文件名排序）
    static func frames(for state: String) -> [NSImage] {
        if let hit = frameCache[state] { return hit }
        guard let dir = resourceDir else { return [] }
        let frameDir = dir.appendingPathComponent("frames/\(state)")
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: frameDir, includingPropertiesForKeys: nil)) ?? []
        let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
        let images = sorted.compactMap { NSImage(contentsOf: $0) }
        frameCache[state] = images
        return images
    }

    static func durations(for state: String) -> [Double] {
        tracks[state] ?? [250]
    }
}

/// 帧动画视图：按状态播放鲸鱼娘（Timer 逐帧）
struct WhaleSpriteView: NSViewRepresentable {
    let state: String
    var width: CGFloat = 32
    var height: CGFloat = 65

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var timer: Timer?
        var frameIndex = 0
    }

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        let frames = WhaleAssets.frames(for: state)
        guard !frames.isEmpty else { return }
        let durations = WhaleAssets.durations(for: state)

        context.coordinator.timer?.invalidate()
        context.coordinator.frameIndex = 0
        nsView.image = frames[0]
        nsView.frame.size = NSSize(width: width, height: height)

        var index = 0
        func scheduleNext() {
            let d = durations[index % durations.count] / 1000.0
            index += 1
            context.coordinator.timer = Timer.scheduledTimer(withTimeInterval: d, repeats: false) { _ in
                let i = index % frames.count
                nsView.image = frames[i]
                scheduleNext()
            }
        }
        scheduleNext()
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        coordinator.timer?.invalidate()
    }
}
