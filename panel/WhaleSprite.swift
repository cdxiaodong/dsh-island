// WhaleSprite.swift —— 鲸鱼娘动画组件。
// 资源来自 dsh-web-ui 的 dsh-pet（Apache-2.0）：每状态一个 GIF（192×208），
// NSImageView 原生播放。GIF 随面板二进制分发在 bin/whale/ 下。
import AppKit
import SwiftUI

/// 从插件资源目录加载鲸鱼娘 GIF（可执行文件旁 bin/whale/<state>.gif）
enum WhaleAssets {
    private static var cache: [String: NSImage] = [:]

    /// 状态 → 鲸鱼娘动画
    static func spriteState(for status: String) -> String {
        switch status {
        case "running", "processing": return "running"
        case "waitingApproval": return "waiting"
        case "failed", "error": return "failed"
        case "idle": return "idle"
        default: return "idle"
        }
    }

    static func image(for state: String) -> NSImage? {
        if let hit = cache[state] { return hit }
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        // 1) 随二进制分发：<exec>/whale/<state>.gif
        let bundled = execDir.appendingPathComponent("whale/\(state).gif")
        // 2) 源码目录（开发/preview）：<exec>/../panel/resources/whale/<state>.gif
        let source = execDir.deletingLastPathComponent().appendingPathComponent("panel/resources/whale/\(state).gif")
        let url = FileManager.default.fileExists(atPath: bundled.path) ? bundled : source
        guard let img = NSImage(contentsOf: url) else { return nil }
        cache[state] = img
        return img
    }
}

/// NSImageView 包装：按状态切换 GIF 动画
struct WhaleSpriteView: NSViewRepresentable {
    let state: String
    var width: CGFloat = 34
    var height: CGFloat = 50

    func makeNSView(context: Context) -> NSImageView {
        let v = NSImageView()
        v.imageScaling = .scaleProportionallyUpOrDown
        v.animates = true
        return v
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = WhaleAssets.image(for: state)
        nsView.animates = true
        nsView.frame.size = NSSize(width: width, height: height)
    }
}
