<p align="center">
  <img src="docs/live-panel-approval.png" width="480" alt="dsh-island 灵动岛面板">
</p>

# dsh-island

> 自带 **macOS 菜单栏灵动岛** 的 DeepSeek Harness（DSH）插件 —— 插件一启动，DSH 的会话、工具调用、审批直接出现在你的**顶部菜单栏**，点击展开实时面板，无需安装任何第三方应用。

## 这是什么

开发 AI agent 时，最常见的烦恼是「切窗口看它到底在干嘛、是不是卡在审批」。**dsh-island 把 DSH 的实时状态带进 macOS 菜单栏**：

- 插件 apply 时**自动拉起原生 Swift 面板**（`bin/dsh-island-panel`，NSStatusItem + NSPopover + SwiftUI，借鉴 [CodeIsland](https://github.com/wxtsky/CodeIsland) 的实现）
- 菜单栏按钮文案**随状态动态变化**：`🐋 DSH`（空闲）→ `🔧 运行中 / 🔧 <工具>`（执行中）→ `🛡️ 需要授权`（审批中）
- 点击菜单栏图标 → 弹出毛玻璃灵动岛面板：会话、工具调用、事件流
- 审批请求直接在面板上点「允许 / 拒绝」，决策回写 DSH

```
DSH 进程
  └─ dsh-island 插件（cordis）
       ├─ apply() 时 spawn → bin/dsh-island-panel（Swift 原生，常驻菜单栏）
       ├─ 监听 DSH 事件（session/tools/approval/subagent/status）
       └─ Unix socket /tmp/dsh-island-<uid>.sock → 菜单栏图标 + 面板实时更新
                            ↑ 面板上点「允许/拒绝」→ 决策回写 DSH
```

**无需中间层**：不依赖 CodeIsland 应用、不写 hook 配置、不用浏览器。装插件即用。

## 功能

- **自动拉起**：插件加载即常驻菜单栏（已运行则不重复启动）
- **动态菜单栏**：按钮文案随状态变（空闲/运行中/等待授权）
- **会话状态**：`SessionStart` / `SessionEnd` 跟随 DSH 会话生命周期
- **工具调用**：`PreToolUse` / `PostToolUse` / `PostToolUseFailure` 实时展示正在执行的工具
- **面板审批**：`approval/request` → 面板出现「需要授权」卡，点「允许 / 拒绝」直接回写 DSH
- **子代理**：`SubagentStart` / `SubagentStop`
- **状态变化**：`agent/status` → 面板状态灯与提示
- **零侵入**：不修改 DSH 配置、不拦截工具决策（`next()` 总是放行）

## 事件映射

| DSH 事件 | 面板事件 | 方向 |
|---|---|---|
| `session/created` | SessionStart | 通知 |
| `session/disposed` | SessionEnd | 通知 |
| `tools/pre-execute` | PreToolUse | 通知 |
| `tools/post-execute` | PostToolUse / PostToolUseFailure | 通知 |
| `approval/request` | **PermissionRequest**（阻塞） | 双向 · 面板批准/拒绝回写 |
| `subagent/start` / `subagent/end` | SubagentStart / Stop | 通知 |
| `agent/status` | Notification | 通知 |

> 事件发送对 DSH 是**旁路观察**：`PreToolUse` / `PostToolUse` 监听器总是调用 `next()` 放行，发送失败也不影响 agent 执行。唯一「停留等待」的是 `approval/request` —— 这是审批的语义本身。

## 安装

```bash
dsh plugin --profile <profile> add github:cdxiaodong/dsh-island
```

前提：macOS 14+（面板为 arm64 二进制；Intel 需自行用 `panel/build.sh` 重编）。

## 配置

```typescript
interface Config {
  socketPath?: string        // 面板 socket（默认 /tmp/dsh-island-<uid>.sock）
  source?: string            // 上报的 source 标识（默认 dsh）
  approvalTimeoutMs?: number // 审批等待面板决策超时（默认 5 分钟）
  approvals?: boolean        // 是否把审批转发给面板（默认 true）
  subagents?: boolean        // 是否上报子代理事件（默认 true）
  agentStatus?: boolean      // 是否上报 agent 状态（默认 true）
  autoLaunchPanel?: boolean  // apply 时自动拉起面板（默认 true）
  panelBin?: string          // 覆盖面板二进制路径
  debug?: boolean            // 打印发送日志（默认 false）
}
```

## 开发

```bash
./panel/build.sh              # 编译 Swift 灵动岛面板 → bin/dsh-island-panel
npm run build                 # tsc → lib/
npm test                      # node --test，8 个用例
node scripts/live-panel.mjs   # 浏览器版实时演示（无 DSH 时看效果）
```

测试用 `cordis` Context 精确模拟 DSH 宿主的事件通道（`tools/*`、`approval/request` 均按宿主真实 waterfall 签名 `(exec, next)` 调用）。

## 架构（借鉴 CodeIsland）

| 组件 | 来源 |
|---|---|
| 菜单栏 NSStatusItem + NSPopover 灵动岛 | CodeIsland `StatusItemController` 思路 + 自研 popover |
| 菜单栏模板图标 / 状态文案 | CodeIsland `menuBarIcon` 的 template 约定 |
| NWListener Unix socket 接收 | CodeIsland `HookServer` |
| 深色毛玻璃 SwiftUI 卡片 | CodeIsland `NotchPanelView` 风格精简 |

## License

MIT
