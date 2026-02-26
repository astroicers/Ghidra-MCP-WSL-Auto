# test_helper.bash — bats 測試輔助函式
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Stub log functions (modules depend on these) ---
log_info()  { echo "[INFO]  $1"; }
log_ok()    { echo "[OK]    $1"; }
log_warn()  { echo "[WARN]  $1"; }
log_error() { echo "[ERROR] $1" >&2; }
log_skip()  { echo "[SKIP]  $1"; }
sanitize_log() { cat; }

# --- Test-scoped constants (override production paths) ---
export INSTALL_DIR="/tmp/test-ghidra"
export MCP_DIR="/tmp/test-ghidra-mcp"
export LOG_FILE="/tmp/test-ghidra-install.log"
export GHIDRA_GITHUB_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"
export MCP_REPO_URL="https://github.com/LaurieWired/GhidraMCP.git"
export REQUIRED_JDK_VERSION=21
export MIN_PYTHON_VERSION="3.10"
export MIN_DISK_GB=5

# --- Module loader ---
load_module() {
    local module="$1"
    source "${SCRIPT_DIR}/scripts/${module}.sh"
}

# --- Load install.sh functions without running main ---
load_install_functions() {
    eval "$(awk '/^(sanitize_log|_log|log_info|log_ok|log_warn|log_error|log_skip|print_usage|parse_args|do_uninstall|print_summary)\(/,/^}/' "${SCRIPT_DIR}/install.sh")"
}

# --- Cleanup ---
cleanup_test_env() {
    rm -rf /tmp/test-ghidra /tmp/test-ghidra-mcp /tmp/test-ghidra-install.log 2>/dev/null || true
}
