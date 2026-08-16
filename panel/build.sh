#!/bin/bash
# build.sh —— 编译 dsh-island-panel（macOS 菜单栏灵动岛，Swift 原生）
# 产物：bin/dsh-island-panel（arm64，随插件分发，无需 Xcode）
# 资源：bin/whale2/（鲸鱼娘桌宠 15 动作，来自 vlln/whale-girl，MIT credit ZipZipPipe）
set -euo pipefail
cd "$(dirname "$0")/.."

mkdir -p bin

# 复制鲸鱼娘桌宠资源
rm -rf bin/whale2
cp -R panel/resources/whale2 bin/whale2
# 半身套件（托盘专用，头+上半身）
rm -rf bin/whale2b
cp -R panel/resources/whale2b bin/whale2b
# 二次元 Chibi 造型（抹鲸，MIT）
rm -rf bin/chibi bin/chibi2b
cp -R panel/resources/chibi bin/chibi
cp -R panel/resources/chibi2b bin/chibi2b
echo "whale2: $(ls bin/whale2/frames | wc -l | tr -d ' ') 动作, whale2b(半身): $(ls bin/whale2b/frames | wc -l | tr -d ' ') 动作, chibi: 2 动作"

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
