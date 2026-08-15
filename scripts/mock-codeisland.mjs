// mock-codeisland.mjs —— 在未安装 CodeIsland 应用时，模拟刘海面板的 Unix
// socket 接收端：监听 /tmp/codeisland-<uid>.sock，把 dsh-island 推送的事件
// 实时打印出来。对 PermissionRequest 默认自动 allow（可 --deny 改拒绝）。
//
// 用法：
//   node scripts/mock-codeisland.mjs [--allow|--deny] [--socket <path>]
//
// 演示步骤（另开终端）：
//   1. node scripts/mock-codeisland.mjs
//   2. dsh web   （或在 DSH 会话里发消息，观察本终端事件流）
import { createServer } from 'node:net'
import { defaultSocketPath } from '../lib/socket.js'
import * as fs from 'node:fs'

const args = process.argv.slice(2)
const decision = args.includes('--deny') ? 'deny' : 'allow'
const pathIdx = args.indexOf('--socket')
const socketPath = pathIdx >= 0 && args[pathIdx + 1] ? args[pathIdx + 1] : defaultSocketPath()

// 清理可能残留的旧 socket 文件
try { fs.unlinkSync(socketPath) } catch { /* ignore */ }

const COLORS = {
  SessionStart: '\x1b[32m', SessionEnd: '\x1b[90m',
  PreToolUse: '\x1b[36m', PostToolUse: '\x1b[32m', PostToolUseFailure: '\x1b[31m',
  PermissionRequest: '\x1b[33m', SubagentStart: '\x1b[35m', SubagentStop: '\x1b[35m',
  Notification: '\x1b[34m', reset: '\x1b[0m', dim: '\x1b[2m',
}
const icon = {
  SessionStart: '🟢', SessionEnd: '⚫', PreToolUse: '🔧', PostToolUse: '✅',
  PostToolUseFailure: '❌', PermissionRequest: '🛡️', SubagentStart: '🧩',
  SubagentStop: '🧩', Notification: '💬',
}

const server = createServer((conn) => {
  const chunks = []
  conn.on('data', (d) => chunks.push(d))
  conn.on('end', () => {
    const text = Buffer.concat(chunks).toString('utf8')
    if (!text.trim()) return
    let ev
    try { ev = JSON.parse(text) } catch { ev = { hook_event_name: '?', raw: text.slice(0, 200) } }

    const name = ev.hook_event_name ?? '?'
    const color = COLORS[name] ?? COLORS.reset
    const line = [
      `${COLORS.dim}${new Date().toISOString().slice(11, 19)}${COLORS.reset}`,
      `${icon[name] ?? '·'}`,
      `${color}${name}${COLORS.reset}`,
      ev.tool_name ? `${COLORS.dim}tool=${COLORS.reset}${ev.tool_name}` : '',
      ev.question ? `${COLORS.dim}question=${COLORS.reset}"${ev.question}"` : '',
      ev.message ? `${COLORS.dim}msg=${COLORS.reset}${ev.message}` : '',
      `${COLORS.dim}session=${COLORS.reset}${ev.session_id ?? '-'}`,
    ].filter(Boolean).join(' ')
    console.log(line)

    if (name === 'PermissionRequest') {
      const resp = { hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: decision } } }
      conn.end(JSON.stringify(resp))
    } else {
      conn.end('{}')
    }
  })
  conn.on('error', () => {})
})

server.listen(socketPath, () => {
  console.log(`\x1b[1m[dsh-island mock CodeIsland]\x1b[0m listening on ${socketPath}`)
  console.log(`\x1b[2m审批决策 = ${decision}（PermissionRequest 会自动回 ${decision}）\x1b[0m\n`)
})

process.on('SIGINT', () => { server.close(); try { fs.unlinkSync(socketPath) } catch {} ; process.exit(0) })
