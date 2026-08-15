#!/bin/bash
# build.sh —— 编译 dsh-island-panel（macOS 灵动岛面板，Swift 原生）
# 产物：bin/dsh-island-panel（arm64，随插件分发，无需 Xcode）
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p bin

# -swift-version 5 关闭 Swift 6 严格并发检查（兼容性优先）
swiftc -swift-version 5 \
  panel/main.swift \
  panel/PanelModel.swift \
  panel/SocketServer.swift \
  panel/PanelView.swift \
  panel/StatusBarController.swift \
  -o bin/dsh-island-panel \
  -framework AppKit -framework SwiftUI -framework Network -framework Combine

echo "✓ built bin/dsh-island-panel ($(file -b bin/dsh-island-panel | cut -d, -f1-2))"
