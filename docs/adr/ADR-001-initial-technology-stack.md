# [ADR-001]: 初始技術棧選型

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-02-26 |
| **決策者** | 專案負責人 |

---

## 背景（Context）

> 本專案需要在 WSL2 (Ubuntu/Debian) 環境下，一鍵自動部署 Ghidra 逆向工程平台與 GhidraMCP 插件。
> 需要決定：自動化語言、安裝路徑策略、Python 環境隔離方式、版本管理策略、以及 API Key 的安全儲存方式。
> 主要約束條件包括：目標環境為 WSL2 Ubuntu、零額外預裝依賴、需支援冪等性安裝、API Key 不得明文出現在日誌中。

---

## 評估選項（Options Considered）

### 選項 A：Bash 腳本 + 模組化架構

- **技術棧**：
  - 自動化語言：Bash 5.x（WSL Ubuntu 原生 Shell）
  - 套件管理：apt（系統層）、pip + venv（Python 層）
  - JSON 解析：jq（解析 GitHub API 回應）
  - 測試框架：bats-core + shellcheck
  - Java Runtime：OpenJDK 21（Ghidra 11.x 必備）
  - Python：3.10+（GhidraMCP bridge 需求）
- **優點**：
  - 零額外安裝：WSL Ubuntu 原生支援 Bash，使用者無需預裝任何工具
  - 透明度高：使用者可直接 `cat` / `less` 檢視腳本內容
  - 與系統管理操作天然契合（apt install、chmod、ln -s 等）
  - 偵錯方便：`bash -x` 即可追蹤執行流程
- **缺點**：
  - 缺乏原生結構化資料處理（需搭配 jq）
  - 錯誤處理需手動 `set -euo pipefail` 和 `trap` 機制
  - 可測試性相對較低
  - 跨發行版可攜性需注意（apt vs dnf）
- **風險**：
  - Bash 版本差異（4.x vs 5.x）可能影響語法相容性
  - 複雜邏輯（如 JSON 解析 GitHub API）需依賴外部工具 jq

### 選項 B：Ansible Playbook

- **優點**：
  - 聲明式語法、冪等性內建、社群龐大
  - 豐富的內建模組（apt、pip、file、template）
- **缺點**：
  - 需先安裝 Ansible 本身（Python + pip），產生循環依賴（Python 是安裝目標之一）
  - 對單機部署場景過於沉重
  - 使用者學習門檻高，不適合「一鍵執行」的易用性目標
- **風險**：
  - Ansible 版本升級可能引入不相容變更
  - WSL2 環境下的 Ansible 穩定性缺乏充分驗證

### 選項 C：Docker 容器化部署

- **優點**：
  - 隔離性極佳、可重複建置
  - 環境一致性保證
- **缺點**：
  - Ghidra 需要 X11 GUI，Docker 內執行 GUI 需額外設定 X11 socket forwarding
  - 需要在 WSL2 中安裝 Docker Desktop 或 Docker Engine
  - 與「WSL 原生體驗」的專案目標衝突
- **風險**：
  - Docker + WSL2 + X11 的組合穩定性不佳
  - 容器內的 GPU 加速支援有限

### 選項 D：Python 腳本

- **優點**：
  - 跨平台能力強、豐富的標準庫
  - 較佳的可測試性（unittest / pytest）
- **缺點**：
  - 系統管理任務仍需大量 `subprocess` 呼叫，相比 Bash 無顯著優勢
  - 產生循環依賴：Python 本身是安裝目標之一
- **風險**：
  - 不同 Python 版本間的相容性問題
  - `subprocess` 呼叫的錯誤處理複雜度

---

## 決策（Decision）

> 我們選擇 **選項 A：Bash 腳本 + 模組化架構**，因為：
>
> 1. **零依賴部署**：WSL Ubuntu 原生支援 Bash，使用者僅需 `sudo ./install.sh` 即可開始，完全符合 SRS 的「一鍵式」目標
> 2. **避免循環依賴**：Python 和 Java 都是安裝目標，不適合作為安裝工具本身
> 3. **天然契合**：專案操作（apt、wget、chmod、ln）本質上就是 Shell 命令，Bash 是最自然的選擇
> 4. **透明度與可審計性**：安全研究人員（目標使用者）偏好可直接閱讀的腳本

**技術棧總覽：**

| 層級 | 技術 | 版本 | 用途 |
|------|------|------|------|
| 自動化語言 | Bash | 5.x+ | 安裝腳本主體 |
| Java Runtime | OpenJDK | 21 | Ghidra 執行環境 |
| Python Runtime | Python | 3.10+ | GhidraMCP bridge |
| Python 隔離 | venv | (內建) | MCP 依賴隔離 |
| JSON 解析 | jq | 1.6+ | GitHub API 回應解析 |
| 版本取得 | GitHub REST API | v3 | 動態抓取 Ghidra latest release |
| 靜態分析 | shellcheck | 0.8+ | Bash 腳本 lint |
| 測試框架 | bats-core | 1.0+ | Bash 函式測試 |
| GUI 支援 | X11 libs | - | libxrender1, libxtst6, libxi6 |

---

## 後果（Consequences）

**正面影響：**
- 使用者零預裝、零學習門檻
- 腳本透明可審計，適合安全研究人員的信任模型
- 模組化設計（install.sh + scripts/*.sh）提供良好的可維護性
- `bash -x` 偵錯模式降低維護成本

**負面影響 / 技術債：**
- Bash 缺乏原生單元測試支援，需引入 bats-core（`tech-debt: test-framework-setup`）
- 錯誤處理需手動管理 `set -euo pipefail` + `trap`，易遺漏
- 限定維護者需具備 Shell 腳本能力
- 僅支援 apt 系統（Ubuntu/Debian），不支援 dnf/yum（Fedora/RHEL）

**後續追蹤：**
- [ ] 建立 bats-core 測試骨架（tests/ 目錄）
- [ ] 確認 shellcheck 在 CI 中的整合方式
- [ ] 驗證 Bash 4.x 相容性（部分舊版 WSL 環境）

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：docs/SRS.md §3（核心功能需求）、docs/SRS.md §4（非功能需求）
