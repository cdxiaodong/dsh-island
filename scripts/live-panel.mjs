// live-panel.mjs —— 实时可视化 dsh-island 效果面板。
//
// 一个进程同时做三件事：
//  1. HTTP 服务 → 浏览器访问 http://127.0.0.1:3081 看到实时 CodeIsland 风格面板
//  2. Unix socket 接收端 → 真实 DSH 里的 dsh-island 推送的事件也会实时进面板
//  3. 内置演示模式 → 点页面按钮用「真实 dsh-island 插件」模拟一次完整会话，
//     不依赖模型 API key，立刻看效果
//
// 用法：node scripts/live-panel.mjs [--port 3081]
import { createServer } from 'node:http'
import { createServer as createUnixServer } from 'node:net'
import { tmpdir } from 'node:os'
import * as path from 'node:path'
import * as fs from 'node:fs'
import * as os from 'node:os'
import { randomUUID } from 'node:crypto'
import { Context } from 'cordis'
import * as dshIsland from '../lib/index.js'

const pi = process.argv.indexOf('--port')
const PORT = pi >= 0 && process.argv[pi + 1] ? Number(process.argv[pi + 1]) : 3081
const socketPath = process.env.CODEISLAND_SOCKET_PATH
  ?? `/tmp/codeisland-${process.getuid?.() ?? 0}.sock`

// ---------------------------------------------------------------------------
// SSE 广播
// ---------------------------------------------------------------------------
/** @type {import('node:http').ServerResponse[]} */
const clients = []
function broadcast(event) {
  const payload = `data: ${JSON.stringify(event)}\n\n`
  for (const res of clients) res.write(payload)
}

// ---------------------------------------------------------------------------
// 1. HTTP + SSE
// ---------------------------------------------------------------------------
const server = createServer((req, res) => {
  const url = new URL(req.url, `http://${req.headers.host}`)

  if (url.pathname === '/events') {
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    })
    res.write('retry: 1000\n\n')
    clients.push(res)
    req.on('close', () => clients.splice(clients.indexOf(res), 1))
    return
  }

  if (url.pathname === '/demo' && req.method === 'POST') {
    runDemo()
    res.writeHead(202).end('{"ok":true}')
    return
  }

  // 静态面板页
  if (url.pathname === '/' || url.pathname === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' })
    res.end(PANEL_HTML)
    return
  }
  res.writeHead(404).end('not found')
})

server.listen(PORT, () => {
  console.log(`\x1b[1m[dsh-island live panel]\x1b[0m http://127.0.0.1:${PORT}`)
})

// ---------------------------------------------------------------------------
// 2. Unix socket 接收端（真实 dsh 的 dsh-island 会连这里）
// ---------------------------------------------------------------------------
try { fs.unlinkSync(socketPath) } catch { /* ignore */ }
createUnixServer((conn) => {
  const chunks = []
  conn.on('data', (d) => chunks.push(d))
  conn.on('end', () => {
    const text = Buffer.concat(chunks).toString('utf8')
    if (!text.trim()) return
    let ev
    try { ev = JSON.parse(text) } catch { return }
    broadcast({ type: 'event', ...ev })
    // 审批自动 allow（真实 dsh 场景面板自动放行；也可在 UI 上改）
    if (ev.hook_event_name === 'PermissionRequest') {
      conn.end(JSON.stringify({ hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior: 'allow' } } }))
    } else {
      conn.end('{}')
    }
  })
  conn.on('error', () => {})
}).listen(socketPath, () => {
  console.log(`\x1b[2m  unix socket mock: ${socketPath}\x1b[0m`)
})

// ---------------------------------------------------------------------------
// 3. 内置演示：用真实 dsh-island 插件跑一次完整会话
// ---------------------------------------------------------------------------
async function runDemo() {
  broadcast({ type: 'status', text: '🔄 演示会话进行中…' })
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms))
  const root = new Context()
  await root.plugin(dshIsland, { socketPath, approvals: true, debug: false })

  const session = { id: 'demo-' + randomUUID().slice(0, 6), cwd: '/Users/cdxd/projects/awesome-agent' }
  const agent = { id: session.id, session }
  const exec = (callId, command) => ({ name: 'Bash', callId, arguments: { command }, agent })
  const ALLOW = () => Promise.resolve({ kind: 'allow' })
  const ACCEPT = () => Promise.resolve({ kind: 'accept' })

  root.emit('session/created', session)
  root.emit('agent/status', { ...session, status: 'processing' })
  await sleep(900)

  await root.waterfall('tools/pre-execute', exec('c1', 'git status --short'), ALLOW)
  await root.waterfall('tools/post-execute', exec('c1', 'git status --short'), { isError: false }, ACCEPT)
  await sleep(1100)

  await root.waterfall('tools/pre-execute', exec('c2', 'rm -rf node_modules'), ALLOW)
  const outcome = await root.waterfall('approval/request', {
    agent, toolName: 'Bash', callId: 'c2',
    reason: 'rm -rf node_modules — 高危命令，需要你确认',
  }, () => Promise.resolve({ outcome: 'unavailable' }))
  await sleep(1200)

  await root.waterfall('tools/post-execute', exec('c2', 'rm -rf node_modules'), { isError: false }, ACCEPT)
  await sleep(1100)

  root.emit('agent/status', { ...session, status: 'idle' })
  await sleep(600)
  root.emit('session/disposed', session)
  broadcast({ type: 'status', text: '✅ 演示完成 — 真实 dsh-island 插件已把 9 个事件推送到面板' })
}

// ---------------------------------------------------------------------------
// 面板 HTML（CodeIsland 像素风，SSE 实时更新）
// ---------------------------------------------------------------------------
const PANEL_HTML = `<!doctype html>
<html lang="zh">
<head>
<meta charset="utf-8">
<title>dsh-island 实时效果面板</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { background: #0d0d12; font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    color: #c9c9d6; display: flex; min-height: 100vh; align-items: center; justify-content: center; padding: 40px; }
  .wrap { width: 460px; display: flex; flex-direction: column; gap: 16px; }
  .island { background: #1a1a22; border: 1px solid #2b2b38; border-radius: 24px; padding: 18px;
    box-shadow: 0 18px 60px rgba(0,0,0,.6); }
  .top { display: flex; align-items: center; gap: 12px; margin-bottom: 14px; }
  .pixel { width: 40px; height: 40px; border-radius: 8px; background: linear-gradient(135deg,#4f8cff,#7a5cff);
    display: flex; align-items: center; justify-content: center; font-weight: 800; color: #fff; font-size: 18px; }
  .t-name { font-weight: 700; font-size: 15px; color: #fff; }
  .t-sub { font-size: 11px; color: #7a7a8e; max-width: 250px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .status { margin-left: auto; display: flex; align-items: center; gap: 6px; font-size: 11px; color: #7a7a8e; }
  .dot { width: 9px; height: 9px; border-radius: 50%; background: #555; transition: background .3s, box-shadow .3s; }
  .dot.live { background: #2ecc71; box-shadow: 0 0 8px #2ecc71; }
  .feed { background: #14141b; border: 1px solid #23232e; border-radius: 14px; padding: 10px 12px; min-height: 240px;
    max-height: 300px; overflow-y: auto; }
  .row { display: flex; align-items: center; gap: 8px; padding: 5px 0; border-bottom: 1px solid #1d1d28; font-size: 11.5px; }
  .row:last-child { border-bottom: none; }
  .ts { color: #55556a; min-width: 52px; }
  .icon { width: 14px; text-align: center; }
  .ev { color: #a9a9c0; min-width: 128px; }
  .tool { background: #1f1f2b; color: #7cb6ff; padding: 1px 6px; border-radius: 5px; font-size: 10.5px; }
  .q { color: #ffcf6b; }
  .approval { margin-top: 12px; background: #241c10; border: 1px solid #4a3a18; border-radius: 14px; padding: 14px; }
  .a-head { font-size: 12px; font-weight: 700; color: #ffcf6b; margin-bottom: 8px; }
  .a-cmd { font-size: 12px; margin-bottom: 6px; }
  .a-cmd code { background: #33280f; color: #ffcf6b; padding: 2px 6px; border-radius: 5px; }
  .a-reason { font-size: 11px; color: #a99a7a; margin-bottom: 10px; }
  .a-btns { display: flex; gap: 8px; }
  .a-btns button { flex: 1; padding: 8px; border-radius: 9px; border: none; font-size: 12px; font-weight: 700; cursor: pointer; font-family: inherit; }
  .allow { background: #2ecc71; color: #06230f; }
  .deny { background: #2b2b38; color: #e74c3c; }
  .a-result { font-size: 11px; color: #2ecc71; margin-top: 8px; }
  .hint { margin-top: 14px; text-align: center; font-size: 10.5px; color: #4a4a5e; line-height: 1.7; }
  .bar { display: flex; gap: 10px; }
  .bar button { flex: 1; padding: 12px; border-radius: 12px; border: none; font-size: 13px; font-weight: 700; cursor: pointer;
    font-family: inherit; background: linear-gradient(135deg,#4f8cff,#7a5cff); color: #fff; }
  .bar button:active { transform: scale(.98); }
  .bar button:disabled { opacity: .4; cursor: not-allowed; }
</style>
</head>
<body>
<div class="wrap">
  <div class="island">
    <div class="top">
      <div class="pixel">DSH</div>
      <div>
        <div class="t-name">DeepSeek Harness</div>
        <div class="t-sub" id="cwd">等待事件…</div>
      </div>
      <div class="status"><span class="dot" id="dot"></span><span id="statText">离线</span></div>
    </div>
    <div class="feed" id="feed"></div>
    <div class="approval" id="approval" style="display:none"></div>
    <div class="hint">dsh-island 把 DSH 的会话/工具/审批实时推到刘海面板。<br>下方「模拟一次会话」用<b>真实插件</b>演示完整流程（无需 API key）。</div>
  </div>
  <div class="bar">
    <button id="demoBtn">▶ 模拟一次完整会话</button>
  </div>
</div>
<script>
  const $ = (id) => document.getElementById(id)
  const feed = $('feed'), approval = $('approval')
  const icons = { SessionStart:'🟢', SessionEnd:'⚫', PreToolUse:'🔧', PostToolUse:'✅',
    PostToolUseFailure:'❌', PermissionRequest:'🛡️', SubagentStart:'🧩', SubagentStop:'🧩', Notification:'💬' }
  const cols = { SessionStart:'#2ecc71', SessionEnd:'#888', PreToolUse:'#4f8cff', PostToolUse:'#2ecc71',
    PostToolUseFailure:'#e74c3c', PermissionRequest:'#ffcf6b', Notification:'#a9a9c0' }

  function addEvent(ev) {
    const ts = new Date().toTimeString().slice(0,8)
    const row = document.createElement('div')
    row.className = 'row'
    row.innerHTML = '<span class="ts">'+ts+'</span><span class="icon">'+(icons[ev.hook_event_name]||'·')+'</span>'+
      '<span class="ev" style="color:'+(cols[ev.hook_event_name]||'#a9a9c0')+'">'+(ev.hook_event_name||ev.type)+'</span>'+
      (ev.tool_name ? '<span class="tool">'+ev.tool_name+'</span>' : '')+
      (ev.question ? '<span class="q">'+ev.question+'</span>' : '')+
      (ev.message ? '<span class="q">'+ev.message+'</span>' : '')
    feed.appendChild(row)
    feed.scrollTop = feed.scrollHeight
    if (ev.cwd) { $('cwd').textContent = ev.cwd; }
    // 状态灯
    if (ev.hook_event_name === 'SessionStart') setLive(true, '会话中')
    if (ev.hook_event_name === 'SessionEnd') setLive(false, '离线')
    if (ev.hook_event_name === 'PermissionRequest') showApproval(ev)
    if (ev.hook_event_name === 'PostToolUse') hideApproval('✅ 已批准执行')
  }
  function setLive(on, text) { $('dot').className = 'dot' + (on?' live':''); $('statText').textContent = text }
  function showApproval(ev) {
    approval.style.display = ''
    approval.innerHTML = '<div class="a-head">🛡️ 需要授权</div><div class="a-cmd">'+ev.tool_name+' · <code>'+ev.question+'</code></div>'+
      '<div class="a-reason">'+ev.question+'</div>'+
      '<div class="a-btns"><button class="allow" onclick="hideApproval(\'✅ 已批准\')">允许</button>'+
      '<button class="deny" onclick="hideApproval(\'⛔ 已拒绝\')">拒绝</button></div>'
  }
  function hideApproval(msg) { approval.innerHTML = '<div class="a-result">'+msg+'</div>' }
  window.hideApproval = hideApproval

  const es = new EventSource('/events')
  es.onmessage = (e) => {
    const d = JSON.parse(e.data)
    if (d.type === 'event') addEvent(d)
    if (d.type === 'status') { setLive(true, '演示'); document.title = d.text }
  }

  $('demoBtn').onclick = async () => {
    $('demoBtn').disabled = true
    feed.innerHTML = ''; approval.style.display = 'none'
    await fetch('/demo', { method: 'POST' })
    setTimeout(() => { $('demoBtn').disabled = false }, 7000)
  }
</script>
</body>
</html>`
