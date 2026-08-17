<p align="center">
</p>

<h1 align="center">dsh-island · 鲸鱼娘灵动岛</h1>

<p align="center">
  <b>DeepSeek Harness (DSH) 的 macOS 菜单栏灵动岛</b> —— 插件一启动，DSH 的会话、工具调用、审批直接出现在顶部菜单栏，
  点击展开实时面板；配套 <b>跨端同步</b> 与 <b>手机动态管理端</b>，让 AI 任务一边跑、你一边掌控。
</p>

<p align="center">
  <a href="#-功能预览">功能预览</a> ·
  <a href="#-快速安装">快速安装</a> ·
  <a href="#-功能">功能</a> ·
  <a href="#-路线图-roadmap">路线图</a>
</p>

---

## 🎬 功能预览

**交互式预览（浏览器直接体验）**：`docs/` 下是一整套可运行的产品预览。本地起一个静态服务器即可逐页体验全部交互：

```bash
cd docs && python3 -m http.server 8080
# 打开 http://localhost:8080/index.html
```

### ① DSH 对话联动 · 会话全览 + Auto 模式

<img src="docs/screenshots/demo-dsh-link.gif" width="820" alt="DSH 对话联动">

所有 DSH 会话一屏总览：活跃会话、工具调用、时长、状态一目了然；点击会话二次展开最近工具 / Token / 运行模式（Auto 全程无需批准），可直接跳转会话或停止。灵动岛胶囊随状态实时切换「空闲 / 运行中 / 等待授权」。

### ② 跨端互通 · Mac 灵动岛 ↔ 手机灵动岛

<img src="docs/screenshots/demo-cross-sync.gif" width="820" alt="跨端互通">

任务在电脑上跑，进度实时同步到手机灵动岛：菜单栏胶囊一瞥即得，关键节点（完成/失败/审批）主动展开提醒，手机上直接跟随确认。异构灵动岛形态（macOS 菜单栏 ↔ iPhone Dynamic Island）同一状态源双向流转。

### ③ 价值对比 · 一天工作流的前后之差

<img src="docs/screenshots/demo-value.png" width="820" alt="价值对比">

镜头对准一个开发者的工作日：反复切窗看进度、错过关键节点、离开电脑即失联 —— 有了灵动岛之后，一瞥即得、主动提醒、手机随手掌控。数字会滚动，前后差距一目了然。

### ④ 手机动态管理端 · 接口映射，不写死任何一个功能

<img src="docs/screenshots/demo-manage.png" width="820" alt="手机动态管理端">

手机管理端从 DSH 拉取**能力清单**（原生功能 + 全部插件接口），**动态生成管理界面**：装上一个新的第三方插件，手机端自动多一个管理入口，App 永不过时。内置对多个真实高 star 插件（open-design 87.4k★、voyager 19.5k★、dsh-web-ui、modlens、OpenBiliClaw…）的实时监测：状态 / 调用量 / 内存 / 健康度，远程启停、检查更新。

> 预览即产品形态：追平甚至超越市面上「写死 UI」的 DSH 手机端，走的是「接口即入口」的动态映射路线。

---

## ⚡ 快速安装

```bash
dsh plugin --profile <profile> add github:cdxiaodong/dsh-island
```

前提：macOS 14+（面板为 arm64 二进制；Intel 需自行用 `panel/build.sh` 重编）。

---

## 是什么

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

## 托盘动态内容

菜单栏胶囊随 DSH 状态实时变化：

| 状态 | 托盘显示 |
|---|---|
| 空闲 | `空闲 5m`（会话时长）+ 鲸鱼娘 idle 慢眨眼 |
| 运行中 | `git commit ·12`（工具名 + 调用计数） |
| 等待授权 | `等待授权`（琥珀点 + 鲸鱼娘 wait 摆动） |
| 子代理 | 右键菜单显示 `子代理 N` |

鲸鱼娘半身动画 **15+ 动作**，随状态协调切换（working/think/wait/celebrate/error），空闲时随机轮播 walk/play/joy/sleep/eat/waving/wake 等。

## 插件注册接口

其他 DSH 插件可以在**托盘右键菜单**里注册自己的菜单项：

```typescript
import type { Context } from 'cordis'

export const inject = ['island']

export function apply(ctx: Context) {
  // 注册一个菜单项（出现在托盘右键菜单，图标 + 标题）
  ctx.island.registerMenuItem({
    id: 'my-plugin',
    title: '我的插件',
    icon: '🔧',
    action: () => {
      console.log('my-plugin clicked')
    },
  })
}
```

## 插件管理

托盘**右键 →「插件管理」**子菜单：动态列出 DSH 运行时所有插件（`●`运行 / `○`停止），点击运行中 → 关闭、停止 → 启用，插件加载/卸载自动刷新。

## 交互

- **左键**托盘 → 打开展示框（鲸鱼娘随机欢迎动作）
- **右键**托盘 → 菜单（状态/统计/插件管理/打开面板/退出）
- 点击展示框外部 → 自动关闭

---

## 🗺️ 路线图 Roadmap

以下能力已进入产品设计（见上方功能预览），正在陆续落地：

| 模块 | 状态 | 说明 |
|---|---|---|
| 📱 手机管理端 App | 🔨 开发中 | 从 DSH 拉取能力清单，动态生成管理界面（「接口即入口」路线） |
| 🔌 动态接口映射后端 | 🔨 开发中 | DSH 侧暴露 `/api/capabilities`，插件 / 原生功能统一注册 |
| 🔔 完成 / 审批通知提醒 | TODO | 灵动岛主动展开 + 系统通知，别错过关键节点 |
| 📊 Token / 用量面板 | TODO | 每会话 Token、成本、剩余额度一屏总览 |
| 👥 多会话管理 | TODO | 所有 DSH 会话列表 + 二次展开详情（预览已呈现） |
| 🎨 多套鲸鱼娘皮肤 | TODO | 图生图换肤：洛丽塔 / 水手服 / 宫廷 / 小魔女，一次一套穿搭 |
| 🌐 跨端实时同步 | TODO | Mac ↔ 手机状态双向同步（预览已呈现交互） |
| 🦴 Intel 原生面板 | TODO | 当前面板为 arm64，Intel 需重编 |

> 想看每一步的真实交互？运行上方「功能预览」里的演示即可 —— 界面、动效、状态流转皆是可点击的。

---

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

## 致谢

感谢 [LINUX DO](https://linux.do) 社区提供交流与推广的平台，感谢佬友们的反馈与支持。

## License

MIT
