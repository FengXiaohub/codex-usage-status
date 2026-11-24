# Codex & Antigravity Usage Status（配额状态栏）

**[English](README.md) | [简体中文](README.zh-CN.md)**

轻量、零凭据接触的原生 macOS 顶部菜单栏应用，让你一眼看清 **OpenAI Codex** 与 **Google Antigravity**（Gemini 模型组 & Claude/GPT 模型组）的实时剩余配额与重置时间。

---

## v0.4.0 更新：Codex + Antigravity 横向三列并排显示

菜单栏图标现已升级为在单个紧凑的 `NSStatusItem` 内**横向并排显示三组模型配额**（`C | G | A`）：

- **`C`（Codex）**：来自本地 Codex `app-server`（支持 `/Applications/ChatGPT.app` 或 `/Applications/Codex.app`）的 5 小时（`5H`）与每周（`7D`）配额窗口。
- **`G`（Antigravity Gemini 模型组）**：来自本地 Antigravity CLI 的 Gemini 模型组（`Gemini 4 Neon / Carbon / Argon / Hydrogen`、`Orchestrator`、`Gemini 3.8 Flash`）5 小时与每周配额窗口。
- **`A`（Antigravity Claude & GPT 模型组）**：来自本地 Antigravity CLI 的第三方模型组（`Claude Opus / Sonnet`、`GPT-OSS`）5 小时与每周配额窗口。

### 默认显示样式（`Quota & Reset Times` 配额与重置时间）

默认采用横向三列（`C | G | A`）双行布局，每列左侧带有醒目的单字母粗体标识，右侧分上下两行展示剩余百分比与精确重置时刻：

```text
C 88%·21:05      | G 83%·明天00:55  | A 100%·明天01:28
  0%·周三15:32   |   91%·12月1日    |   100%·12月1日
```

在英文系统语言下自动切换为英文日期格式：

```text
C 88%·21:05      | G 83%·Tomorrow 00:55 | A 100%·Tomorrow 01:28
  0%·Wed15:32    |   91%·Dec 1 14:55    |   100%·Dec 1 20:28
```

- **第一行（上行）**：5 小时窗口（`5H`）剩余额度百分比与重置时间。
- **第二行（下行）**：每周窗口（`7D`）剩余额度百分比与重置时间。
- **独立容错与并发拉取**：Codex 与 Antigravity 采用并发查询；如果其中某一个工具未安装或暂不可用，其余可用列依然正常显示。
- **三种视觉样式可切换**：点击菜单栏图标，在 `Display Style` 下可随时切换 `Quota & Reset Times`（默认双行百分比+时间）、`Double Ring`（双圆环进度）和 `Large Readout`（大字号读数）。

---

## 历史版本更新

### v0.3.2 更新

macOS 应用支持最新版 ChatGPT 桌面端应用包路径（Codex 内嵌于 `Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex`），同时向下兼容旧版 ChatGPT 和独立版 Codex 路径。

### v0.3.1 更新

自动检测新版 `/Applications/ChatGPT.app` 与旧版 `/Applications/Codex.app` 中的 Codex 可执行文件，修复仅安装 ChatGPT 桌面端时出现红色 `?` 的问题。

### v0.3.0 更新

根据 Codex 返回的配额窗口自动适配布局：
- 同时具有 5 小时和每周窗口的 Plus 账号显示双行重置时间。
- 仅暴露每周窗口的 Pro 账号自动合并为单行大字居中显示（如 `43%·周日12:57`），并自动隐藏 5H 菜单项。

### v0.2.0 更新

新增紧凑的 `Quota & Reset Times`（配额与重置时间）显示样式，以及中英文双语本地化支持。

![Codex Usage Status menu-bar badge](docs/assets/menu-bar-badge.png)

---

## 安全模型（零凭据边界）

本应用严格遵守最小权限与本地安全边界：

- **Codex 数据源**：仅调用官方本地 Codex `app-server` 的只读方法 `account/rateLimits/read`。
- **Antigravity 数据源**：仅调用官方本地 Antigravity CLI 的只读命令 `agy -p "/usage" --output-format json`。
- **绝不触碰凭据**：不修改任何客户端文件，**不读取** `~/.codex/auth.json` 或 Antigravity 本地凭据库，**不读取、不存储、不传输**任何 Token、Cookie、Session、OAuth 凭据、API Key 或浏览器数据。

详见面向用户的隐私摘要 [PRIVACY.md](PRIVACY.md) 与工程硬边界规范 [SECURITY.md](SECURITY.md)。

---

## 运行要求

- macOS 13 或更高版本
- 已安装并登录以下至少一项工具：
  - **Codex**：安装于 `/Applications/ChatGPT.app` 或 `/Applications/Codex.app`（可通过环境变量 `CODEX_BIN` 自定义路径）
  - **Antigravity CLI (`agy`)**：安装于 `~/.local/bin/agy`、`/usr/local/bin/agy` 或 `/opt/homebrew/bin/agy`（可通过环境变量 `AGY_BIN` 自定义路径）

---

## 从 Release 安装

1. 前往 [GitHub Releases](https://github.com/FengXiaohub/codex-usage-status/releases/latest) 下载对应你 Mac 芯片架构的最新压缩包：
   - Apple Silicon (M 系列芯片)：`CodexUsageStatus-<version>-macos-arm64.zip`
   - Intel 芯片：`CodexUsageStatus-<version>-macos-x86_64.zip`
2. 解压 ZIP 文件。
3. 将 `CodexUsageStatus.app` 拖入 `/Applications`（应用程序）目录。
4. 打开 `CodexUsageStatus.app`。

本应用为纯菜单栏常驻应用（Menu-bar-only），不会占用底部 Dock 栏。你也可以将其添加到 `macOS 系统设置 > 通用 > 登录项` 实现开机自启。

---

## 从源码构建

源码构建环境要求：
- Swift 工具链 / Xcode Command Line Tools
- Node.js 20 或更高版本（用于运行单元测试与 CLI 诊断探针）

```sh
npm test
npm run build:macos
npm run start:macos
```

构建脚本会自动识别当前 Mac 的硬件架构（Apple Silicon 默认构建 `arm64`）。如需指定架构构建：

```sh
BUILD_ARCH=arm64 npm run build:macos
BUILD_ARCH=x86_64 npm run build:macos
```

一键构建并安装到 `/Applications` 目录：

```sh
npm run install:macos
```

默认刷新间隔为 120 秒（最小 60 秒，失败重试退避为 300 秒）。如需自定义刷新间隔：

```sh
CODEX_USAGE_REFRESH_SECONDS=180 npm run start:macos
```

---

## 命令行诊断探针（CLI Probe）

项目内置了 Node.js CLI 探针与原生单次诊断模式，可直接在终端查看三组配额：

```sh
# Node.js 文本与 JSON 探针
npm run usage
npm run usage:json

# 原生 Swift 二进制单次输出
./dist/CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus --once
# 示例输出：C 5h 88% 7d 0% | G 5h 83% 7d 91% | A 5h 100% 7d 100%
```

如果你的 `codex` 或 `agy` 安装在非标准路径，可通过环境变量指定：

```sh
CODEX_BIN=/path/to/codex AGY_BIN=/path/to/agy npm run usage
```

---

## 打包发布构建

```sh
npm run package:macos
npm run package:macos:all
```

`package:macos` 会在 `dist/` 下生成当前架构的 `.app` 压缩包；`package:macos:all` 会同时构建 `arm64` 与 `x86_64` 两个架构的发布包及 `SHA256SUMS.txt` 校验文件。

---

## 仓库目录结构

- `macos/CodexUsageStatus/`：原生 Swift / AppKit 菜单栏应用。
  - `App/`：菜单栏状态项生命周期、下拉菜单、定时刷新调度与路径配置。
  - `Codex/`：本地 Codex `app-server` JSON-RPC 客户端与 Antigravity `agy` CLI 并发拉取器。
  - `Domain/`：Codex 与 Antigravity 配额响应解码模型及三列数据归一化。
  - `UI/`：横向三列（`C` / `G` / `A`）徽章样式与 AppKit 绘制实现。
- `src/`：用于诊断与测试的 Node.js CLI 探针。
- `test/`：配额归一化与敏感信息脱敏的单元测试。
- `scripts/`：构建、运行、安装与发布打包脚本。
- `.github/workflows/`：CI 与 Release 自动构建工作流。
- `docs/`：架构说明、目录结构与发布文档。

更多结构与依赖边界说明请参阅 [docs/project-structure.md](docs/project-structure.md)。
