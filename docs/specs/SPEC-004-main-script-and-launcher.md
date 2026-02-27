# SPEC-004：主腳本與啟動器 (install.sh + bin/ghidra-mcp)

> 對應 SRS F4：啟動與整合優化，及整體流程編排

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-004 |
| **關聯 ADR** | ADR-001（初始技術棧選型） |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 目標（Goal）

> 提供安裝流程的統一進入點 (install.sh)，負責 CLI 參數解析、日誌系統初始化、依序呼叫子模組，並在安裝完成後建立一鍵啟動器 (bin/ghidra-mcp)。

---

## 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| --help / -h | flag | CLI | 顯示說明後退出 |
| --verbose / -v | flag | CLI | 啟用詳細輸出 |
| --skip-update | flag | CLI | 跳過 apt update/upgrade |
| --ghidra-version \<ver\> | string | CLI | 指定 Ghidra 版本 |
| --no-interactive | flag | CLI | 跳過互動式連接模式設定 |
| --uninstall | flag | CLI | 移除已安裝的元件 |

---

## 輸出規格（Expected Output）

**成功情境：**
- 所有子模組依序成功執行
- 安裝摘要輸出至 stdout
- 完整日誌寫入 /var/log/ghidra-mcp-install.log
- bin/ghidra-mcp 啟動器已可執行

**失敗情境：**

| 錯誤類型 | Exit Code | 處理方式 |
|----------|-----------|----------|
| 非 root 執行 | 11 | 提示使用 sudo |
| 子模組失敗 | 子模組回傳碼 | 輸出失敗步驟，中斷安裝 |
| --uninstall 時無安裝紀錄 | 1 | 提示無可移除元件 |

---

## 模組介面設計

### install.sh 結構

```bash
#!/usr/bin/env bash
set -euo pipefail

# ── 全域常數 ──
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="${INSTALL_DIR:-/opt/ghidra}"
readonly MCP_DIR="${MCP_DIR:-/opt/ghidra-mcp}"
readonly LOG_FILE="/var/log/ghidra-mcp-install.log"
readonly GHIDRA_GITHUB_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
readonly MCP_REPO_URL="https://github.com/LaurieWired/GhidraMCP.git"

# ── 日誌函式 ──
log_info()  { _log "INFO"  "$1" "\033[0;34m"; }
log_ok()    { _log "OK"    "$1" "\033[0;32m"; }
log_warn()  { _log "WARN"  "$1" "\033[0;33m"; }
log_error() { _log "ERROR" "$1" "\033[0;31m" >&2; }
log_skip()  { _log "SKIP"  "$1" "\033[0;33m"; }

_log() {
    local level="$1" msg="$2" color="$3"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "${color}[%-5s]\033[0m %s\n" "$level" "$msg"
    echo "[$ts] [$level] $msg" | sanitize_log >> "$LOG_FILE"
}

sanitize_log() {
    sed 's/sk-[a-zA-Z0-9_-]\{20,\}/sk-***REDACTED***/g; s/anthropic-[a-zA-Z0-9_-]\{20,\}/***REDACTED***/g'
}

# ── CLI 解析 ──
parse_args() { ... }

# ── 錯誤處理 ──
trap 'cleanup_on_error $LINENO' ERR
trap 'cleanup_on_interrupt' INT TERM

# ── 載入子模組 ──
source "${SCRIPT_DIR}/scripts/check_env.sh"
source "${SCRIPT_DIR}/scripts/setup_ghidra.sh"
source "${SCRIPT_DIR}/scripts/setup_mcp.sh"

# ── 主流程 ──
main() {
    parse_args "$@"
    log_info "開始安裝 Ghidra-MCP-WSL-Auto"

    check_env_run_all
    setup_ghidra_run_all
    setup_mcp_run_all

    print_summary
    log_ok "安裝完成！"
}

main "$@"
```

### bin/ghidra-mcp 啟動器

```bash
#!/usr/bin/env bash
set -euo pipefail

# 載入環境
ENV_FILE="/opt/ghidra-mcp/GhidraMCP/.env"
VENV_DIR="/opt/ghidra-mcp/GhidraMCP/.venv"

[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
source "${VENV_DIR}/bin/activate"

# Port 設定
MCP_PORT="${MCP_SERVER_PORT:-60006}"
GHIDRA_PORT="${GHIDRA_PLUGIN_PORT:-60005}"

# 自動 patch Ghidra 插件 port（透過 Python XML patch tool config）
_patch_ghidra_plugin_port  # 修改 _code_browser.tcd

# 啟動 MCP Bridge (背景，帶完整參數)
python3 /opt/ghidra-mcp/GhidraMCP/bridge_mcp_ghidra.py \
    --ghidra-server "http://127.0.0.1:${GHIDRA_PORT}/" \
    --transport sse \
    --mcp-host 127.0.0.1 \
    --mcp-port "${MCP_PORT}" &
MCP_PID=$!

# 等待 MCP Bridge 就緒 (最多 30 秒)
for i in {1..30}; do
    if curl -s "http://127.0.0.1:${MCP_PORT}/" >/dev/null 2>&1; then
        echo "[OK] MCP Bridge 已就緒"
        break
    fi
    sleep 1
done

# 啟動 Ghidra (背景)
/opt/ghidra/ghidraRun "$@" &
GHIDRA_PID=$!

# 健康檢查：等待 Ghidra 插件 HTTP server 就緒 (最多 60 秒)
for j in {1..60}; do
    if curl -s "http://127.0.0.1:${GHIDRA_PORT}/" >/dev/null 2>&1; then
        echo "[OK] Ghidra 插件 HTTP server 已就緒"
        break
    fi
    sleep 1
done

# 等待 Ghidra 結束
wait "$GHIDRA_PID" 2>/dev/null || true

# 清理
kill "$MCP_PID" 2>/dev/null || true
```

### 日誌格式

```
[2026-02-26 14:30:01] [INFO]  開始安裝 Ghidra-MCP-WSL-Auto
[2026-02-26 14:30:02] [OK]    WSL2 環境驗證通過
[2026-02-26 14:30:03] [SKIP]  openjdk-21-jdk 已安裝
[2026-02-26 14:31:20] [OK]    Ghidra 11.3.1 解壓至 /opt/ghidra_11.3.1
[2026-02-26 14:32:31] [OK]    API Key 已設定 (sk-***REDACTED***)
```

---

## 邊界條件（Edge Cases）

- Case 1：非 root 使用者直接執行 → exit 11，提示 `sudo ./install.sh`
- Case 2：--uninstall 模式 → 移除 /opt/ghidra、/opt/ghidra-mcp、/etc/profile.d/ghidra.sh
- Case 3：部分模組失敗 → 輸出已完成步驟，提示使用者修復後重跑（冪等性保證安全）
- Case 4：CTRL+C 中斷 → trap 清理暫存檔（/tmp/ghidra_download/）
- Case 5：日誌檔不可寫（權限問題）→ 降級為 stdout-only 模式

---

## 驗收標準（Done When）

- [ ] `bash -n install.sh` 語法正確
- [ ] `make test-filter FILTER=install` 全數通過
- [ ] `make lint` 無 shellcheck error
- [ ] `sudo ./install.sh --help` 正確顯示說明
- [ ] 日誌中無明文 API Key（sanitize_log 驗證）
- [ ] bin/ghidra-mcp 可正確啟動 MCP Bridge + Ghidra

---

## 禁止事項（Out of Scope）

- 不要在 install.sh 中實作具體安裝邏輯（委派給子模組）
- 不要硬編碼路徑（使用全域常數 + 環境變數覆寫）

---

## 參考資料（References）

- 相關 ADR：ADR-001
- SRS：§3 F4 啟動與整合優化
- SRS：§4 非功能需求（日誌、安全性）
- SRS：§5 專案結構建議
