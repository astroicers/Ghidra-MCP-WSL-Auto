#!/usr/bin/env bash
# install.sh — Ghidra-MCP-WSL-Auto 主安裝腳本
# 用途：一鍵部署 Ghidra + GhidraMCP 於 WSL2 Ubuntu/Debian
# 使用方式：sudo ./install.sh [OPTIONS]
set -euo pipefail

# ── 全域常數 ──
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
readonly INSTALL_DIR="${INSTALL_DIR:-/opt/ghidra}"
readonly MCP_DIR="${MCP_DIR:-/opt/ghidra-mcp}"
readonly LOG_FILE="${LOG_FILE:-/var/log/ghidra-mcp-install.log}"
readonly GHIDRA_GITHUB_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
readonly MCP_REPO_URL="https://github.com/LaurieWired/GhidraMCP.git"
readonly REQUIRED_JDK_VERSION=21
readonly MIN_PYTHON_VERSION="3.10"
readonly MIN_DISK_GB=5

# ── CLI 參數預設值 ──
VERBOSE=false
SKIP_APT_UPDATE=false
NO_INTERACTIVE=false
UNINSTALL=false

# ── 日誌函式 ──
sanitize_log() {
    sed 's/sk-[a-zA-Z0-9_-]\{20,\}/sk-***REDACTED***/g; s/anthropic-[a-zA-Z0-9_-]\{20,\}/***REDACTED***/g'
}

_log() {
    local level="$1" msg="$2" color="$3"
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S')"
    printf "${color}[%-5s]\033[0m %s\n" "$level" "$msg"
    { echo "[$ts] [$level] $msg" | sanitize_log >> "$LOG_FILE"; } 2>/dev/null || true
}

log_info()  { _log "INFO"  "$1" "\033[0;34m"; }
log_ok()    { _log "OK"    "$1" "\033[0;32m"; }
log_warn()  { _log "WARN"  "$1" "\033[0;33m"; }
log_error() { _log "ERROR" "$1" "\033[0;31m" >&2; }
log_skip()  { _log "SKIP"  "$1" "\033[0;33m"; }

# ── 錯誤處理 ──
cleanup_on_error() {
    local lineno="$1"
    log_error "安裝在第 ${lineno} 行發生錯誤，請檢查日誌: ${LOG_FILE}"
    # 清理暫存下載
    rm -rf /tmp/ghidra_download/*.part 2>/dev/null || true
}

cleanup_on_interrupt() {
    log_warn "使用者中斷安裝 (CTRL+C)"
    rm -rf /tmp/ghidra_download/*.part 2>/dev/null || true
    exit 130
}

trap 'cleanup_on_error $LINENO' ERR
trap 'cleanup_on_interrupt' INT TERM

# ── CLI 參數解析 ──
print_usage() {
    cat <<'USAGE'
使用方式：sudo ./install.sh [OPTIONS]

選項：
  -h, --help            顯示此說明
  -v, --verbose         啟用詳細輸出
      --skip-update     跳過 apt update/upgrade
      --ghidra-version  指定 Ghidra 版本 (例: 11.3.1)
      --no-interactive  跳過互動式連接模式設定
      --uninstall       移除已安裝的元件

環境變數覆寫：
  INSTALL_DIR           Ghidra 安裝路徑 (預設: /opt/ghidra)
  MCP_DIR               MCP 工作目錄 (預設: /opt/ghidra-mcp)
  GHIDRA_VERSION        指定 Ghidra 版本
  GHIDRA_XMX            JVM 最大記憶體 MB (預設: 自動計算)

範例：
  sudo ./install.sh                           # 標準安裝
  sudo ./install.sh --verbose --skip-update   # 詳細模式，跳過系統更新
  sudo GHIDRA_VERSION=11.3.1 ./install.sh     # 指定版本
USAGE
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_usage
                exit 0
                ;;
            -v|--verbose)
                export VERBOSE=true
                set -x
                shift
                ;;
            --skip-update)
                SKIP_APT_UPDATE=true
                shift
                ;;
            --ghidra-version)
                GHIDRA_VERSION="${2:?'--ghidra-version 需要版本號'}"
                shift 2
                ;;
            --no-interactive)
                NO_INTERACTIVE=true
                shift
                ;;
            --uninstall)
                UNINSTALL=true
                shift
                ;;
            *)
                log_error "未知參數: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# ── 解除安裝 ──
do_uninstall() {
    log_info "開始移除 Ghidra-MCP-WSL-Auto..."
    local removed=0

    if [[ -d "$INSTALL_DIR" ]] || [[ -L "$INSTALL_DIR" ]]; then
        rm -rf "$INSTALL_DIR"
        # 移除版本目錄
        rm -rf /opt/ghidra_* 2>/dev/null || true
        log_ok "已移除 Ghidra: ${INSTALL_DIR}"
        ((removed++)) || true
    fi

    if [[ -d "$MCP_DIR" ]]; then
        rm -rf "$MCP_DIR"
        log_ok "已移除 GhidraMCP: ${MCP_DIR}"
        ((removed++)) || true
    fi

    if [[ -f /etc/profile.d/ghidra.sh ]]; then
        rm -f /etc/profile.d/ghidra.sh
        log_ok "已移除 PATH 設定"
        ((removed++)) || true
    fi

    if [[ $removed -eq 0 ]]; then
        log_warn "無可移除的元件"
        exit 1
    fi

    log_ok "移除完成 (共 ${removed} 項)"
    exit 0
}

# ── 安裝摘要 ──
print_summary() {
    echo ""
    echo "========================================"
    log_ok "Ghidra-MCP-WSL-Auto 安裝完成！"
    echo "========================================"
    echo ""
    echo "  Ghidra 安裝路徑:  ${INSTALL_DIR}"
    echo "  MCP 工作目錄:     ${MCP_DIR}"
    echo "  安裝日誌:         ${LOG_FILE}"
    echo ""
    echo "  啟動方式:"
    echo "    ghidra          # 僅啟動 Ghidra"
    echo "    ghidra-mcp      # 啟動 Ghidra + MCP Bridge"
    echo ""
    echo "  首次使用請重新載入 PATH:"
    echo "    source /etc/profile.d/ghidra.sh"
    echo ""
}

# ── 載入子模組 ──
source "${SCRIPT_DIR}/scripts/check_env.sh"
source "${SCRIPT_DIR}/scripts/setup_ghidra.sh"
source "${SCRIPT_DIR}/scripts/setup_mcp.sh"

# ── 主流程 ──
main() {
    parse_args "$@"

    # 初始化日誌
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null || true
    touch "$LOG_FILE" 2>/dev/null || true

    log_info "開始安裝 Ghidra-MCP-WSL-Auto"

    # 解除安裝模式
    if [[ "$UNINSTALL" == "true" ]]; then
        do_uninstall
    fi

    # 依序執行子模組
    check_env_run_all
    setup_ghidra_run_all
    setup_mcp_run_all

    print_summary
    log_ok "安裝完成！"
}

main "$@"
