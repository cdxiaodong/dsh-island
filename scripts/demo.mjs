// dsh-island 演示：在无真实 CodeIsland / DSH 宿主环境下，用 cordis Context
// 模拟一个完整 DSH agent 会话，驱动插件把状态实时推送到一个 mock 刘海面板，
// 最后生成 docs/demo-panel.html 用于可视化与截图。
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import * as path from 'node:path'
import * as fs from 'node:fs'
import { randomUUID } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { Context } from 'cordis'
import * as plugin from '../lib/index.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

// ---------------------------------------------------------------------------
// 1. Mock CodeIsland —— 监听临时 Unix socket，记录事件；对审批回 allow
// ---------------------------------------------------------------------------
const socketPath = path.join(tmpdir(), `ci-demo-${randomUUID().slice(0, 8)}.sock`)
/** @type {Array<Record<string, unknown>>} */
const events = []
const server = createServer((conn) => {
  const chunks = []
  conn.on('data', (d) => chunks.push(d))
  conn.on('end', () => {
    const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'))
    events.push({ ...payload, _receivedAt: new Date().toISOString() })
    if (payload.hook_event_name === 'PermissionRequest') {
      // 演示：面板自动批准
      conn.end(JSON.stringify({
        hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } },
      }))
    } else {
      conn.end('{}')
    }
  })
  conn.on('error', () => {})
})
await new Promise((r) => server.listen(socketPath, r))

// ---------------------------------------------------------------------------
// 2. 加载插件
// ---------------------------------------------------------------------------
const root = new Context()
await root.plugin(plugin, { socketPath, debug: true })

// ---------------------------------------------------------------------------
// 3. 模拟一个完整的 DSH agent 会话
// ---------------------------------------------------------------------------
const session = { id: 'dsh-demo-1', cwd: '/Users/cdxd/projects/awesome-agent' }
const agent = { id: session.id, session }
const exec = (callId, command) => ({ name: 'Bash', callId, arguments: { command }, agent })
const ALLOW = () => Promise.resolve({ kind: 'allow' })
const ACCEPT = () => Promise.resolve({ kind: 'accept' })

console.log('▶ 会话开始')
root.emit('session/created', session)
root.emit('agent/status', { ...session, status: 'processing' })
await sleep(250)

console.log('▶ 工具调用：git status')
await root.waterfall('tools/pre-execute', exec('call-1', 'git status --short'), ALLOW)
await root.waterfall('tools/post-execute', exec('call-1', 'git status --short'), { isError: false }, ACCEPT)
await sleep(250)

console.log('▶ 高危命令触发审批')
await root.waterfall('tools/pre-execute', exec('call-2', 'rm -rf node_modules'), ALLOW)
const approval = await root.waterfall('approval/request', {
  agent,
  toolName: 'Bash',
  callId: 'call-2',
  reason: 'rm -rf node_modules — 高危命令，需要你确认',
}, () => Promise.resolve({ outcome: 'unavailable' }))
console.log('   审批结果 →', JSON.stringify(approval))
await sleep(250)

console.log('▶ 工具完成')
await root.waterfall('tools/post-execute', exec('call-2', 'rm -rf node_modules'), { isError: false }, ACCEPT)
await sleep(250)

console.log('▶ 会话结束')
root.emit('agent/status', { ...session, status: 'idle' })
await sleep(150)
root.emit('session/disposed', session)

// 等待所有 socket 事件送达
await sleep(600)
server.close()

// ---------------------------------------------------------------------------
// 4. 生成可视化面板 HTML
// ---------------------------------------------------------------------------
const html = renderPanel(events)
const docsDir = path.join(__dirname, '..', 'docs')
fs.mkdirSync(docsDir, { recursive: true })
const htmlPath = path.join(docsDir, 'demo-panel.html')
fs.writeFileSync(htmlPath, html)

console.log('\n=== CodeIsland 收到的 DSH 事件 ===')
for (const e of events) {
  const tool = e.tool_name ? ` tool=${e.tool_name}` : ''
  const q = e.question ? ` question="${e.question}"` : ''
  console.log(`  [${e._receivedAt.slice(11, 19)}] ${e.hook_event_name}${tool}${q}  (session=${e.session_id})`)
}
console.log(`\n共 ${events.length} 个事件 → ${htmlPath}`)

// ---------------------------------------------------------------------------
// 5. 渲染面板（仿 CodeIsland 深色像素风）
// ---------------------------------------------------------------------------
function renderPanel(evts) {
  const sessionId = evts[0]?.session_id ?? 'dsh-demo-1'
  const cwd = evts[0]?.cwd ?? '/Users/cdxd/projects/awesome-agent'
  const approval = evts.find((e) => e.hook_event_name === 'PermissionRequest')

  const rows = evts.map((e, i) => {
    const ts = e._receivedAt.slice(11, 19)
    const icon = { SessionStart: '🟢', SessionEnd: '⚫', PreToolUse: '🔧', PostToolUse: '✅', PostToolUseFailure: '❌', PermissionRequest: '🛡️', SubagentStart: '🧩', SubagentStop: '🧩', Notification: '💬' }[e.hook_event_name] ?? '·'
    const detail = e.tool_name
      ? `<span class="tool">${e.tool_name}</span>`
      : e.question ? `<span class="q">${e.question}</span>` : ''
    return `<div class="row ${i === evts.length - 1 ? 'last' : ''}">
      <span class="ts">${ts}</span><span class="icon">${icon}</span>
      <span class="ev">${e.hook_event_name}</span>${detail}</div>`
  }).join('')

  const approvalCard = approval
    ? `<div class="approval">
        <div class="a-head">🛡️ 需要授权</div>
        <div class="a-cmd">Bash · <code>rm -rf node_modules</code></div>
        <div class="a-reason">${approval.question}</div>
        <div class="a-btns"><button class="allow">允许</button><button class="deny">拒绝</button></div>
        <div class="a-tip">↑ 在 CodeIsland 刘海面板上，这两个按钮就在眼前</div>
      </div>`
    : ''

  return `<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<title>DSH → CodeIsland 面板演示</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #0d0d12; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; color: #c9c9d6;
    display: flex; align-items: center; justify-content: center; min-height: 100vh; padding: 40px; }
  .island { width: 420px; background: #1a1a22; border: 1px solid #2b2b38; border-radius: 24px;
    padding: 18px; box-shadow: 0 18px 60px rgba(0,0,0,.6); }
  .top { display: flex; align-items: center; gap: 12px; margin-bottom: 14px; }
  .pixel { width: 40px; height: 40px; image-rendering: pixelated; background:
    linear-gradient(135deg,#4f8cff,#7a5cff); border-radius: 8px; display: flex; align-items: center;
    justify-content: center; font-weight: 800; color: #fff; font-size: 18px; }
  .t-name { font-weight: 700; font-size: 15px; color: #fff; }
  .t-sub { font-size: 11px; color: #7a7a8e; }
  .status { margin-left: auto; display: flex; align-items: center; gap: 6px; font-size: 11px; color: #7a7a8e; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: #2ecc71; box-shadow: 0 0 8px #2ecc71; }
  .feed { background: #14141b; border: 1px solid #23232e; border-radius: 14px; padding: 10px 12px;
    min-height: 220px; max-height: 300px; overflow-y: auto; }
  .row { display: flex; align-items: center; gap: 8px; padding: 5px 0; border-bottom: 1px solid #1d1d28;
    font-size: 11.5px; }
  .row:last-child { border-bottom: none; }
  .ts { color: #55556a; min-width: 52px; }
  .icon { width: 14px; text-align: center; }
  .ev { color: #a9a9c0; min-width: 128px; }
  .tool { background: #1f1f2b; color: #7cb6ff; padding: 1px 6px; border-radius: 5px; font-size: 10.5px; }
  .q { color: #ffcf6b; }
  .approval { margin-top: 12px; background: #241c10; border: 1px solid #4a3a18; border-radius: 14px;
    padding: 14px; }
  .a-head { font-size: 12px; font-weight: 700; color: #ffcf6b; margin-bottom: 8px; }
  .a-cmd { font-size: 12px; margin-bottom: 6px; }
  .a-cmd code { background: #33280f; color: #ffcf6b; padding: 2px 6px; border-radius: 5px; }
  .a-reason { font-size: 11px; color: #a99a7a; margin-bottom: 10px; }
  .a-btns { display: flex; gap: 8px; }
  .a-btns button { flex: 1; padding: 8px; border-radius: 9px; border: none; font-size: 12px; font-weight: 700;
    cursor: pointer; font-family: inherit; }
  .allow { background: #2ecc71; color: #06230f; }
  .deny { background: #2b2b38; color: #e74c3c; }
  .a-tip { margin-top: 10px; font-size: 10.5px; color: #6f6f86; text-align: center; }
  .foot { margin-top: 14px; text-align: center; font-size: 10.5px; color: #4a4a5e; }
</style>
</head>
<body>
  <div class="island">
    <div class="top">
      <div class="pixel">DSH</div>
      <div>
        <div class="t-name">DeepSeek Harness</div>
        <div class="t-sub">${cwd}</div>
      </div>
      <div class="status"><span class="dot"></span> 实时</div>
    </div>
    <div class="feed">${rows}</div>
    ${approvalCard}
    <div class="foot">由 dsh-island 插件通过 Unix socket 实时推送 · session ${sessionId}</div>
  </div>
</body>
</html>`
}
