import { Context, Service } from 'cordis'
import { spawn } from 'node:child_process'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import * as path from 'node:path'
import { CodeIslandSocket, defaultSocketPath, parseDecision, type SendResult } from './socket.js'

export const name = 'dsh-island'

export interface Config {
  /** 覆盖面板 socket 路径（默认 /tmp/dsh-island-<uid>.sock） */
  socketPath?: string
  /** 上报给面板的 source 标识（默认 dsh） */
  source?: string
  /** 审批事件等待面板决策的超时毫秒数（默认 5 分钟） */
  approvalTimeoutMs?: number
  /** 是否把 approval/request 转发给面板审批（默认 true） */
  approvals?: boolean
  /** 是否上报 subagent 启停（默认 true） */
  subagents?: boolean
  /** 是否上报 agent/status 状态变化（默认 true） */
  agentStatus?: boolean
  /** 开启后把发送的每个事件打到 stderr（排障用） */
  debug?: boolean
  /** 插件 apply 时自动拉起 macOS 灵动岛面板（默认 true） */
  autoLaunchPanel?: boolean
  /** 覆盖面板二进制路径（默认 <插件>/bin/dsh-island-panel） */
  panelBin?: string
}

declare module 'cordis' {
  interface Context {
    island: IslandService
  }
}

export const provide = ['island']

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
  private readonly client: CodeIslandSocket
  private readonly source: string
  private readonly approvalTimeoutMs: number
  private readonly config: Config

  constructor(ctx: Context, config: Config = {}) {
    super(ctx, 'island')
    this.config = config
    this.source = config.source ?? 'dsh'
    this.approvalTimeoutMs = config.approvalTimeoutMs ?? 300_000
    this.client = new CodeIslandSocket(config.socketPath)

    // 会话生命周期
    ctx.on('session/created' as any, (session: any) => {
      void this.emit({
        hook_event_name: 'SessionStart',
        session_id: this.sessionIdOf(session),
        cwd: this.cwdOf(session),
      })
    })
    ctx.on('session/disposed' as any, (session: any) => {
      void this.emit({
        hook_event_name: 'SessionEnd',
        session_id: this.sessionIdOf(session),
      })
    })

    // 工具调用（观察型 waterfall 监听器：调用 next() 放行，不影响决策）
    ctx.on('tools/pre-execute' as any, (exec: any, next: any) =>
      this.onPreToolUse(exec, next))
    ctx.on('tools/post-execute' as any, (exec: any, result: any, next: any) =>
      this.onPostToolUse(exec, result, next))

    // 审批（answerer：转发给 CodeIsland，回写 allow/deny）
    if (config.approvals !== false) {
      ctx.on('approval/request' as any, (req: any, next: any) =>
        this.onApprovalRequest(req, next), true /* prepend：CodeIsland 优先审批 */)
    }

    // 子代理
    if (config.subagents !== false) {
      ctx.on('subagent/start' as any, (agent: any) => {
        void this.emit({
          hook_event_name: 'SubagentStart',
          session_id: this.sessionIdOf(agent),
          agent_id: this.idOf(agent),
          agent_type: agent?.type ?? agent?.kind ?? 'subagent',
        })
      })
      ctx.on('subagent/end' as any, (agent: any) => {
        void this.emit({
          hook_event_name: 'SubagentStop',
          session_id: this.sessionIdOf(agent),
          agent_id: this.idOf(agent),
          agent_type: agent?.type ?? agent?.kind ?? 'subagent',
        })
      })
    }

    // 状态变化
    if (config.agentStatus !== false) {
      ctx.on('agent/status' as any, (agent: any) => {
        const status = agent?.status ?? ''
        void this.emit({
          hook_event_name: 'Notification',
          session_id: this.sessionIdOf(agent),
          agent_id: this.idOf(agent),
          message: `Agent status: ${status}`,
        })
      })
    }
  }

  // ---- 事件处理器 -----------------------------------------------------

  private async onPreToolUse(exec: any, next: any) {
    void this.emit({
      hook_event_name: 'PreToolUse',
      session_id: this.sessionIdOf(exec),
      agent_id: this.idOf(exec),
      tool_name: exec?.name,
      tool_use_id: exec?.callId,
      tool_input: exec?.arguments,
      cwd: this.cwdOf(exec),
    })
    return this.delegate(next)
  }

  private async onPostToolUse(exec: any, result: any, next: any) {
    const isError = result?.isError === true || result?.error !== undefined
    void this.emit({
      hook_event_name: isError ? 'PostToolUseFailure' : 'PostToolUse',
      session_id: this.sessionIdOf(exec),
      agent_id: this.idOf(exec),
      tool_name: exec?.name,
      tool_use_id: exec?.callId,
      tool_input: exec?.arguments,
      cwd: this.cwdOf(exec),
    })
    return this.delegate(next, result)
  }

  private async onApprovalRequest(req: any, next: any) {
    const toolName = req?.toolName ?? req?.tool ?? 'tool'
    const reason = req?.reason ?? 'Approval requested'

    // CodeIsland 未运行 → 放行给下一个 answerer / 宿主默认处理
    if (!this.client.available()) return this.delegate(next)

    const res = await this.client.send(
      {
        hook_event_name: 'PermissionRequest',
        session_id: this.sessionIdOf(req),
        agent_id: this.idOf(req),
        tool_name: toolName,
        tool_use_id: req?.callId,
        question: reason,
        cwd: this.cwdOf(req),
        _source: this.source,
      },
      { wait: true, timeoutMs: this.approvalTimeoutMs },
    )
    const decision = parseDecision(res.response)
    this.debug('approval', { tool: toolName, reason, decision, error: res.error })

    if (decision === 'allow') return { outcome: 'allowed-once' }
    if (decision === 'deny') return { outcome: 'rejected' }

    // 超时 / 连接失败 / 无决策 → 放行给其他 answerer；没有则 fail-closed 拒绝
    const delegated = await this.delegate(next)
    return delegated ?? { outcome: 'rejected' }
  }

  // ---- 内部工具 -------------------------------------------------------

  private async emit(payload: Record<string, unknown>) {
    if (!this.client.available()) return
    const full: Record<string, unknown> = {
      ...payload,
      _source: this.source,
      cwd: (payload.cwd as string | undefined) ?? process.cwd(),
    }
    this.debug('emit', full)
    const res: SendResult = await this.client.send(full, { wait: false })
    if (!res.ok && res.error !== 'connect_timeout') {
      this.debug('send_failed', { error: res.error, payload: full })
    }
  }

  /** 安全地委托给 waterfall 链的下一个监听器（默认放行/透传）。 */
  private async delegate(next: any, fallback?: any): Promise<any> {
    if (typeof next !== 'function') return fallback
    try {
      return await next()
    } catch {
      return fallback
    }
  }

  private debug(tag: string, data: unknown) {
    if (this.config.debug) {
      process.stderr.write(`[dsh-island:${tag}] ${JSON.stringify(data)}\n`)
    }
  }

  /** 从 agent / session / exec / req 提取稳定 session_id。 */
  private sessionIdOf(input: any): string | undefined {
    const id = this.idOf(input)
      ?? input?.session?.id
      ?? (typeof input?.id === 'string' ? input.id : undefined)
    return id ?? `dsh-${process.pid}`
  }

  private idOf(input: any): string | undefined {
    if (!input) return undefined
    if (typeof input.agentId === 'string') return input.agentId
    if (input.agent && typeof input.agent.id === 'string') return input.agent.id
    return undefined
  }

  private cwdOf(input: any): string | undefined {
    const cwd = input?.cwd
      ?? input?.session?.cwd
      ?? input?.agent?.session?.cwd
      ?? input?.workspaceRoot
    return typeof cwd === 'string' && cwd.length > 0 ? cwd : process.cwd()
  }
}

export function apply(ctx: Context, config?: Config) {
  launchPanel(config)
  ctx.plugin(IslandService, config)
}

/** 自动拉起 macOS 灵动岛面板二进制（若未在运行）。 */
function launchPanel(config: Config = {}) {
  if (config.autoLaunchPanel === false) return
  // lib/ 的上一级是插件根目录，面板二进制在 bin/dsh-island-panel
  const here = path.dirname(fileURLToPath(import.meta.url))
  const bin = config.panelBin ?? path.resolve(here, '..', 'bin', 'dsh-island-panel')
  if (!existsSync(bin)) return
  const sock = config.socketPath ?? defaultSocketPath()
  if (existsSync(sock)) return // 面板已在运行，跳过
  const child = spawn(bin, [], {
    detached: true,
    stdio: 'ignore',
    env: { ...process.env, DSH_ISLAND_SOCKET_PATH: sock },
  })
  child.unref()
}
