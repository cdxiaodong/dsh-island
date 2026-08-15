import { createConnection, type Socket } from 'node:net'
import { constants as fsConstants, statSync } from 'node:fs'

/**
 * CodeIsland 的 Unix socket 客户端。
 *
 * CodeIsland 通过 `/tmp/codeisland-<uid>.sock` 接收所有 AI 工具的 hook 事件：
 * 客户端 connect → 写入一帧 JSON → half-close（EOF 触发服务端处理）。
 *
 * - 非阻塞事件：服务端处理完立即回写 `{}` 并关闭连接。
 * - 阻塞事件（PermissionRequest / Notification 带 question）：服务端保持
 *   连接，直到用户在刘海面板上批准/拒绝后才回写
 *   `{"hookSpecificOutput":{...,"decision":{"behavior":"allow|deny"}}}`。
 */
export class CodeIslandSocket {
  readonly socketPath: string
  readonly connectTimeoutMs: number

  constructor(socketPath?: string, connectTimeoutMs = 1500) {
    this.socketPath = socketPath ?? defaultSocketPath()
    this.connectTimeoutMs = connectTimeoutMs
  }

  /** CodeIsland 应用是否在运行（socket 文件存在且为 Unix socket）。 */
  available(): boolean {
    try {
      const st = statSync(this.socketPath)
      return (st.mode & fsConstants.S_IFMT) === fsConstants.S_IFSOCK
    } catch {
      return false
    }
  }

  /**
   * 发送一帧事件。
   *
   * @param payload  事件 JSON（会被 `JSON.stringify` 后整帧写入）。
   * @param opts.wait  阻塞事件置 true —— 等待 CodeIsland 回写决策。
   * @param opts.timeoutMs  阻塞等待超时（毫秒）。非阻塞事件用 connectTimeoutMs。
   * @returns `{ ok, response?, error? }`；response 为服务端回写的 JSON。
   */
  send(
    payload: Record<string, unknown>,
    opts: { wait?: boolean; timeoutMs?: number } = {},
  ): Promise<SendResult> {
    const wait = opts.wait ?? false
    const timeoutMs = wait ? (opts.timeoutMs ?? 300_000) : this.connectTimeoutMs

    return new Promise((resolve) => {
      let settled = false
      const finish = (r: SendResult) => {
        if (settled) return
        settled = true
        clearTimeout(timer)
        resolve(r)
      }

      const sock: Socket = createConnection(this.socketPath)
      const chunks: Buffer[] = []

      const timer = setTimeout(() => {
        sock.destroy()
        finish({ ok: false, error: wait ? 'timeout' : 'connect_timeout' })
      }, timeoutMs)
      // 不让未处理的 error 打到进程级 uncaughtException
      sock.on('error', (err: NodeJS.ErrnoException) => {
        finish({ ok: false, error: err.code ?? err.message })
      })

      sock.on('connect', () => {
        sock.write(JSON.stringify(payload))
        // half-close：服务端在 EOF 后开始处理（与 codeisland-bridge 行为一致）
        sock.end()
      })

      sock.on('data', (d) => chunks.push(Buffer.isBuffer(d) ? d : Buffer.from(d)))

      sock.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8')
        if (!text.trim()) {
          finish({ ok: true })
          return
        }
        try {
          finish({ ok: true, response: JSON.parse(text) as Record<string, unknown> })
        } catch {
          finish({ ok: true, response: { raw: text } })
        }
      })

      sock.on('close', () => {
        if (!settled) finish({ ok: false, error: 'closed' })
      })
    })
  }
}

/**
 * dsh-island 面板的默认 Unix socket 路径。
 * 插件启动时自动拉起 macOS 灵动岛面板，面板监听此路径；插件把事件写进来。
 * 可用 DSH_ISLAND_SOCKET_PATH 覆盖（测试/自定义端口）。
 */
export function defaultSocketPath(): string {
  if (process.env.DSH_ISLAND_SOCKET_PATH) return process.env.DSH_ISLAND_SOCKET_PATH
  return `/tmp/dsh-island-${process.getuid?.() ?? 0}.sock`
}

export interface SendResult {
  ok: boolean
  /** 服务端回写并成功解析的 JSON（阻塞事件为决策 payload）。 */
  response?: Record<string, unknown>
  /** 失败原因（连接错误 / 超时 / 无法解析）。 */
  error?: string
}

/**
 * 从 CodeIsland 的 PermissionRequest 响应里解析决策。
 * 兼容两种回写形态：
 *   `{"hookSpecificOutput":{"decision":{"behavior":"allow"}}}`  （标准）
 *   `{"decision":{"behavior":"always"}}`                          （宽松）
 *
 * @returns 'allow' | 'deny' | null（无有效决策）
 */
export function parseDecision(response: Record<string, unknown> | undefined): 'allow' | 'deny' | null {
  if (!response) return null
  const ho = response.hookSpecificOutput as Record<string, unknown> | undefined
  const decision = (ho?.decision ?? response.decision) as Record<string, unknown> | undefined
  const behavior = decision?.behavior
  if (typeof behavior !== 'string') return null
  const b = behavior.trim().toLowerCase()
  if (b === 'allow' || b === 'always') return 'allow'
  if (b === 'deny') return 'deny'
  return null
}
