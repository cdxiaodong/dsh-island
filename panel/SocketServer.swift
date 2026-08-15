// SocketServer.swift —— 监听 Unix socket，接收 dsh-island 插件推送的事件。
// 借鉴 CodeIsland 的 HookServer（NWListener + NWEndpoint.unix）。
// 非阻塞事件：处理完回写 "{}"；PermissionRequest：保持连接，等面板审批后回写决策。
import Foundation
import Network

/// 插件注册的菜单项
struct PluginMenuItem {
    let id: String
    let title: String
    let icon: String?
}

@MainActor
final class SocketServer {
    /// 收到插件菜单设置时的回调（由 StatusBarController 更新右键菜单）
    var onMenuUpdate: (([PluginMenuItem]) -> Void)?
    /// 菜单点击回调（面板点击插件菜单项 → 由控制器转发给 DSH）
    var onMenuClick: ((String) -> Void)?

    nonisolated static var socketPath: String {
        if let env = ProcessInfo.processInfo.environment["DSH_ISLAND_SOCKET_PATH"], !env.isEmpty {
            return env
        }
        return "/tmp/dsh-island-\(getuid()).sock"
    }

    /// DSH 插件监听的控制 socket（面板发菜单点击过去）
    nonisolated static var ctlSocketPath: String {
        if let env = ProcessInfo.processInfo.environment["DSH_ISLAND_CTL_SOCKET_PATH"], !env.isEmpty {
            return env
        }
        return "/tmp/dsh-island-ctl-\(getuid()).sock"
    }

    private let model: PanelModel
    private var listener: NWListener?

    init(model: PanelModel) {
        self.model = model
    }

    func start() {
        unlink(Self.socketPath)

        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: Self.socketPath)

        do {
            listener = try NWListener(using: params)
        } catch {
            return
        }
        listener?.newConnectionHandler = { [weak self] conn in
            Task { @MainActor in self?.handle(conn) }
        }
        listener?.stateUpdateHandler = { [previousUmask = umask(0o077)] state in
            switch state {
            case .ready:
                umask(previousUmask)
                chmod(Self.socketPath, 0o700)
                fputs("[dsh-island-panel] listening on \(Self.socketPath)\n", stderr)
            case .failed(let error):
                fputs("[dsh-island-panel] listener failed: \(error.localizedDescription)\n", stderr)
            default:
                break
            }
        }
        listener?.start(queue: .main)
    }

    // MARK: 连接处理

    private func handle(_ conn: NWConnection) {
        conn.start(queue: .main)
        receiveAll(conn, accumulated: Data())
    }

    private func receiveAll(_ conn: NWConnection, accumulated: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
            Task { @MainActor in
                guard let self else { return }
                var data = accumulated
                if let content { data.append(content) }
                if isComplete || error != nil {
                    self.process(data, conn)
                } else {
                    self.receiveAll(conn, accumulated: data)
                }
            }
        }
    }

    private func process(_ data: Data, _ conn: NWConnection) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            send(conn, "{\"error\":\"parse_failed\"}")
            conn.cancel()
            return
        }
        // 插件菜单设置（type=menu_set）—— 非事件，更新右键菜单
        if let type = json["type"] as? String, type == "menu_set" {
            var items: [PluginMenuItem] = []
            if let rawItems = json["items"] as? [[String: Any]] {
                for raw in rawItems {
                    if let id = raw["id"] as? String, let title = raw["title"] as? String {
                        items.append(PluginMenuItem(id: id, title: title, icon: raw["icon"] as? String))
                    }
                }
            }
            onMenuUpdate?(items)
            send(conn, "{}")
            conn.cancel()
            return
        }

        let name = json["hook_event_name"] as? String ?? ""

        if name == "PermissionRequest" {
            // 阻塞事件：显示审批卡，保持连接等待用户决策
            model.approval = ApprovalCard(
                tool: json["tool_name"] as? String ?? "tool",
                reason: json["question"] as? String ?? "Approval requested"
            )
            model.pendingConnection = conn
            model.handle(json)
            return
        }

        model.handle(json)
        send(conn, "{}")
    }

    // MARK: 审批回写

    /// 面板审批按钮回调：把决策写回插件 → DSH
    func respondApproval(_ behavior: String) {
        guard let conn = model.pendingConnection else { return }
        let resp = "{\"hookSpecificOutput\":{\"hookEventName\":\"PermissionRequest\",\"decision\":{\"behavior\":\"\(behavior)\"}}}"
        send(conn, resp)
        model.pendingConnection = nil
        model.approval = nil
    }

    /// 发送后等数据真正交给协议栈再关闭连接（立即 cancel 会丢弃未发出的数据）
    private func send(_ conn: NWConnection, _ text: String) {
        conn.send(content: Data(text.utf8), completion: .contentProcessed { [weak conn] _ in
            conn?.cancel()
        })
    }
}
