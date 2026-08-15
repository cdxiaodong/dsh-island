import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:net'
import { tmpdir } from 'node:os'
import * as path from 'node:path'
import { randomUUID } from 'node:crypto'
import { Context } from 'cordis'
import * as plugin from '../lib/index.js'
import { parseDecision } from '../lib/socket.js'

// ---------------------------------------------------------------------------
// Mock CodeIsland —— 监听临时 Unix socket，模拟刘海面板的接收行为：
//   EOF 后解析 JSON → 记录事件 → 按 setDecision 回写决策（否则回 {}）
// ---------------------------------------------------------------------------
function createMockIsland() {
  const socketPath = path.join(tmpdir(), `ci-${process.pid}-${randomUUID().slice(0, 8)}.sock`)
  /** @type {Array<Record<string, unknown>>} */
  const received = []
  /** @type {Array<'allow'|'deny'|undefined>} */
  const decisions = []

  const server = createServer((conn) => {
    const chunks = []
    conn.on('data', (d) => chunks.push(d))
    conn.on('end', () => {
      const payload = JSON.parse(Buffer.concat(chunks).toString('utf8'))
      received.push(payload)
      const behavior = decisions.shift()
      if (behavior === 'allow' || behavior === 'deny') {
        conn.end(JSON.stringify({
          hookSpecificOutput: { hookEventName: 'PermissionRequest', decision: { behavior } },
        }))
      } else {
        conn.end('{}')
      }
    })
    conn.on('error', () => {})
  })

  return new Promise((resolve) => {
    server.listen(socketPath, () => resolve({
      server,
      socketPath,
      received,
      setDecision: (d) => decisions.push(d),
      close: () => new Promise((r) => server.close(() => r())),
    }))
  })
}

/** 轮询等待条件满足（socket 事件是异步到达的）。 */
async function until(fn, timeout = 2000) {
  const start = Date.now()
  while (Date.now() - start < timeout) {
    if (fn()) return
    await new Promise((r) => setTimeout(r, 10))
  }
  throw new Error('until: timeout')
}

/** 创建已就绪的根 Context（cordis 的 plugin() 异步执行 apply，必须 await）。 */
async function makeRoot(config) {
  const root = new Context()
  await root.plugin(plugin, config)
  return root
}

// ---------------------------------------------------------------------------
// parseDecision 单元测试
// ---------------------------------------------------------------------------
test('parseDecision: 标准 allow / always / deny 与容错', () => {
  assert.equal(parseDecision({ hookSpecificOutput: { decision: { behavior: 'allow' } } }), 'allow')
  assert.equal(parseDecision({ hookSpecificOutput: { decision: { behavior: 'always' } } }), 'allow')
  assert.equal(parseDecision({ decision: { behavior: 'deny' } }), 'deny')
  assert.equal(parseDecision({ hookSpecificOutput: { decision: { behavior: 'ALWAYS' } } }), 'allow')
  assert.equal(parseDecision(undefined), null)
  assert.equal(parseDecision({}), null)
  assert.equal(parseDecision({ hookSpecificOutput: {} }), null)
})

// ---------------------------------------------------------------------------
// 会话生命周期
// ---------------------------------------------------------------------------
test('session/created → SessionStart，session/disposed → SessionEnd', async () => {
  const island = await createMockIsland()
  try {
    const root = await makeRoot({ socketPath: island.socketPath })
    const session = { id: 'sess-1', cwd: '/repo' }
    root.emit('session/created', session)
    root.emit('session/disposed', session)

    await until(() => island.received.length >= 2)
    const start = island.received.find((e) => e.hook_event_name === 'SessionStart')
    const end = island.received.find((e) => e.hook_event_name === 'SessionEnd')
    assert.ok(start)
    assert.equal(start.session_id, 'sess-1')
    assert.equal(start.cwd, '/repo')
    assert.equal(start._source, 'dsh')
    assert.ok(end)
    assert.equal(end.session_id, 'sess-1')
  } finally {
    await island.close()
  }
})

// ---------------------------------------------------------------------------
// 工具调用
// ---------------------------------------------------------------------------
test('tools/pre-execute → PreToolUse，且放行', async () => {
  const island = await createMockIsland()
  try {
    const root = await makeRoot({ socketPath: island.socketPath })
    const exec = {
      name: 'Bash',
      callId: 'call-1',
      arguments: { command: 'ls -la' },
      agent: { id: 'sess-1', session: { id: 'sess-1', cwd: '/repo' } },
    }
    const decision = await root.waterfall('tools/pre-execute', exec, () => Promise.resolve({ kind: 'allow' }))
    assert.deepEqual(decision, { kind: 'allow' })

    await until(() => island.received.some((e) => e.hook_event_name === 'PreToolUse'))
    const ev = island.received.find((e) => e.hook_event_name === 'PreToolUse')
    assert.equal(ev.tool_name, 'Bash')
    assert.equal(ev.tool_use_id, 'call-1')
    assert.deepEqual(ev.tool_input, { command: 'ls -la' })
    assert.equal(ev.session_id, 'sess-1')
  } finally {
    await island.close()
  }
})

test('tools/post-execute 成功 → PostToolUse，失败 → PostToolUseFailure', async () => {
  const island = await createMockIsland()
  try {
    const root = await makeRoot({ socketPath: island.socketPath })

    const ok = await root.waterfall(
      'tools/post-execute',
      { name: 'Read', callId: 'c1', arguments: { file_path: 'a.ts' } },
      { isError: false },
      () => Promise.resolve({ kind: 'accept' }),
    )
    assert.deepEqual(ok, { kind: 'accept' })

    await root.waterfall(
      'tools/post-execute',
      { name: 'Bash', callId: 'c2', arguments: { command: 'rm x' } },
      { isError: true, error: { message: 'boom' } },
      () => Promise.resolve({ kind: 'accept' }),
    )

    await until(() => island.received.some((e) => e.hook_event_name === 'PostToolUseFailure'))
    assert.ok(island.received.some((e) => e.hook_event_name === 'PostToolUse'))
    const fail = island.received.find((e) => e.hook_event_name === 'PostToolUseFailure')
    assert.equal(fail.tool_name, 'Bash')
  } finally {
    await island.close()
  }
})

// ---------------------------------------------------------------------------
// 审批
// ---------------------------------------------------------------------------
test('approval/request → PermissionRequest，allow → allowed-once', async () => {
  const island = await createMockIsland()
  island.setDecision('allow')
  try {
    const root = await makeRoot({ socketPath: island.socketPath })
    const req = {
      agent: { id: 'sess-1', session: { id: 'sess-1', cwd: '/repo' } },
      toolName: 'Bash',
      callId: 'call-9',
      reason: 'run rm -rf node_modules',
    }
    const outcome = await root.waterfall('approval/request', req, () => Promise.resolve({ outcome: 'unavailable' }))
    assert.deepEqual(outcome, { outcome: 'allowed-once' })

    await until(() => island.received.length >= 1)
    const ev = island.received[0]
    assert.equal(ev.hook_event_name, 'PermissionRequest')
    assert.equal(ev.tool_name, 'Bash')
    assert.equal(ev.question, 'run rm -rf node_modules')
    assert.equal(ev._source, 'dsh')
  } finally {
    await island.close()
  }
})

test('approval/request → deny → rejected', async () => {
  const island = await createMockIsland()
  island.setDecision('deny')
  try {
    const root = await makeRoot({ socketPath: island.socketPath })
    const req = { agent: { id: 'sess-1' }, toolName: 'Bash', reason: 'risky' }
    const outcome = await root.waterfall('approval/request', req, () => Promise.resolve({ outcome: 'unavailable' }))
    assert.deepEqual(outcome, { outcome: 'rejected' })
  } finally {
    await island.close()
  }
})

test('approval/request 但 CodeIsland 未运行 → 委托 next', async () => {
  const root = await makeRoot({ socketPath: path.join(tmpdir(), `nope-${randomUUID()}.sock`) })
  const req = { agent: { id: 'sess-1' }, toolName: 'Bash', reason: 'x' }
  const outcome = await root.waterfall('approval/request', req, () => Promise.resolve({ outcome: 'unavailable' }))
  assert.deepEqual(outcome, { outcome: 'unavailable' })
})

// ---------------------------------------------------------------------------
// subagent / agent status
// ---------------------------------------------------------------------------
test('subagent/start → SubagentStart，agent/status → Notification', async () => {
  const island = await createMockIsland()
  try {
    const root = await makeRoot({ socketPath: island.socketPath })

    root.emit('subagent/start', { id: 'agent-2', type: 'researcher' })
    root.emit('agent/status', { id: 'sess-1', status: 'processing' })

    await until(() =>
      island.received.some((e) => e.hook_event_name === 'SubagentStart')
      && island.received.some((e) => e.hook_event_name === 'Notification'))
    const sub = island.received.find((e) => e.hook_event_name === 'SubagentStart')
    const notif = island.received.find((e) => e.hook_event_name === 'Notification')
    assert.equal(sub.agent_type, 'researcher')
    assert.match(notif.message, /processing/)
  } finally {
    await island.close()
  }
})
