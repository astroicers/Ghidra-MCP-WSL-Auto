# Ghidra-MCP-WSL-Auto

一鍵部署 **Ghidra** 逆向工程平台及 **[GhidraMCP](https://github.com/LaurieWired/GhidraMCP)** (Model Context Protocol) 插件於 **WSL2 Ubuntu/Debian** 環境。

## 功能特色

- 自動偵測 WSL2 環境、安裝 OpenJDK 21 及所有系統依賴
- 從 GitHub Release 自動下載最新版 Ghidra（支援斷點續傳）
- 自動安裝 GhidraMCP 插件（處理雙層 ZIP 解包）
- 建立 Python venv 隔離環境安裝 MCP SDK
- 雙模式 MCP 連接：Claude Code CLI（推薦）或 API Key
- 一鍵啟動器 `ghidra-mcp`（同時啟動 Ghidra + MCP Bridge）
- 冪等設計：重複執行安全，已完成步驟自動跳過
- GitHub API rate limit 自動重試（指數退避，最多 3 次）

## 快速開始

```bash
git clone https://github.com/YOUR_USERNAME/Ghidra-MCP-WSL-Auto.git
cd Ghidra-MCP-WSL-Auto
sudo ./install.sh
```

安裝完成後，重新載入 PATH 並啟動：

```bash
source /etc/profile.d/ghidra.sh
ghidra-mcp    # 啟動 Ghidra + MCP Bridge
```

首次啟動 Ghidra 後，需啟用 GhidraMCP 插件：

1. **File** → **Configure** → **Developer**
2. 勾選 **GhidraMCPPlugin**
3. 重啟 Ghidra

啟用後，Ghidra 插件 HTTP Server 會在 `http://127.0.0.1:18080` 運行（可透過 `.env` 中 `GHIDRA_PLUGIN_PORT` 自訂），MCP Bridge SSE Server 則在 `http://127.0.0.1:60006`。

## 系統需求

- **宿主 OS**: Windows 10 (22H2+) 或 Windows 11
- **WSL**: WSL 2 + Ubuntu 22.04 LTS 或更新版本
- **RAM**: 8GB 最低（建議 16GB+）
- **磁碟**: 至少 5GB 可用空間
- **網路**: 需連接 GitHub、OpenJDK 鏡像、Python PyPI

## 安裝選項

```bash
sudo ./install.sh                           # 標準安裝
sudo ./install.sh --verbose                 # 詳細輸出模式
sudo ./install.sh --skip-update             # 跳過 apt update/upgrade
sudo ./install.sh --no-interactive          # 跳過互動式連接模式設定
sudo GHIDRA_VERSION=11.3.1 ./install.sh     # 指定 Ghidra 版本
sudo GHIDRA_XMX=8192 ./install.sh           # 指定 JVM 記憶體 (MB)
sudo ./install.sh --uninstall               # 移除所有已安裝元件
```

## MCP 連接模式

安裝過程中會提示選擇 MCP 連接模式：

### 模式一：Claude Code CLI（推薦）

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

### 模式二：API Key

安裝時選擇 API Key 模式，支援 OpenAI / Anthropic / 自訂提供者。
API Key 安全存儲於 `/opt/ghidra-mcp/GhidraMCP/.env`（chmod 600）。

| 提供者 | API Key 管理 |
|--------|-------------|
| OpenAI | [API Keys](https://platform.openai.com/api-keys) |
| Anthropic (Claude) | [API Keys](https://console.anthropic.com/settings/keys) |

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
├── tests/                     # bats 測試（38 個驗證案例）
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

## 授權

MIT License
