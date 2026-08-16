# 【DSH 插件】dsh-island · 鲸鱼娘灵动岛 —— DSH 状态进 macOS 菜单栏,手机端还能动态管理

> 装一个插件,DSH 的会话 / 工具调用 / 审批直接出现在你的**顶部菜单栏**,点击展开实时面板即可批准/拒绝;配套手机端动态管理,新插件即插即用,App 永不过时。

---

## 🐋 是什么

开发 AI agent 时最烦的就是「切窗口看它到底在干嘛、是不是卡在审批」。**dsh-island 把 DSH 的实时状态带进 macOS 菜单栏**:

- 插件启动即**自动拉起原生 Swift 灵动岛面板**（NSStatusItem + NSPopover + SwiftUI）
- 菜单栏按钮随状态变:🐋 空闲 → 🔧 运行中 → 🛡️ 需要授权
- 点击展开毛玻璃面板:会话、工具调用、事件流一屏总览
- **审批直接在面板上点「允许/拒绝」**,决策回写 DSH
- 鲸鱼娘桌宠 15+ 动作动画,随状态切换,空闲时随机轮播

```
DSH ── dsh-island 插件（cordis）
      ├─ apply() 时 spawn → Swift 原生面板（常驻菜单栏）
      ├─ 监听 session/tools/approval/subagent/status 事件
      └─ Unix socket → 菜单栏图标 + 面板实时更新
              ↑ 面板点「允许/拒绝」→ 决策回写 DSH
```

无需中间层,不依赖 CodeIsland 应用,装插件即用。

## 🎬 功能预览(交互式演示)

`docs/` 目录放了一套**可运行的交互式产品预览**,本地起个静态服务器就能逐页体验:

```bash
cd docs && python3 -m http.server 8080
# 打开 http://localhost:8080/index.html
```

### ① 跨端互通 · Mac 灵动岛 ↔ 手机灵动岛
任务在电脑上跑,进度实时同步到手机;关键节点(完成/失败/审批)主动展开提醒。

### ② DSH 对话联动 · 会话全览 + Auto 模式
所有 DSH 会话一屏总览,点击二次展开「最近工具 / Token / 运行模式」,可直接跳转/停止会话。

### ③ 价值对比 · 一天工作流的前后之差
少切窗、不错过、心流不断 —— 数字会滚动,差距一目了然。

### ④ 手机动态管理端 · 接口映射,不写死任何一个功能
手机端从 DSH 拉取**能力清单**,**动态生成管理界面**:装新插件自动多一个入口。内置对多个真实高 star 插件(open-design 87.4k★ / voyager 19.5k★ / dsh-web-ui / modlens / OpenBiliClaw…)的实时监测:状态 / 调用量 / 内存 / 健康度,远程启停、检查更新。

## ⚡ 安装

```bash
dsh plugin --profile <profile> add github:cdxiaodong/dsh-island
```

- 前提:macOS 14+,arm64(Intel 需用 `panel/build.sh` 重编)

## 🗺️ Roadmap

| 模块 | 状态 |
|---|---|
| 📱 手机管理端 App | 🔨 开发中 |
| 🔌 动态接口映射后端 | 🔨 开发中 |
| 🔔 完成/审批通知提醒 | TODO |
| 📊 Token/用量面板 | TODO |
| 👥 多会话管理 | TODO |
| 🎨 多套鲸鱼娘皮肤 | TODO |
| 🌐 跨端实时同步 | TODO |

## 🔗 链接

- 仓库:https://github.com/cdxiaodong/dsh-island
- 聚合站:awesome-dsh-plugin.com 及各 awesome-deepseek-harness 列表均已收录
- 交流/反馈:可以在本贴回复,或在 GitHub Issues 提

---

*如果对你有帮助,欢迎 ⭐ 支持;有想加的功能/皮肤,评论区聊*