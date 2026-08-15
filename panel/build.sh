#!/bin/bash
# build.sh —— 编译 dsh-island-panel（macOS 菜单栏灵动岛，Swift 原生）
# 产物：bin/dsh-island-panel（arm64，随插件分发，无需 Xcode）
# 资源：bin/whale/*.gif（鲸鱼娘动画，来自 dsh-web-ui dsh-pet，Apache-2.0）
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p bin

# 复制鲸鱼娘动画资源
rm -rf bin/whale
cp -R panel/resources/whale bin/whale

# -swift-version 5 关闭 Swift 6 严格并发检查（兼容性优先）
swiftc -swift-version 5 \
  panel/main.swift \
  panel/PanelModel.swift \
  panel/SocketServer.swift \
  panel/PanelView.swift \
  panel/WhaleSprite.swift \
  panel/StatusBarController.swift \
  -o bin/dsh-island-panel \
  -framework AppKit -framework SwiftUI -framework Network -framework Combine

echo "✓ built bin/dsh-island-panel ($(file -b bin/dsh-island-panel | cut -d, -f1-2))"
echo "✓ whale sprites: $(ls bin/whale | wc -l | tr -d ' ') gifs"
