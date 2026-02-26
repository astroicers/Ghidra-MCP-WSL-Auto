# Test Hardening & Bug Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace stub/skeleton bats tests with real functional tests that actually verify module behavior, and fix implementation bugs identified during review.

**Architecture:** Tests use bats-core framework with a `test_helper.bash` that loads individual modules in isolation (without triggering `main()`). Each module's exported functions are tested by mocking external commands (apt, wget, git, curl) and verifying outputs, exit codes, and side effects against the SPECs.

**Tech Stack:** Bash 5.x, bats-core, shellcheck, GNU coreutils

---

## Pre-requisites

Install bats-core and shellcheck on the development machine:

```bash
sudo apt-get update -qq && sudo apt-get install -y bats shellcheck
```

---

### Task 1: Fix test_helper.bash — Robust Module Loading

**Files:**
- Modify: `tests/test_helper.bash`

**Problem:** Current `load_common()` uses fragile `sed` + `eval` to extract functions from `install.sh`. This breaks if section headers change. Also, modules call `log_*` functions defined in `install.sh` — tests fail because `log_*` is undefined when loading modules directly.

**Step 1: Rewrite test_helper.bash**

Replace the entire file with a version that:
1. Defines stub `log_*` functions so modules can be sourced without `install.sh`
2. Exports the same global constants that `install.sh` defines (using `/tmp/test-*` paths)
3. Provides `load_module` that sources a script from `scripts/`
4. Provides `load_install_functions` that sources `install.sh` functions without running `main`

```bash
# test_helper.bash — bats test helper
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

# --- Load install.sh functions (parse_args, sanitize_log, etc.) without running main ---
load_install_functions() {
    # Source install.sh but prevent main() from executing
    # by temporarily redefining main
    eval "$(awk '/^(sanitize_log|_log|log_info|log_ok|log_warn|log_error|log_skip|print_usage|parse_args|do_uninstall|print_summary)\(/,/^}/' "${SCRIPT_DIR}/install.sh")"
}

# --- Cleanup ---
cleanup_test_env() {
    rm -rf /tmp/test-ghidra /tmp/test-ghidra-mcp /tmp/test-ghidra-install.log 2>/dev/null || true
}
```

**Step 2: Run syntax check**

Run: `bash -n tests/test_helper.bash`
Expected: No output (success)

**Step 3: Commit**

```bash
git add tests/test_helper.bash
git commit -m "fix(tests): rewrite test_helper with stub log functions and robust module loading"
```

---

### Task 2: Rewrite check_env.bats — Real Function Tests

**Files:**
- Modify: `tests/check_env.bats`

**Problem:** Current tests either just check variable existence or inline `sed` commands instead of calling actual functions. Need to test real `check_env_*` functions.

**Step 1: Rewrite check_env.bats**

```bash
#!/usr/bin/env bats
# tests/check_env.bats — SPEC-001 environment detection tests

load 'test_helper'

setup() {
    cleanup_test_env
}

teardown() {
    cleanup_test_env
}

# ── WSL2 detection ──

@test "check_env_verify_wsl: returns 0 on WSL2" {
    load_module check_env
    if grep -qi "microsoft\|WSL" /proc/version 2>/dev/null; then
        run check_env_verify_wsl
        [ "$status" -eq 0 ]
    else
        skip "Not a WSL2 environment"
    fi
}

@test "check_env_verify_wsl: also detects via WSL_DISTRO_NAME" {
    load_module check_env
    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        run check_env_verify_wsl
        [ "$status" -eq 0 ]
    else
        skip "WSL_DISTRO_NAME not set"
    fi
}

# ── Root check ──

@test "check_env_verify_root: non-root returns exit 11" {
    load_module check_env
    if [[ $EUID -ne 0 ]]; then
        run check_env_verify_root
        [ "$status" -eq 11 ]
    else
        skip "Running as root, cannot test non-root path"
    fi
}

# ── Disk space ──

@test "check_env_check_disk: returns 0 with sufficient space" {
    load_module check_env
    run check_env_check_disk
    [ "$status" -eq 0 ]
    [[ "$output" == *"磁碟空間足夠"* ]]
}

# ── APT packages ──

@test "APT_PACKAGES array contains required packages" {
    load_module check_env
    [ ${#APT_PACKAGES[@]} -ge 10 ]
    [[ " ${APT_PACKAGES[*]} " == *" openjdk-21-jdk "* ]]
    [[ " ${APT_PACKAGES[*]} " == *" python3 "* ]]
    [[ " ${APT_PACKAGES[*]} " == *" python3-venv "* ]]
    [[ " ${APT_PACKAGES[*]} " == *" jq "* ]]
    [[ " ${APT_PACKAGES[*]} " == *" wget "* ]]
    [[ " ${APT_PACKAGES[*]} " == *" git "* ]]
}

# ── System update ──

@test "check_env_system_update: skips when SKIP_APT_UPDATE=true" {
    load_module check_env
    export SKIP_APT_UPDATE=true
    run check_env_system_update
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]]
}

# ── Java verification ──

@test "check_env_verify_java: detects installed JDK" {
    if ! command -v java &>/dev/null; then
        skip "Java not installed"
    fi
    load_module check_env
    run check_env_verify_java
    [ "$status" -eq 0 ]
    [[ "$output" == *"Java"* ]]
}

@test "check_env_verify_java: returns 1 when java missing" {
    load_module check_env
    # Override PATH to hide java
    run env PATH="/usr/bin/nonexistent" bash -c "
        source '${SCRIPT_DIR}/tests/test_helper.bash'
        source '${SCRIPT_DIR}/scripts/check_env.sh'
        check_env_verify_java
    "
    [ "$status" -ne 0 ]
}

# ── Python verification ──

@test "check_env_verify_python: detects Python >= 3.10" {
    if ! command -v python3 &>/dev/null; then
        skip "Python3 not installed"
    fi
    load_module check_env
    run check_env_verify_python
    [ "$status" -eq 0 ]
    [[ "$output" == *"Python"* ]]
}
```

**Step 2: Run tests**

Run: `bats tests/check_env.bats`
Expected: All non-skipped tests PASS

**Step 3: Commit**

```bash
git add tests/check_env.bats
git commit -m "test(check_env): replace stubs with real function assertions"
```

---

### Task 3: Rewrite setup_ghidra.bats — JVM Tuning & Idempotency Tests

**Files:**
- Modify: `tests/setup_ghidra.bats`

**Problem:** Tests check local variables but never call functions. JVM tuning test just computes math locally. Idempotency test creates files but doesn't call the actual function.

**Step 1: Rewrite setup_ghidra.bats**

```bash
#!/usr/bin/env bats
# tests/setup_ghidra.bats — SPEC-002 Ghidra deployment tests

load 'test_helper'

setup() {
    cleanup_test_env
    export INSTALL_DIR="/tmp/test-ghidra"
    mkdir -p "$INSTALL_DIR"
}

teardown() {
    cleanup_test_env
}

# ── Version fetch ──

@test "setup_ghidra_fetch_version: GHIDRA_VERSION env override" {
    load_module setup_ghidra
    export GHIDRA_VERSION="11.3.1"
    run setup_ghidra_fetch_version
    [ "$status" -eq 0 ]
    [[ "$output" == *"11.3.1"* ]]
}

@test "setup_ghidra_fetch_version: GitHub API returns valid URL" {
    command -v curl &>/dev/null || skip "curl not installed"
    command -v jq &>/dev/null || skip "jq not installed"

    local response
    response=$(curl -sL "https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest" 2>/dev/null) || skip "GitHub API unreachable"

    local url
    url=$(echo "$response" | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' 2>/dev/null | head -1)

    [ -n "$url" ]
    [[ "$url" == https://* ]]
    [[ "$url" == *".zip" ]]
}

# ── JVM tuning ──

@test "setup_ghidra_tune_jvm: creates Xmx entry in vmoptions" {
    load_module setup_ghidra
    # Create mock vmoptions file
    mkdir -p "${INSTALL_DIR}/support"
    echo "-Xmx1024m" > "${INSTALL_DIR}/support/ghidraRun.vmoptions"

    run setup_ghidra_tune_jvm
    [ "$status" -eq 0 ]

    # Verify Xmx was updated (should be >= 2048)
    local xmx_line
    xmx_line=$(grep "^-Xmx" "${INSTALL_DIR}/support/ghidraRun.vmoptions")
    [[ "$xmx_line" =~ ^-Xmx[0-9]+m$ ]]

    local xmx_val
    xmx_val=$(echo "$xmx_line" | grep -oP '\d+')
    [ "$xmx_val" -ge 2048 ]
    [ "$xmx_val" -le 16384 ]
}

@test "setup_ghidra_tune_jvm: GHIDRA_XMX env override" {
    load_module setup_ghidra
    mkdir -p "${INSTALL_DIR}/support"
    echo "-Xmx1024m" > "${INSTALL_DIR}/support/ghidraRun.vmoptions"

    export GHIDRA_XMX=8192
    run setup_ghidra_tune_jvm
    [ "$status" -eq 0 ]

    local xmx_line
    xmx_line=$(grep "^-Xmx" "${INSTALL_DIR}/support/ghidraRun.vmoptions")
    [ "$xmx_line" = "-Xmx8192m" ]
}

@test "setup_ghidra_tune_jvm: appends Xmx when missing" {
    load_module setup_ghidra
    mkdir -p "${INSTALL_DIR}/support"
    echo "# empty vmoptions" > "${INSTALL_DIR}/support/ghidraRun.vmoptions"

    run setup_ghidra_tune_jvm
    [ "$status" -eq 0 ]
    grep -q "^-Xmx" "${INSTALL_DIR}/support/ghidraRun.vmoptions"
}

@test "setup_ghidra_tune_jvm: skips when vmoptions file missing" {
    load_module setup_ghidra
    # No support/ directory created
    run setup_ghidra_tune_jvm
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]] || [[ "$output" == *"找不到"* ]]
}

# ── Extract idempotency ──

@test "setup_ghidra_extract: skips when same version installed" {
    load_module setup_ghidra
    export GHIDRA_VERSION="11.3.1"

    # Simulate installed Ghidra with matching version
    local ver_dir="/tmp/test-ghidra_11.3.1_PUBLIC"
    mkdir -p "$ver_dir"
    touch "$ver_dir/ghidraRun"
    ln -sfn "$ver_dir" "$INSTALL_DIR"

    run setup_ghidra_extract
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]] || [[ "$output" == *"已安裝"* ]]

    rm -rf "$ver_dir"
}

# ── PATH config ──

@test "setup_ghidra_configure_path: writes profile.d script" {
    load_module setup_ghidra
    # Cannot write to /etc/profile.d/ without root, so test content generation
    if [[ $EUID -eq 0 ]]; then
        run setup_ghidra_configure_path
        [ "$status" -eq 0 ]
        [ -f "/etc/profile.d/ghidra.sh" ]
        grep -q "GHIDRA_INSTALL_DIR" /etc/profile.d/ghidra.sh
    else
        skip "Requires root to write /etc/profile.d/"
    fi
}
```

**Step 2: Run tests**

Run: `bats tests/setup_ghidra.bats`
Expected: All non-skipped tests PASS

**Step 3: Commit**

```bash
git add tests/setup_ghidra.bats
git commit -m "test(setup_ghidra): add real JVM tuning and idempotency assertions"
```

---

### Task 4: Rewrite setup_mcp.bats — Clone Strategy & Security Tests

**Files:**
- Modify: `tests/setup_mcp.bats`

**Problem:** Tests only check directory existence and variable values — never call actual functions. API key security test creates its own file instead of testing the real function.

**Step 1: Rewrite setup_mcp.bats**

```bash
#!/usr/bin/env bats
# tests/setup_mcp.bats — SPEC-003 MCP plugin integration tests

load 'test_helper'

setup() {
    cleanup_test_env
    export MCP_DIR="/tmp/test-ghidra-mcp"
    export INSTALL_DIR="/tmp/test-ghidra"
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    mkdir -p "$MCP_DIR" "$INSTALL_DIR"
}

teardown() {
    cleanup_test_env
}

# ── Constants ──

@test "MCP_REPO_URL is defined" {
    [ -n "${MCP_REPO_URL:-}" ]
    [[ "$MCP_REPO_URL" == *"GhidraMCP"* ]]
}

# ── Clone strategy ──

@test "setup_mcp_clone_repo: detects existing .git and pulls" {
    load_module setup_mcp
    local mcp_path="${MCP_DIR}/GhidraMCP"
    mkdir -p "${mcp_path}/.git"

    run setup_mcp_clone_repo
    [ "$status" -eq 0 ]
    [[ "$output" == *"已存在"* ]] || [[ "$output" == *"SKIP"* ]]
}

@test "setup_mcp_clone_repo: removes non-git dir and re-clones" {
    load_module setup_mcp
    local mcp_path="${MCP_DIR}/GhidraMCP"
    mkdir -p "${mcp_path}/not-a-git-repo"

    # This will attempt a real git clone, which may fail in CI
    run setup_mcp_clone_repo
    # Either succeeds (clone worked) or fails with exit 30 (network issue)
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 30 ]]
}

# ── venv ──

@test "setup_mcp_create_venv: skips when venv exists" {
    load_module setup_mcp
    local venv_dir="${MCP_DIR}/GhidraMCP/.venv"
    mkdir -p "${venv_dir}/bin"

    run setup_mcp_create_venv
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]] || [[ "$output" == *"已存在"* ]]
}

@test "python3 -m venv is available" {
    run python3 -m venv --help
    [ "$status" -eq 0 ]
}

# ── API Key security ──

@test "setup_mcp_configure_api: non-interactive creates template with 600 perms" {
    load_module setup_mcp
    export NO_INTERACTIVE=true

    run setup_mcp_configure_api
    [ "$status" -eq 0 ]

    local env_file="${MCP_DIR}/GhidraMCP/.env"
    [ -f "$env_file" ]

    local perms
    perms=$(stat -c %a "$env_file")
    [ "$perms" = "600" ]

    # Verify template content
    grep -q "LLM_PROVIDER" "$env_file"
    grep -q "LLM_API_KEY" "$env_file"
    grep -q "MCP_SERVER_PORT" "$env_file"
}

# ── Launcher ──

@test "setup_mcp_create_launcher: generates executable script" {
    load_module setup_mcp
    mkdir -p "${SCRIPT_DIR}/bin"

    run setup_mcp_create_launcher
    [ "$status" -eq 0 ]

    local launcher="${SCRIPT_DIR}/bin/ghidra-mcp"
    [ -f "$launcher" ]
    [ -x "$launcher" ]

    # Verify launcher content
    grep -q "ghidraRun" "$launcher"
    grep -q "MCP_DIR" "$launcher"
    grep -q ".venv" "$launcher"

    # Clean up (don't leave generated file)
    rm -f "$launcher"
}
```

**Step 2: Run tests**

Run: `bats tests/setup_mcp.bats`
Expected: All non-skipped tests PASS

**Step 3: Commit**

```bash
git add tests/setup_mcp.bats
git commit -m "test(setup_mcp): add clone strategy, security, and launcher tests"
```

---

### Task 5: Rewrite install.bats — CLI, Sanitize, and Uninstall Tests

**Files:**
- Modify: `tests/install.bats`

**Problem:** sanitize_log tests use inline `sed` instead of the real `sanitize_log()` function. --help test may fail because `install.sh` sources modules that call `exit` on WSL check.

**Step 1: Rewrite install.bats**

```bash
#!/usr/bin/env bats
# tests/install.bats — SPEC-004 main script tests

load 'test_helper'

setup() {
    cleanup_test_env
}

teardown() {
    cleanup_test_env
}

# ── Syntax validation ──

@test "install.sh: valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/install.sh"
    [ "$status" -eq 0 ]
}

@test "scripts/check_env.sh: valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/scripts/check_env.sh"
    [ "$status" -eq 0 ]
}

@test "scripts/setup_ghidra.sh: valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/scripts/setup_ghidra.sh"
    [ "$status" -eq 0 ]
}

@test "scripts/setup_mcp.sh: valid bash syntax" {
    run bash -n "${SCRIPT_DIR}/scripts/setup_mcp.sh"
    [ "$status" -eq 0 ]
}

# ── CLI arguments ──

@test "install.sh --help: shows usage and exits 0" {
    # Run in a subshell that stubs source to prevent module loading
    run bash -c "
        source() { :; }
        . '${SCRIPT_DIR}/install.sh' --help 2>&1
    " 2>&1 || true

    # Alternative: test print_usage directly
    load_install_functions
    run print_usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"使用方式"* ]]
    [[ "$output" == *"--verbose"* ]]
    [[ "$output" == *"--uninstall"* ]]
}

@test "parse_args: sets VERBOSE=true for -v" {
    load_install_functions
    VERBOSE=false
    parse_args -v 2>/dev/null || true
    [ "$VERBOSE" = "true" ]
}

@test "parse_args: sets SKIP_APT_UPDATE for --skip-update" {
    load_install_functions
    SKIP_APT_UPDATE=false
    parse_args --skip-update
    [ "$SKIP_APT_UPDATE" = "true" ]
}

@test "parse_args: sets NO_INTERACTIVE for --no-interactive" {
    load_install_functions
    NO_INTERACTIVE=false
    parse_args --no-interactive
    [ "$NO_INTERACTIVE" = "true" ]
}

@test "parse_args: sets UNINSTALL for --uninstall" {
    load_install_functions
    UNINSTALL=false
    parse_args --uninstall
    [ "$UNINSTALL" = "true" ]
}

@test "parse_args: sets GHIDRA_VERSION for --ghidra-version" {
    load_install_functions
    parse_args --ghidra-version 11.3.1
    [ "$GHIDRA_VERSION" = "11.3.1" ]
}

# ── Log sanitization ──

@test "sanitize_log: masks OpenAI API Key" {
    load_install_functions
    local result
    result=$(echo "Key: sk-abc123def456ghi789jkl012mno345pqr" | sanitize_log)
    [[ "$result" == *"REDACTED"* ]]
    [[ "$result" != *"abc123"* ]]
}

@test "sanitize_log: masks Anthropic API Key" {
    load_install_functions
    local result
    result=$(echo "Key: anthropic-sk-abc123def456ghi789jkl012" | sanitize_log)
    [[ "$result" == *"REDACTED"* ]]
    [[ "$result" != *"abc123"* ]]
}

@test "sanitize_log: preserves normal text" {
    load_install_functions
    local input="Installing Ghidra 11.3.1"
    local result
    result=$(echo "$input" | sanitize_log)
    [ "$result" = "$input" ]
}

# ── Uninstall ──

@test "do_uninstall: removes INSTALL_DIR and MCP_DIR" {
    load_install_functions
    export INSTALL_DIR="/tmp/test-ghidra"
    export MCP_DIR="/tmp/test-ghidra-mcp"

    mkdir -p "$INSTALL_DIR" "$MCP_DIR"

    # do_uninstall calls exit, so run in subshell
    run bash -c "
        source '${SCRIPT_DIR}/tests/test_helper.bash'
        load_install_functions
        export INSTALL_DIR='/tmp/test-ghidra'
        export MCP_DIR='/tmp/test-ghidra-mcp'
        do_uninstall
    "
    [ "$status" -eq 0 ]
    [ ! -d "/tmp/test-ghidra" ]
    [ ! -d "/tmp/test-ghidra-mcp" ]
}
```

**Step 2: Run tests**

Run: `bats tests/install.bats`
Expected: All non-skipped tests PASS

**Step 3: Commit**

```bash
git add tests/install.bats
git commit -m "test(install): add CLI parsing, sanitize_log, and uninstall tests"
```

---

### Task 6: Fix setup_ghidra.sh — readonly Collision with Test Overrides

**Files:**
- Modify: `scripts/setup_ghidra.sh`

**Problem:** `readonly DOWNLOAD_DIR="/tmp/ghidra_download"` on line 4 causes `readonly` error when tests re-source the module. Also, `GHIDRA_ZIP_PATH` and `GHIDRA_DOWNLOAD_URL` are set as globals without declaration, making tests fragile.

**Step 1: Fix readonly collision**

Change line 4 of `scripts/setup_ghidra.sh`:
```bash
# Before:
readonly DOWNLOAD_DIR="/tmp/ghidra_download"

# After:
DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp/ghidra_download}"
```

**Step 2: Run syntax check and tests**

Run: `bash -n scripts/setup_ghidra.sh && bats tests/setup_ghidra.bats`
Expected: PASS

**Step 3: Commit**

```bash
git add scripts/setup_ghidra.sh
git commit -m "fix(setup_ghidra): remove readonly on DOWNLOAD_DIR for test compatibility"
```

---

### Task 7: Fix setup_mcp.sh — readonly Collision with Test Overrides

**Files:**
- Modify: `scripts/setup_mcp.sh`

**Problem:** Lines 5-8 use `readonly` for `MCP_REPO`, `MCP_PATH`, `MCP_VENV`, `MCP_ENV_FILE`. These crash when tests re-source the module or when `install.sh` constants aren't yet set.

**Step 1: Fix readonly declarations**

Change lines 5-8 of `scripts/setup_mcp.sh`:
```bash
# Before:
readonly MCP_REPO="${MCP_REPO_URL}"
readonly MCP_PATH="${MCP_DIR}/GhidraMCP"
readonly MCP_VENV="${MCP_PATH}/.venv"
readonly MCP_ENV_FILE="${MCP_PATH}/.env"

# After:
MCP_REPO="${MCP_REPO_URL:-https://github.com/LaurieWired/GhidraMCP.git}"
MCP_PATH="${MCP_DIR:-/opt/ghidra-mcp}/GhidraMCP"
MCP_VENV="${MCP_PATH}/.venv"
MCP_ENV_FILE="${MCP_PATH}/.env"
```

**Step 2: Run syntax check and tests**

Run: `bash -n scripts/setup_mcp.sh && bats tests/setup_mcp.bats`
Expected: PASS

**Step 3: Commit**

```bash
git add scripts/setup_mcp.sh
git commit -m "fix(setup_mcp): remove readonly for test compatibility and add defaults"
```

---

### Task 8: Run Full Test Suite & shellcheck

**Files:**
- No modifications (verification only)

**Step 1: Run full test suite**

Run: `bats tests/ -r`
Expected: All tests PASS (some may skip based on environment)

**Step 2: Run shellcheck**

Run: `make lint`
Expected: No errors (warnings acceptable)

**Step 3: Fix any issues found**

If shellcheck or bats report errors, fix them in the relevant files.

**Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: address shellcheck and test runner findings"
```

---

### Task 9: Update Architecture Tech Debt & CHANGELOG

**Files:**
- Modify: `docs/architecture.md` (tech debt section)
- Modify: `CHANGELOG.md`

**Step 1: Update architecture.md tech debt**

Change the tech debt section — mark "bats-core test framework setup" as done:
```markdown
- [x] bats-core 測試框架已建立，包含真實函式驗證（非骨架測試）
- [ ] GitHub API 未認證限制 60 req/hr，未實作 rate limit 重試
- [ ] 不支援 proxy 環境下的安裝
- [ ] 不支援 WSL1（缺少完整 Linux kernel）
- [ ] GhidraMCP 插件需從 GitHub Release 取得預編譯版本或本機 Gradle 編譯，兩條路徑尚未完整驗證
```

**Step 2: Update CHANGELOG.md**

Add under `[Unreleased]`:
```markdown
### Changed
- tests/: 重寫所有 bats 測試，從骨架升級為真實函式驗證
- tests/test_helper.bash: 加入 stub log 函式與健壯的模組載入器

### Fixed
- scripts/setup_ghidra.sh: 移除 DOWNLOAD_DIR readonly 避免測試衝突
- scripts/setup_mcp.sh: 移除模組常數 readonly 並加入預設值
```

**Step 3: Commit**

```bash
git add docs/architecture.md CHANGELOG.md
git commit -m "docs: update tech debt status and changelog for test hardening"
```

---

## Summary

| Task | Component | Type |
|------|-----------|------|
| 1 | test_helper.bash | Fix (test infra) |
| 2 | check_env.bats | Rewrite (tests) |
| 3 | setup_ghidra.bats | Rewrite (tests) |
| 4 | setup_mcp.bats | Rewrite (tests) |
| 5 | install.bats | Rewrite (tests) |
| 6 | setup_ghidra.sh | Bug fix (readonly) |
| 7 | setup_mcp.sh | Bug fix (readonly) |
| 8 | Full test suite + shellcheck | Verification |
| 9 | architecture.md + CHANGELOG | Documentation |

Total: 9 tasks, ~30 steps
