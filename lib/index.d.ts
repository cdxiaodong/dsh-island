import { Context, Service } from 'cordis';
export declare const name = "dsh-island";
/** 其他插件通过 ctx.island.registerMenuItem 注册的托盘右键菜单项 */
export interface IslandMenuItem {
    id: string;
    title: string;
    icon?: string;
    /** 点击菜单项时执行 */
    action?: () => void | Promise<void>;
}
export interface Config {
    /** 覆盖面板 socket 路径（默认 /tmp/dsh-island-<uid>.sock） */
    socketPath?: string;
    /** 上报给面板的 source 标识（默认 dsh） */
    source?: string;
    /** 审批事件等待面板决策的超时毫秒数（默认 5 分钟） */
    approvalTimeoutMs?: number;
    /** 是否把 approval/request 转发给面板审批（默认 true） */
    approvals?: boolean;
    /** 是否上报 subagent 启停（默认 true） */
    subagents?: boolean;
    /** 是否上报 agent/status 状态变化（默认 true） */
    agentStatus?: boolean;
    /** 开启后把发送的每个事件打到 stderr（排障用） */
    debug?: boolean;
    /** 插件 apply 时自动拉起 macOS 灵动岛面板（默认 true） */
    autoLaunchPanel?: boolean;
    /** 覆盖面板二进制路径（默认 <插件>/bin/dsh-island-panel） */
    panelBin?: string;
}
declare module 'cordis' {
    interface Context {
        island: IslandService;
    }
}
export declare const provide: string[];
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
export declare class IslandService extends Service {
    private readonly client;
    private readonly source;
    private readonly approvalTimeoutMs;
    private readonly config;
    /** 其他插件注册的菜单项 */
    private menuItems;
    private ctlServer?;
    private pluginRefreshTimer;
    /** 插件管理：name → { callback, runtime }（registry 快照） */
    private pluginRegistry;
    /** 被禁用的插件缓存（enable 时恢复） */
    private disabledPlugins;
    constructor(ctx: Context, config?: Config);
    private onPreToolUse;
    private onPostToolUse;
    private onApprovalRequest;
    /**
     * 注册一个托盘右键菜单项。返回注销函数。
     * 其他 DSH 插件：inject: ['island']，然后 ctx.island.registerMenuItem(...)
     */
    registerMenuItem(item: IslandMenuItem): () => void;
    /** 把菜单项同步给面板（menu_set） */
    private pushMenu;
    /** 监听面板发来的命令（控制 socket /tmp/dsh-island-ctl-<uid>.sock） */
    private startCtlServer;
    /** 插件变化（加载/卸载）后防抖刷新面板插件列表 */
    private schedulePluginListRefresh;
    /** 收集 registry 里已加载的插件快照 */
    private collectPlugins;
    /** 把插件列表发给面板（plugin_list → 右键菜单「插件管理」） */
    private sendPluginList;
    /** 关闭插件（registry.delete + 缓存以便恢复） */
    disablePlugin(id: string): boolean;
    /** 启用插件（从禁用缓存恢复，或 registry 快照重建） */
    enablePlugin(id: string): boolean;
    private ctlSocketPath;
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