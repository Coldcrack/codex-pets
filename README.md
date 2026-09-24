# codex-pet / Codex Pet

<p>
  <a href="#中文">中文</a> |
  <a href="#english">English</a>
</p>

<a id="中文"></a>

## 中文

codex-pet 是一款原生 macOS 桌面宠物，用于监测当前 Mac 上的 Codex 运行状态、额度和 token 用量。小鲸鱼常驻桌面边缘，通过气泡展示关键指标，点击后展开本机详情面板。

应用只读取本机 Codex 数据，不连接远程账号、代理管理面板或余额服务。

### 名称说明

- App 显示名、`.app` 名和安装名：`codex-pet`。
- Swift Package、可执行文件和模块名：`CodexPets`。
- 项目目录及 DMG 文件名前缀：`codex-pets`。

### 功能

- 桌面宠物常驻显示本机 Codex 状态和额度。
- 宠物可自由拖动；点击宠物展开本机详情面板。
- 详情面板显示当前运行和最近活动的任务。
- 显示任务 token 用量及活跃子代理数量。
- 显示 Codex 可用额度窗口、刷新时间和剩余重置次数。
- 显示今天、24 小时、7 天和 30 天 token 用量统计，并可配置顺序和显示状态。
- 支持宠物换肤、右键隐藏、菜单栏恢复和开机自启。
- 菜单栏可显示宠物、本机 `5h` 和 `7d` 额度，并支持拖拽排序或隐藏。

### 本机数据

应用主要读取当前用户目录中的 Codex 数据文件，例如：

- `~/.codex/state_5.sqlite`
- `~/.codex/logs_2.sqlite`
- `~/.codex/sessions`
- 最近的 rollout JSONL 文件

应用不会修改这些文件，也不需要配置远程地址、账号、密码或管理密钥。

### 设置

设置窗口包含：

- `Codex`：本机状态、历史用量、文件监听刷新频率，额度来源和任务范围。
- `启动与外观`：宠物换肤、消耗量项目、菜单栏项目、开机自启和显示选项。
- `关于`：版本和本机监测能力说明。

### 构建和运行

要求：

- macOS 14 或更高版本。
- Swift 6 toolchain / Xcode Command Line Tools。

直接运行：

```bash
swift run CodexPets
```

构建 release：

```bash
swift build -c release
```

构建 `.app` 和 `.dmg`：

```bash
./scripts/build-app.sh
```

安装到当前用户的 Applications 目录：

```bash
./scripts/install-user-app.sh
```

默认安装位置为 `~/Applications/codex-pet.app`。

### 调试命令

```bash
.build/release/CodexPets --print-snapshot
.build/release/CodexPets --print-fast-snapshot
.build/release/CodexPets --print-snapshot-json
.build/release/CodexPets --print-fast-snapshot-json
```

运行测试：

```bash
swift test
./scripts/run-regression-tests.sh
```

### 项目结构

```text
Package.swift                                  Swift Package 配置
Sources/CodexPets/                             应用源码
Sources/CodexPets/PetDashboardView.swift       桌宠气泡和本机详情面板
Sources/CodexPets/DetailPanelMetrics.swift     桌宠及详情面板布局尺寸
Sources/CodexPets/ScreenSafeAreaGeometry.swift 屏幕安全区计算
Sources/CodexPets/CodexUsageStore.swift        本机 Codex 数据读取与统计
Sources/CodexPets/CodexPetsSettings.swift      本机监测和外观设置
Tests/CodexPetsTests/                          Swift 单元测试
Tests/CodexPetsRegressionTests/                本机数据回归测试
Resources/CodexPet.png                         默认桌宠图片
scripts/build-app.sh                           构建 .app 和 .dmg
scripts/run-regression-tests.sh                运行完整回归测试
```

### 注意事项

- 桌宠默认出现在主屏幕右下角，可拖动到当前屏幕的其他位置。
- 本机监测依赖 Codex 的本地数据格式；Codex 改变文件结构时可能需要同步适配。
- 当前构建脚本使用 ad-hoc 签名，适合本机使用。公开发布时应使用 Developer ID 签名和 notarization。

<a id="english"></a>

## English

Codex Pet is a native macOS desktop companion that monitors Codex activity, quota windows, and token usage on the current Mac. The whale stays near the edge of the desktop, shows key metrics in a speech bubble, and opens a local detail panel when clicked.

The app reads local Codex data only. It does not connect to remote accounts, proxy-management panels, or balance services.

### Naming

- App display name, `.app` bundle name, and installation name: `codex-pet`.
- Swift package, executable, and module name: `CodexPets`.
- Project directory and DMG filename prefix: `codex-pets`.

### Features

- Persistent, draggable desktop pet showing local Codex status and quota.
- Local detail panel with running and recent tasks.
- Per-task token usage and active subagent counts.
- Codex quota windows, reset times, and remaining reset credits.
- Token-usage totals for today and the last 24 hours, 7 days, and 30 days, with configurable order and visibility.
- Custom pet artwork, context-menu hiding, menu-bar recovery, and launch at login.
- Reorderable menu-bar items for the pet and local `5h` / `7d` quotas.

### Local Data

The app primarily reads local Codex files such as:

- `~/.codex/state_5.sqlite`
- `~/.codex/logs_2.sqlite`
- `~/.codex/sessions`
- Recent rollout JSONL files

It does not modify those files and requires no remote URL, account, password, or management key.

### Settings

- `Codex`: local status, usage-history and file-watcher refresh intervals, quota source, and task range.
- `Launch & Appearance`: pet artwork, menu-bar items, launch at login, and visibility options.
- `About`: version and local-monitoring information.

### Build and Run

Requirements:

- macOS 14 or later.
- Swift 6 toolchain / Xcode Command Line Tools.

```bash
swift run CodexPets
swift build -c release
./scripts/build-app.sh
./scripts/install-user-app.sh
```

The default installation path is `~/Applications/codex-pet.app`.

### Debug Commands

```bash
.build/release/CodexPets --print-snapshot
.build/release/CodexPets --print-fast-snapshot
.build/release/CodexPets --print-snapshot-json
.build/release/CodexPets --print-fast-snapshot-json
```

Run tests:

```bash
swift test
./scripts/run-regression-tests.sh
```

### Repository Layout

```text
Package.swift                                  Swift Package configuration
Sources/CodexPets/                             App source
Sources/CodexPets/PetDashboardView.swift       Pet bubble and local detail panel
Sources/CodexPets/DetailPanelMetrics.swift     Pet and detail-panel layout metrics
Sources/CodexPets/ScreenSafeAreaGeometry.swift Screen safe-area calculations
Sources/CodexPets/CodexUsageStore.swift        Local Codex data and usage reader
Sources/CodexPets/CodexPetsSettings.swift      Local monitoring and appearance settings
Tests/CodexPetsTests/                          Swift unit tests
Tests/CodexPetsRegressionTests/                Local-data regression tests
Resources/CodexPet.png                         Default desktop-pet image
scripts/build-app.sh                           Build .app and .dmg
scripts/run-regression-tests.sh                Run the full regression suite
```

### Notes

- The pet appears near the bottom-right corner of the main screen by default and can be dragged elsewhere.
- Local monitoring depends on Codex's local data format and may need updates if that format changes.
- The build script uses ad-hoc signing for local use. Public releases should use Developer ID signing and notarization.
