import { Service } from 'cordis';
import { spawn, execFile } from 'node:child_process';
import { existsSync, unlinkSync } from 'node:fs';
import { createServer } from 'node:net';
import { fileURLToPath } from 'node:url';
import * as path from 'node:path';
import { CodeIslandSocket, defaultSocketPath, parseDecision } from './socket.js';
export const name = 'dsh-island';
export const provide = ['island'];
/**
 * dsh-island —— 自带的 macOS 灵动岛（Dynamic Island / 刘海面板）。
 *
 * 插件 apply 时自动拉起 Swift 原生面板二进制（bin/dsh-island-panel），
 * 面板在屏幕顶部刘海区域渲染 DSH 实时状态；插件监听 DSH 内置事件，
 * 把事件写入面板的 Unix socket，审批直接在面板上点允许/拒绝。
 *
 * 事件映射（DSH → 面板）：
 *   session/created        → SessionStart
 *   session/disposed       → SessionEnd
 *   tools/pre-execute      → PreToolUse
 *   tools/post-execute     → PostToolUse / PostToolUseFailure
 *   approval/request       → PermissionRequest（阻塞，面板回写决策）
 *   subagent/start         → SubagentStart
 *   subagent/end           → SubagentStop
 *   agent/status           → Notification
 *
 * 借鉴 CodeIsland（wxtsky/CodeIsland）的 NSPanel + NWListener + SwiftUI
 * 实现，但不需要安装任何第三方应用——面板随插件分发、插件启动即拉起。
 */
export class IslandService extends Service {
    client;
    source;
    approvalTimeoutMs;
    config;
    /** 其他插件注册的菜单项 */
    menuItems = [];
    ctlServer;
    constructor(ctx, config = {}) {
        super(ctx, 'island');
        this.config = config;
        this.source = config.source ?? 'dsh';
        this.approvalTimeoutMs = config.approvalTimeoutMs ?? 300_000;
        this.client = new CodeIslandSocket(config.socketPath);
        // 监听面板发来的菜单点击（控制 socket）
        this.startCtlServer();
        // 会话生命周期
        ctx.on('session/created', (session) => {
            void this.emit({
                hook_event_name: 'SessionStart',
                session_id: this.sessionIdOf(session),
                cwd: this.cwdOf(session),
            });
        });
        ctx.on('session/disposed', (session) => {
            void this.emit({
                hook_event_name: 'SessionEnd',
                session_id: this.sessionIdOf(session),
            });
        });
        // 工具调用（观察型 waterfall 监听器：调用 next() 放行，不影响决策）
        ctx.on('tools/pre-execute', (exec, next) => this.onPreToolUse(exec, next));
        ctx.on('tools/post-execute', (exec, result, next) => this.onPostToolUse(exec, result, next));
        // 审批（answerer：转发给 CodeIsland，回写 allow/deny）
        if (config.approvals !== false) {
            ctx.on('approval/request', (req, next) => this.onApprovalRequest(req, next), true /* prepend：CodeIsland 优先审批 */);
        }
        // 子代理
        if (config.subagents !== false) {
            ctx.on('subagent/start', (agent) => {
                void this.emit({
                    hook_event_name: 'SubagentStart',
                    session_id: this.sessionIdOf(agent),
                    agent_id: this.idOf(agent),
                    agent_type: agent?.type ?? agent?.kind ?? 'subagent',
                });
            });
            ctx.on('subagent/end', (agent) => {
                void this.emit({
                    hook_event_name: 'SubagentStop',
                    session_id: this.sessionIdOf(agent),
                    agent_id: this.idOf(agent),
                    agent_type: agent?.type ?? agent?.kind ?? 'subagent',
                });
            });
        }
        // 状态变化
        if (config.agentStatus !== false) {
            ctx.on('agent/status', (agent) => {
                const status = agent?.status ?? '';
                void this.emit({
                    hook_event_name: 'Notification',
                    session_id: this.sessionIdOf(agent),
                    agent_id: this.idOf(agent),
                    message: `Agent status: ${status}`,
                });
            });
        }
    }
    // ---- 事件处理器 -----------------------------------------------------
    async onPreToolUse(exec, next) {
        void this.emit({
            hook_event_name: 'PreToolUse',
            session_id: this.sessionIdOf(exec),
            agent_id: this.idOf(exec),
            tool_name: exec?.name,
            tool_use_id: exec?.callId,
            tool_input: exec?.arguments,
            cwd: this.cwdOf(exec),
        });
        return this.delegate(next);
    }
    async onPostToolUse(exec, result, next) {
        const isError = result?.isError === true || result?.error !== undefined;
        void this.emit({
            hook_event_name: isError ? 'PostToolUseFailure' : 'PostToolUse',
            session_id: this.sessionIdOf(exec),
            agent_id: this.idOf(exec),
            tool_name: exec?.name,
            tool_use_id: exec?.callId,
            tool_input: exec?.arguments,
            cwd: this.cwdOf(exec),
        });
        return this.delegate(next, result);
    }
    async onApprovalRequest(req, next) {
        const toolName = req?.toolName ?? req?.tool ?? 'tool';
        const reason = req?.reason ?? 'Approval requested';
        // CodeIsland 未运行 → 放行给下一个 answerer / 宿主默认处理
        if (!this.client.available())
            return this.delegate(next);
        const res = await this.client.send({
            hook_event_name: 'PermissionRequest',
            session_id: this.sessionIdOf(req),
            agent_id: this.idOf(req),
            tool_name: toolName,
            tool_use_id: req?.callId,
            question: reason,
            cwd: this.cwdOf(req),
            _source: this.source,
        }, { wait: true, timeoutMs: this.approvalTimeoutMs });
        const decision = parseDecision(res.response);
        this.debug('approval', { tool: toolName, reason, decision, error: res.error });
        if (decision === 'allow')
            return { outcome: 'allowed-once' };
        if (decision === 'deny')
            return { outcome: 'rejected' };
        // 超时 / 连接失败 / 无决策 → 放行给其他 answerer；没有则 fail-closed 拒绝
        const delegated = await this.delegate(next);
        return delegated ?? { outcome: 'rejected' };
    }
    // ---- 插件注册接口（托盘右键菜单）----
    /**
     * 注册一个托盘右键菜单项。返回注销函数。
     * 其他 DSH 插件：inject: ['island']，然后 ctx.island.registerMenuItem(...)
     */
    registerMenuItem(item) {
        this.menuItems.push(item);
        this.pushMenu();
        return () => {
            this.menuItems = this.menuItems.filter((i) => i.id !== item.id);
            this.pushMenu();
        };
    }
    /** 把菜单项同步给面板（menu_set） */
    pushMenu() {
        if (!this.client.available())
            return;
        void this.client.send({
            type: 'menu_set',
            items: this.menuItems.map(({ id, title, icon }) => ({ id, title, icon })),
        }, { wait: false }).catch(() => { });
    }
    /** 监听面板发来的菜单点击（控制 socket /tmp/dsh-island-ctl-<uid>.sock） */
    startCtlServer() {
        const ctlPath = this.ctlSocketPath();
        try {
            unlinkSync(ctlPath);
        }
        catch { /* ignore */ }
        this.ctlServer = createServer((conn) => {
            const chunks = [];
            conn.on('data', (d) => chunks.push(Buffer.isBuffer(d) ? d : Buffer.from(d)));
            conn.on('end', () => {
                try {
                    const msg = JSON.parse(Buffer.concat(chunks).toString('utf8'));
                    if (msg.type === 'menu_click' && msg.id) {
                        const item = this.menuItems.find((i) => i.id === msg.id);
                        void item?.action?.();
                        this.debug('menu_click', msg.id);
                    }
                }
                catch { /* ignore */ }
            });
            conn.on('error', () => { });
        });
        this.ctlServer.on('error', () => { });
        this.ctlServer.listen(ctlPath);
    }
    ctlSocketPath() {
        return process.env.DSH_ISLAND_CTL_SOCKET_PATH
            ?? `/tmp/dsh-island-ctl-${process.getuid?.() ?? 0}.sock`;
    }
    // ---- 内部工具 -------------------------------------------------------
    async emit(payload) {
        if (!this.client.available())
            return;
        const full = {
            ...payload,
            _source: this.source,
            cwd: payload.cwd ?? process.cwd(),
        };
        this.debug('emit', full);
        const res = await this.client.send(full, { wait: false });
        if (!res.ok && res.error !== 'connect_timeout') {
            this.debug('send_failed', { error: res.error, payload: full });
        }
    }
    /** 安全地委托给 waterfall 链的下一个监听器（默认放行/透传）。 */
    async delegate(next, fallback) {
        if (typeof next !== 'function')
            return fallback;
        try {
            return await next();
        }
        catch {
            return fallback;
        }
    }
    debug(tag, data) {
        if (this.config.debug) {
            process.stderr.write(`[dsh-island:${tag}] ${JSON.stringify(data)}\n`);
        }
    }
    /** 从 agent / session / exec / req 提取稳定 session_id。 */
    sessionIdOf(input) {
        const id = this.idOf(input)
            ?? input?.session?.id
            ?? (typeof input?.id === 'string' ? input.id : undefined);
        return id ?? `dsh-${process.pid}`;
    }
    idOf(input) {
        if (!input)
            return undefined;
        if (typeof input.agentId === 'string')
            return input.agentId;
        if (input.agent && typeof input.agent.id === 'string')
            return input.agent.id;
        return undefined;
    }
    cwdOf(input) {
        const cwd = input?.cwd
            ?? input?.session?.cwd
            ?? input?.agent?.session?.cwd
            ?? input?.workspaceRoot;
        return typeof cwd === 'string' && cwd.length > 0 ? cwd : process.cwd();
    }
}
export function apply(ctx, config) {
    launchPanel(config);
    ctx.plugin(IslandService, config);
}
/** 自动拉起 macOS 灵动岛面板 app（若未在运行）。 */
function launchPanel(config = {}) {
    if (config.autoLaunchPanel === false)
        return;
    // lib/ 的上一级是插件根目录，面板 app 在 bin/dsh-island-panel.app
    const here = path.dirname(fileURLToPath(import.meta.url));
    const root = path.resolve(here, '..');
    const appPath = config.panelBin ?? path.join(root, 'bin', 'dsh-island-panel.app');
    const sock = config.socketPath ?? defaultSocketPath();
    if (existsSync(sock))
        return; // 面板已在运行，跳过
    // 优先用 `open` 启动 .app —— 由 LaunchServices 注册，status item 才能显示在菜单栏
    if (existsSync(appPath)) {
        execFile('open', [appPath], { env: { ...process.env, DSH_ISLAND_SOCKET_PATH: sock } }, () => { });
        return;
    }
    // 兜底：裸二进制（非 GUI 会话时可能不显示 status item）
    const bin = path.join(root, 'bin', 'dsh-island-panel');
    if (!existsSync(bin))
        return;
    const child = spawn(bin, [], {
        detached: true,
        stdio: 'ignore',
        env: { ...process.env, DSH_ISLAND_SOCKET_PATH: sock },
    });
    child.unref();
}
