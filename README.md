# Ghidra-MCP-WSL-Auto

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Shell: Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?logo=gnubash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform: WSL2](https://img.shields.io/badge/Platform-WSL2-0078D4?logo=windows&logoColor=white)](https://docs.microsoft.com/en-us/windows/wsl/)

> **English** | [中文](#功能特色)
>
> One-click deployment of an **offline-capable agentic reverse engineering stack**: **Ghidra** + **[GhidraMCP](https://github.com/LaurieWired/GhidraMCP)** (Model Context Protocol), wired to the MCP client of your choice — including fully local models via Ollama, with no data leaving the machine.
>
> **Quick start:** `git clone https://github.com/astroicers/Ghidra-MCP-WSL-Auto.git && cd Ghidra-MCP-WSL-Auto && sudo ./install.sh`

一鍵部署**可離線運行的 agentic 逆向工程套件**：**Ghidra** + **[GhidraMCP](https://github.com/LaurieWired/GhidraMCP)** (Model Context Protocol)，並依需求接上任何 MCP client——包含**完全本地、不外送任何資料**的 Ollama 模型。

## 功能特色

- **三種連接模式**：Claude Code CLI、API Key、**本地模型（完全離線）**
- **Client 無關**：MCP SSE 端點為標準介面，任何支援 SSE 的 client 皆可連接（ollmcp / llama.cpp / Cline / 5ire）
- **離線就緒自檢** `--check-offline`：檢查 Ollama、模型下載狀態與模型規模是否足以支撐多步 tool calling
- 自動安裝 OpenJDK 21 及所有系統依賴
- 從 GitHub Release 自動下載 Ghidra（支援斷點續傳）
- 自動安裝 GhidraMCP 插件（處理雙層 ZIP 解包）
- 建立 Python venv 隔離環境安裝 MCP SDK
- 一鍵啟動器 `ghidra-mcp`（同時啟動 Ghidra + MCP Bridge）
- 冪等設計：重複執行安全，已完成步驟自動跳過
- GitHub API rate limit 自動重試（指數退避，最多 3 次）

## 連接模式選擇

本專案的 MCP Bridge 以標準 **SSE** 端點（`http://127.0.0.1:60006/sse`）對外，因此**不綁定任何特定 LLM 廠商**。依你的硬體與資料敏感度選擇：

| Tier | 適用情境 | 連接方式 | 能力 |
|------|----------|----------|------|
| **A** | 資料**不得外送**（惡意程式樣本、NDA 韌體、受管制二進位檔），且可執行 ≥14B 本地模型 | Ollama + ollmcp | **離線 agentic**，可跨函數多步分析 |
| **B** | 硬體僅能執行 <14B 模型 | 見下方說明 | 多步 tool calling 不可靠，建議改用單次分析工具 |
| **C** | 允許連線至雲端 | Claude Code CLI 或 API Key | **能力最強** |

> **重要：模型規模不是「效果好壞」，而是「能否運作」。**
> 小模型在多步 tool calling 上會直接失敗——3B 級約有 **89%** 的 tool 初始化失敗率，32B 級則接近 **0%**；且誤差會複利累積（每步 95% 成功 × 8 步 ≈ 66% 整體成功）。
> 因此 Tier A 建議至少 14B，實務上以 32B 級最穩定。安裝時與 `--check-offline` 皆會自動警告。

## 快速開始

```bash
git clone https://github.com/astroicers/Ghidra-MCP-WSL-Auto.git
cd Ghidra-MCP-WSL-Auto
sudo ./install.sh
```

安裝完成後，重新載入 PATH 並啟動：

```bash
source /etc/profile.d/ghidra.sh
ghidra-mcp    # 啟動 Ghidra + MCP Bridge
```

### 首次啟動設定

首次啟動 Ghidra 後，需啟用 GhidraMCP 插件：

1. **File** → **Configure** → **Developer** → 勾選 **GhidraMCPPlugin**
2. 關閉 Ghidra
3. 再次執行 `ghidra-mcp`（Launcher 會自動設定插件 port）

> 若自動設定失敗，手動設定：**Edit → Tool Options → GhidraMCP HTTP Server → Server Port: 60005**

### 連接 MCP Client

Bridge 啟動後即在 `http://127.0.0.1:60006/sse` 提供標準 MCP SSE 端點，以下任選其一連接。

**Tier C — Claude Code（能力最強，需連線至雲端）**

```bash
npm install -g @anthropic-ai/claude-code
claude mcp add --transport sse ghidra http://127.0.0.1:60006/sse
```

**Tier A — 本地模型（完全離線，資料不出本機）**

```bash
# 1. 安裝 Ollama 並下載模型（建議 ≥14B）
curl -fsSL https://ollama.com/install.sh | sh
ollama pull qwen2.5:32b

# 2. 安裝支援 SSE 的 MCP client
pipx install mcp-client-for-ollama      # 或 uvx mcp-client-for-ollama

# 3. 確認離線環境就緒
./install.sh --check-offline

# 4. 連接（需先另開終端執行 ghidra-mcp）
ollmcp --mcp-server-url http://127.0.0.1:60006/sse --model qwen2.5:32b
```

> 其他支援 SSE 的 client（llama.cpp 內建 MCP client、Cline、5ire 等）同樣可直接連接此端點，無須修改本專案。

**Tier B — 硬體僅支援 <14B 模型**

多步 tool calling 在此規模下不可靠。建議改用單次分析型工具（如 [GhidraGPT](https://github.com/weirdmachine64/GhidraGPT)，右鍵觸發、支援 Ollama），或改走 Tier C。

### Port 架構

| 元件 | Port | 說明 |
|------|------|------|
| Ghidra 插件 HTTP Server | 60005 | 插件內建 HTTP API（可透過 `.env` 中 `GHIDRA_PLUGIN_PORT` 自訂） |
| MCP Bridge SSE Server | 60006 | **標準 MCP SSE 端點**，任何支援 SSE 的 client 皆可連接（可透過 `.env` 中 `MCP_SERVER_PORT` 自訂） |

> **注意：** GhidraMCP 最新版已知支援 Ghidra 11.3.2。若使用更新版 Ghidra 遇到相容性問題，請用 `sudo GHIDRA_VERSION=11.3.2 ./install.sh` 重新安裝。

## 系統需求

- **OS**: Ubuntu 22.04 LTS 或更新版本（於 WSL2 上開發與驗證，原生 Linux 亦適用）
- **RAM**: 8GB 最低（建議 16GB+）
- **磁碟**: 至少 5GB 可用空間
- **網路**: 安裝時需連接 GitHub、OpenJDK 鏡像、Python PyPI（**安裝完成後，Tier A 可完全離線運行**）

### Tier A（離線 agentic）額外需求

本地模型需與 Ghidra 共存於同一台機器，兩者皆吃記憶體，請預先估算：

| 模型規模 | 建議 VRAM / RAM（僅模型，量化後） | 加上 Ghidra 的實務建議 |
|----------|-----------------------------------|------------------------|
| 14B | ~10GB | 24GB+ |
| 32B | ~20GB | 32GB+ |

> Ghidra 的 JVM 上限可用 `GHIDRA_XMX` 調整（預設依系統記憶體自動計算），必要時可調低以讓出空間給模型。

## 安裝選項

```bash
sudo ./install.sh                           # 標準安裝
sudo ./install.sh --verbose                 # 詳細輸出模式
sudo ./install.sh --skip-update             # 跳過 apt update/upgrade
sudo ./install.sh --no-interactive          # 跳過互動式連接模式設定
sudo GHIDRA_VERSION=11.3.1 ./install.sh     # 指定 Ghidra 版本
sudo GHIDRA_XMX=8192 ./install.sh           # 指定 JVM 記憶體 (MB)
./install.sh --check-offline                # 檢查離線模式就緒狀態（不安裝）
sudo ./install.sh --uninstall               # 移除所有已安裝元件
```

## MCP 連接模式

安裝過程中會提示選擇 MCP 連接模式：

### 模式一：Claude Code CLI（Tier C，能力最強）

在 WSL 中安裝 [Claude Code](https://docs.anthropic.com/en/docs/claude-code) CLI，直接連接 GhidraMCP Server：

```bash
# 安裝 Claude Code
npm install -g @anthropic-ai/claude-code

# 啟動（會引導登入 Anthropic 帳號）
claude
```

將 GhidraMCP 加入 Claude Code 的 MCP Server：

```bash
claude mcp add --transport sse ghidra http://127.0.0.1:60006/sse
```

**使用流程：**

1. 啟動 Ghidra + MCP Bridge：`ghidra-mcp`
2. 在 Ghidra 中開啟要分析的二進位檔案
3. 在另一個終端啟動 Claude Code：`claude`
4. Claude 即可透過 MCP 協定存取 Ghidra 的反組譯結果

### 模式二：API Key（Tier C）

安裝時選擇 API Key 模式，支援 OpenAI / Anthropic / 自訂提供者。
API Key 安全存儲於 `/opt/ghidra-mcp/GhidraMCP/.env`（chmod 600）。

| 提供者 | API Key 管理 |
|--------|-------------|
| OpenAI | [API Keys](https://platform.openai.com/api-keys) |
| Anthropic (Claude) | [API Keys](https://console.anthropic.com/settings/keys) |

### 模式三：本地模型（Tier A，完全離線）

適用於**資料不得外送**的場景——惡意程式樣本、受 NDA 約束的韌體、涉及出口管制的二進位檔。
安裝時選擇模式 3，設定寫入 `.env`（`MCP_MODE=local`，**不含任何金鑰**，chmod 644）：

```bash
OLLAMA_HOST=http://127.0.0.1:11434
OLLAMA_MODEL=qwen2.5:32b
```

安裝後以 `./install.sh --check-offline` 驗證環境就緒狀態，它會檢查：

1. Ollama daemon 是否運行
2. 指定模型是否已下載
3. **模型規模是否足以支撐多步 tool calling**（<14B 會明確警告）
4. MCP SSE 端點是否可連接

```console
$ ./install.sh --check-offline
[INFO ] === 離線就緒自檢 ===
[OK   ] 已載入設定: /opt/ghidra-mcp/GhidraMCP/.env (MCP_MODE=local)
[OK   ] Ollama daemon 運行中: http://127.0.0.1:11434
[OK   ] 模型已就緒: qwen2.5:32b
[OK   ] 模型 qwen2.5:32b 約 32B，符合 agentic 門檻（≥ 14B）
[OK   ] MCP SSE 端點可連接: http://127.0.0.1:60006/sse
[OK   ] 離線就緒檢查通過，可執行離線 agentic 分析
```

> 使用 `--no-interactive` 可跳過連接模式設定，之後手動編輯 `/opt/ghidra-mcp/GhidraMCP/.env`。

## 專案結構

```
Ghidra-MCP-WSL-Auto/
├── install.sh                 # 主安裝腳本
├── scripts/                   # F1~F3 模組化子腳本
│   ├── check_env.sh           #   環境檢測與依賴安裝
│   ├── setup_ghidra.sh        #   Ghidra 自動部署
│   └── setup_mcp.sh           #   GhidraMCP 插件整合
├── config/                    # 模板文件
│   ├── .env.template          #   MCP 連接模式設定模板
│   └── ghidra.desktop         #   Linux 桌面快捷方式
├── bin/                       # 啟動器（install 時自動產生）
├── tests/                     # bats 測試（51 個驗證案例）
│   ├── test_helper.bash
│   ├── check_env.bats
│   ├── install.bats
│   ├── setup_ghidra.bats
│   └── setup_mcp.bats
├── docs/                      # 所有文件
│   ├── SRS.md                 #   需求規格書
│   ├── architecture.md        #   系統架構
│   ├── adr/                   #   架構決策記錄
│   └── specs/                 #   技術規格書
└── Makefile                   # 開發指令
```

## 開發

```bash
make help          # 查看所有可用指令
make build         # 語法檢查
make lint          # shellcheck 靜態分析
make test          # 執行 bats 測試
make adr-list      # 查看架構決策記錄
make spec-list     # 查看技術規格書
```

## 文件

- [docs/SRS.md](docs/SRS.md) — 需求規格書
- [docs/architecture.md](docs/architecture.md) — 系統架構
- [docs/adr/](docs/adr/) — 架構決策記錄
- [docs/specs/](docs/specs/) — 技術規格書

## 授權 / License

[MIT License](LICENSE)
