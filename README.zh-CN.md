# Codex & Antigravity Usage Status（配额状态栏）

**[English](README.md) | [简体中文](README.zh-CN.md)**

轻量、零凭据接触的原生 macOS 顶部菜单栏应用，让你一眼看清 **OpenAI Codex** 与 **Google Antigravity**（Gemini 模型组 & Claude/GPT 模型组）的实时剩余配额、重置时间与本机 Token 消耗统计。

![Codex & Antigravity 顶部菜单栏横向三列效果图](docs/assets/menu-bar-3col.png)

---

## v0.5.0 更新：Token 用量统计、低于 15% 标红告警与额度列单独隐藏

- **下拉菜单新增 Token 用量（支持缓存命中率与点击复制）**：新增「Token 用量 · 今日 / 近 7 天」区域，分别显示 `[C] Codex`、`[G] Gemini`、`[A] Claude & GPT` 今日与近 7 天的 token 消耗及合计；每行子菜单含输入 / 缓存（自动计算命中率百分比） / 输出（含推理）明细、调用次数和今日优先的按模型排行。点击任意额度或统计行即可复制该行文本（点击 Token 标题行可复制完整汇总）。
- **低于 15% 红底白字胶囊高亮与桌面通知**：顶部状态栏中任意一项剩余额度低于 `15%` 时自动渲染为高对比度的红底白字圆角胶囊，并支持可选的 macOS 原生系统通知提醒（每个重置周期最多提醒一次，可在菜单「低额度通知提醒」随时开关）。
- **支持单独隐藏额度列**：菜单新增「显示额度」子菜单，可单独取消勾选隐藏 `[C] Codex`、`[G] Gemini` 或 `[A] Claude & GPT` 额度（设置自动保存，至少保留一项显示；下方 Token 用量统计不受影响）。
- **菜单一键「开机自启」与息屏零唤醒省电**：基于 macOS 原生 `SMAppService` 在菜单内直接开关开机自启；显示器息屏期间自动暂停后台轮询并启用内核定时器合并，后台实现零日志磁盘扫描（仅在点开菜单或手动刷新时按偏移增量读取）；全部界面统一跟随系统语言切换中英文。
- **本机只读、增量读取**：数据来自本机 Codex 会话日志（`~/.codex/sessions/**/rollout-*.jsonl` 中的 `token_count` 事件）与 Antigravity 对话记录（`~/.gemini/antigravity/brain/*/.system_generated/logs/transcript.jsonl`）。只解析 token 数字、模型名和时间，不保存、不上传对话内容；按文件偏移增量读取，刷新开销很小。已压缩的 Codex 历史（`.jsonl.zst`）不计入。
- **总量含缓存命中**：Codex 的 `input_tokens` 本身包含缓存，Antigravity 单独报告缓存读取；两者统一为「未缓存输入 + 缓存 + 输出」。
- **修正 Codex 窗口标签**：Codex 目前可能只返回一个 30 天窗口。菜单栏、下拉菜单、提示和 CLI 改为按实际窗口长度显示 `5H` / `7D` / `30D`（之前固定显示 `7D`，CLI 误显示为 `5h`）；超过 6 天后才重置的时间改为显示日期而非星期。
- **稳定性**：新增 90 秒刷新看门狗，单次查询卡住不会让应用停止刷新；Codex 读取不再阻塞等待 stderr 结束；某个 Antigravity 服务返回异常数据时自动尝试下一个；上报给 Codex 的客户端版本跟随应用版本。
- **调试命令**：在终端运行 `CodexUsageStatus.app/Contents/MacOS/CodexUsageStatus --tokens` 可打印 token 汇总。

## v0.4.4 更新：直连本地 Antigravity 服务、彻底消除 `sandboxd` 死锁与 CPU 死循环

- **直连 `127.0.0.1` 本地接口（彻底移除 `agy` 子进程）**：直接从运行中的 Antigravity 桌面端发现文件（`~/.gemini/antigravity/daemon/hub_*.json`）向 `127.0.0.1` 发起 `RetrieveUserQuotaSummary` 只读请求，并显式绕过公司 VPN / PAC / 系统代理。查询耗时降至约 **5 毫秒**，彻底避免拉起 `agy` 命令行触发 macOS `sandboxd` 64 线程死锁，开机自启更稳。
- **修复深浅色主题 KVO 引起的 `99.5%` CPU 死循环**：改为监听 `NSApp.effectiveAppearance` 并按深浅色状态去重，仅在真正切换外观时重绘一次，常驻 CPU 保持 `0.0%`。
- **隔离工作目录与无感静默等待**：`codex app-server` 运行于独立 `0700` 空临时目录；开机尚未打开 Antigravity 桌面端时，`G`/`A` 列安静保留缓存或显示 `--`（不再闪红 `?`），打开桌面端后自动实时同步。

## v0.4.2 更新：系统代理自动继承、防抖动容错与深浅色即时切换

- **自动继承 macOS 系统代理**：在开机自启或访达双击启动（LaunchServices 无终端环境变量）场景下，自动读取 macOS 系统代理设置并注入 `agy` / `codex` 子进程，开箱即用不超时。
- **防偶发断网变红**：Antigravity 超时放宽至 35 秒并内置自动重试；Mac 休眠唤醒后延迟 5 秒刷新；遇到 1~2 次瞬时网络抖动时保留上次有效配额并 30 秒快速重试（连续 3 次失败才显示红色 `?`）。
- **深浅色主题即时重绘与管道加固**：系统自动切换 Dark/Light 模式时立即重绘菜单栏文字；修复 `Settings...` 弹窗置顶与 `SIGPIPE` 管道容错。

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

- **Codex 数据源**：仅在独立临时目录中调用官方本地 Codex `app-server` 的只读方法 `account/rateLimits/read`。
- **Antigravity 数据源**：仅读取 `~/.gemini/antigravity/daemon/hub_*.json` 中的本机临时端口与 `csrfToken`，直连 `127.0.0.1` 调用官方只读接口 `RetrieveUserQuotaSummary`。
- **绝不触碰凭据**：不修改任何客户端文件，**不读取** `~/.codex/auth.json`、Google OAuth 凭据或系统钥匙串，**不扫描**用户文稿目录，也不接触 Cookie、API Key 或浏览器数据。

详见面向用户的隐私摘要 [PRIVACY.md](PRIVACY.md) 与工程硬边界规范 [SECURITY.md](SECURITY.md)。

---

## 运行要求

- macOS 13 或更高版本
- 已安装并登录以下至少一项工具：
  - **Codex**：安装于 `/Applications/ChatGPT.app` 或 `/Applications/Codex.app`（可通过环境变量 `CODEX_BIN` 自定义路径）
  - **Antigravity**：安装并运行 `/Applications/Antigravity.app` 桌面端

---

## 一键安装（通过 AI Agent 或终端免编译安装）

无需安装 Xcode 或克隆源码，你可以直接把下面这句话发给你的 **Codex / Antigravity / Claude Code** 等任意 AI Agent 让它自动安装：

```text
请帮我下载并安装最新版 FengXiaohub/codex-usage-status 到 /Applications 并启动：https://github.com/FengXiaohub/codex-usage-status
```

或者让 Agent（或你自己打开 macOS 终端）直接运行以下一键脚本——会自动识别 Apple Silicon (`arm64`) / Intel (`x86_64`) 芯片、拉取最新 Release 包、安装至 `/Applications`、解除系统隔离属性并启动：

```sh
ARCH="$(uname -m)"; [[ "$ARCH" == "x86_64" && "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]] && ARCH="arm64"
TAG="$(basename "$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/FengXiaohub/codex-usage-status/releases/latest)")"
TMP_DIR="$(mktemp -d)" && trap 'rm -rf "$TMP_DIR"' EXIT
curl -fL "https://github.com/FengXiaohub/codex-usage-status/releases/download/${TAG}/CodexUsageStatus-${TAG#v}-macos-${ARCH}.zip" -o "$TMP_DIR/app.zip" && ditto -x -k "$TMP_DIR/app.zip" "$TMP_DIR"
pkill -x CodexUsageStatus 2>/dev/null || true
rm -rf /Applications/CodexUsageStatus.app && ditto "$TMP_DIR/CodexUsageStatus.app" /Applications/CodexUsageStatus.app
xattr -cr /Applications/CodexUsageStatus.app && open -n /Applications/CodexUsageStatus.app
```

---

## 从 Release 手动下载安装

1. 前往 [GitHub Releases](https://github.com/FengXiaohub/codex-usage-status/releases/latest) 下载对应你 Mac 芯片架构的最新压缩包：
   - **Apple Silicon（M1 / M2 / M3 / M4 系列芯片）**：`CodexUsageStatus-0.5.0-macos-arm64.zip`
   - **Intel 芯片**：`CodexUsageStatus-0.5.0-macos-x86_64.zip`
2. 双击解压 ZIP 文件。
3. 将 `CodexUsageStatus.app` 拖入 `/Applications`（应用程序）目录。
4. 双击打开 `CodexUsageStatus.app`。

### 首次运行与自动同步说明

- **首次打开若提示“无法验证开发者”**：由于开源构建包暂未经过 Apple 开发者公证，首次打开可在 **系统设置 > 隐私与安全性** 中点击 **仍要打开**，或在终端执行以下命令解除隔离属性：
  ```sh
  xattr -cr /Applications/CodexUsageStatus.app
  ```
- **纯菜单栏运行与一键开机自启**：应用不会占用底部 Dock 栏。点击顶部菜单栏图标勾选 **「开机自启」** 即可一键开启登录自动启动。
- **随客户端更新实时同步**：应用内部不写死模型列表，直接读取本机已安装的 `ChatGPT.app` / `Codex.app` 与运行中的 `Antigravity.app` 本地服务实时获取配额；客户端升级或重新打开时会自动感知并即时刷新。

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
  - `App/`：菜单栏状态项生命周期、下拉菜单、低额度通知去重管理、定时刷新调度与路径配置。
  - `Codex/`：本地 Codex `app-server` JSON-RPC 客户端与 Antigravity `127.0.0.1` 本地服务并发拉取器。
  - `Domain/`：配额响应解码模型、三列数据归一化与 Token 统计报表模型。
  - `Tokens/`：本机会话日志 256 KB 零拷贝增量 Token 扫描器。
  - `UI/`：横向三列（`C` / `G` / `A`）徽章样式、低于 15% 胶囊高亮、单列显隐与 AppKit 绘制实现。
  - `Tests/`：Swift `XCTest` 自动化单元测试。
- `src/`：用于诊断与测试的 Node.js CLI 探针。
- `test/`：配额归一化与敏感信息脱敏的单元测试。
- `scripts/`：构建、运行、安装与发布打包脚本。
- `.github/workflows/`：CI 与 Release 自动构建工作流。
- `docs/`：架构说明、目录结构与发布文档。

更多结构与依赖边界说明请参阅 [docs/project-structure.md](docs/project-structure.md)。
