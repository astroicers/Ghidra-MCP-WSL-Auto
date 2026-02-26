# 📋 專案需求規格書 (SRS) - Ghidra-MCP-WSL-Auto

## 1. 專案目標

開發一個自動化 Bash 腳本，實現在 **Windows WSL (Ubuntu/Debian)** 環境下「一鍵式」部署 **Ghidra** 逆向工程平台及其 **GhidraMCP** (Model Context Protocol) 插件。旨在消除跨平台環境配置的複雜性，讓安全研究人員能快速獲得 AI 輔助的逆向分析能力。

---

## 2. 系統環境要求 (System Requirements)

* **宿主作業系統**: Windows 10 (22H2+) 或 Windows 11。
* **虛擬化環境**: WSL 2 (建議 Ubuntu 22.04 LTS 或更新版本)。
* **硬體建議**:
* RAM: 至少 8GB (建議 16GB+)。
* Disk: 至少 5GB 剩餘空間。


* **網路**: 需具備連接 GitHub、OpenJDK 鏡像與 Python PyPI 的權限。

---

## 3. 核心功能需求 (Functional Requirements)

### F1: 環境自動初始化

* **系統更新**: 自動執行 `apt update && apt upgrade`。
* **依賴安裝**: 自動檢測並安裝：
* **Java Runtime**: OpenJDK 21 (Ghidra 11.x 必備)。
* **Python 環境**: Python 3.10+ 及 `python3-venv`。
* **工具鏈**: `wget`, `unzip`, `git`, `curl`, `libawt-x11` (GUI 支援)。



### F2: Ghidra 自動部署

* **動態獲取**: 從 Ghidra GitHub Releases 自動抓取最新的穩定版本下載連結。
* **靜默安裝**: 解壓至 `/opt/ghidra` 並配置適當的檔案權限。
* **效能優化**: 根據系統 RAM 自動計算並修改 `ghidraRun.vmoptions` 中的 `-Xmx` 參數。

### F3: GhidraMCP 插件整合

* **自動拉取**: Clone `LaurieWired/GhidraMCP` 倉庫。
* **虛擬環境建置**: 在插件目錄下建立獨立的 `venv`，避免系統庫汙染。
* **自動掛載**: 將編譯好的插件 (Extension) 軟連結或複製到 Ghidra 的擴充路徑。
* **MCP 連接模式**: 支援 Claude Code CLI（推薦）和 API Key 兩種模式，互動式引導設定。

### F4: 啟動與整合優化

* **全域路徑**: 將 `ghidra` 命令加入使用者 `$PATH`。
* **一鍵啟動器**: 建立一個封裝腳本，啟動時自動檢查 MCP 後端服務狀態。

---

## 4. 非功能需求 (Non-Functional Requirements)

* **冪等性 (Idempotency)**: 腳本多次執行不會導致重複安裝或損壞環境。
* **錯誤處理**:
* 若網路中斷，應支援斷點續傳或清理殘餘檔案。
* 腳本需在非 WSL 環境執行時自動報警並退出。


* **透明度**: 提供詳細的安裝日誌 (`install.log`)。
* **安全性**: API Key（若使用 API Key 模式）不得明文出現在腳本或日誌中。

---

## 5. 專案結構建議 (Folder Structure)

```text
Ghidra-MCP-WSL-Auto/
├── install.sh                 # 主進入點腳本
├── CLAUDE.md                  # AI 行為憲法
├── README.md                  # 說明文件
├── CHANGELOG.md               # 變更記錄
├── Makefile                   # 開發指令
├── scripts/                   # 模組化子腳本
│   ├── check_env.sh           #   F1: 環境檢測
│   ├── setup_ghidra.sh        #   F2: Ghidra 安裝邏輯
│   └── setup_mcp.sh           #   F3: MCP 插件配置
├── config/                    # 模板文件
│   ├── .env.template          #   MCP 連接模式設定模板
│   └── ghidra.desktop         #   Linux 桌面快捷方式模板
├── bin/                       # 啟動器（install 時自動產生）
├── tests/                     # bats 測試
│   └── *.bats
└── docs/                      # 文件
    ├── SRS.md                 #   本文件
    ├── architecture.md        #   系統架構
    ├── adr/                   #   架構決策記錄
    │   └── ADR-NNN-*.md
    └── specs/                 #   技術規格書
        └── SPEC-NNN-*.md

```

---

## 6. 成功驗證指標 (Definition of Done)

1. 使用者僅需執行 `sudo ./install.sh` 即可完成所有配置。
2. 在終端機輸入 `ghidra` 能成功啟動 GUI 介面。
3. Ghidra 內部的 "File -> Configure -> Plugins" 能看到 MCP 相關組件。
4. AI 助手能成功讀取 Ghidra 反組譯出的虛擬碼 (Decompiled Code)。

