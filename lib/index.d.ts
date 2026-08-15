import { Context, Service } from 'cordis';
export declare const name = "dsh-island";
export interface Config {
    /** 覆盖 CodeIsland socket 路径（默认 /tmp/codeisland-<uid>.sock） */
    socketPath?: string;
    /** 上报给 CodeIsland 的 source 标识（默认 dsh） */
    source?: string;
    /** 审批事件等待 CodeIsland 决策的超时毫秒数（默认 5 分钟） */
    approvalTimeoutMs?: number;
    /** 是否把 approval/request 转发给 CodeIsland 审批（默认 true） */
    approvals?: boolean;
    /** 是否上报 subagent 启停（默认 true） */
    subagents?: boolean;
    /** 是否上报 agent/status 状态变化（默认 true） */
    agentStatus?: boolean;
    /** 开启后把发送的每个事件打到 stderr（排障用） */
    debug?: boolean;
}
declare module 'cordis' {
    interface Context {
        island: IslandService;
    }
}
export declare const provide: string[];
/**
 * dsh-island —— 把 DSH agent 的实时状态桥接到 CodeIsland 刘海面板。
 *
 * 事件映射（DSH → CodeIsland）：
 *   session/created        → SessionStart
 *   session/disposed       → SessionEnd
 *   tools/pre-execute      → PreToolUse
 *   tools/post-execute     → PostToolUse / PostToolUseFailure
 *   approval/request       → PermissionRequest（阻塞，回写决策）
 *   subagent/start         → SubagentStart
 *   subagent/end           → SubagentStop
 *   agent/status           → Notification
 *
 * 接入模型与 Claude/Codex 的 hook 不同：DSH 是插件运行时，所以本插件直接
 * 监听 DSH 内置事件，把归一化的 payload 写入 CodeIsland 的 Unix socket，
 * 无需任何 hook 配置文件。
 */
export declare class IslandService extends Service {
    private readonly client;
    private readonly source;
    private readonly approvalTimeoutMs;
    private readonly config;
    constructor(ctx: Context, config?: Config);
    private onPreToolUse;
    private onPostToolUse;
    private onApprovalRequest;
    private emit;
    /** 安全地委托给 waterfall 链的下一个监听器（默认放行/透传）。 */
    private delegate;
    private debug;
    /** 从 agent / session / exec / req 提取稳定 session_id。 */
    private sessionIdOf;
    private idOf;
    private cwdOf;
}
export declare function apply(ctx: Context, config?: Config): void;
//# sourceMappingURL=index.d.ts.map