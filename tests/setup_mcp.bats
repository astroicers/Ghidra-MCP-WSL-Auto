#!/usr/bin/env bats
# tests/setup_mcp.bats — SPEC-003 MCP 插件配置模組測試

load 'test_helper'

setup() {
    cleanup_test_env
    export MCP_DIR="/tmp/test-ghidra-mcp"
    export INSTALL_DIR="/tmp/test-ghidra"
    mkdir -p "$MCP_DIR" "$INSTALL_DIR"
}

teardown() {
    cleanup_test_env
}

# ── Constants ──

@test "MCP_REPO_URL is defined and points to GhidraMCP" {
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

# ── venv ──

@test "setup_mcp_create_venv: skips when venv already exists" {
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

# ── MCP connection mode ──

@test "setup_mcp_configure_connection: non-interactive creates env template with 644 perms" {
    load_module setup_mcp
    export NO_INTERACTIVE=true
    mkdir -p "${MCP_DIR}/GhidraMCP"

    run setup_mcp_configure_connection
    [ "$status" -eq 0 ]

    local env_file="${MCP_DIR}/GhidraMCP/.env"
    [ -f "$env_file" ]

    local perms
    perms=$(stat -c %a "$env_file")
    [ "$perms" = "644" ]

    grep -q "MCP_MODE" "$env_file"
    grep -q "GHIDRA_PLUGIN_PORT" "$env_file"
    grep -q "MCP_SERVER_PORT" "$env_file"
}

# ── Plugin extraction (double-layer ZIP) ──

@test "_extract_ghidramcp_plugin: extracts inner ZIP from release wrapper" {
    load_module setup_mcp
    local work_dir="/tmp/test-extract-plugin"
    local ext_dir="${work_dir}/Extensions"
    mkdir -p "$ext_dir" "${work_dir}/inner/GhidraMCP/lib"

    # 建立模擬的內層 ZIP（含 extension.properties）
    echo "name=GhidraMCP" > "${work_dir}/inner/GhidraMCP/extension.properties"
    echo "manifest" > "${work_dir}/inner/GhidraMCP/Module.manifest"
    echo "jar" > "${work_dir}/inner/GhidraMCP/lib/GhidraMCP.jar"
    (cd "${work_dir}/inner" && zip -q -r "${work_dir}/GhidraMCP-1-4.zip" GhidraMCP/)

    # 建立模擬的外層 ZIP（含 bridge + 內層 ZIP）
    mkdir -p "${work_dir}/outer/GhidraMCP-release-1-4"
    echo "bridge" > "${work_dir}/outer/GhidraMCP-release-1-4/bridge_mcp_ghidra.py"
    cp "${work_dir}/GhidraMCP-1-4.zip" "${work_dir}/outer/GhidraMCP-release-1-4/"
    (cd "${work_dir}/outer" && zip -q -r "${work_dir}/release.zip" GhidraMCP-release-1-4/)

    # 測試解包
    run _extract_ghidramcp_plugin "${work_dir}/release.zip" "$ext_dir"
    [ "$status" -eq 0 ]

    # 驗證 extension.properties 被正確解壓
    [ -f "${ext_dir}/GhidraMCP/extension.properties" ]
    grep -q "name=GhidraMCP" "${ext_dir}/GhidraMCP/extension.properties"
    [ -f "${ext_dir}/GhidraMCP/lib/GhidraMCP.jar" ]

    rm -rf "$work_dir"
}

@test "_extract_ghidramcp_plugin: directly extracts inner-format ZIP" {
    load_module setup_mcp
    local work_dir="/tmp/test-extract-direct"
    local ext_dir="${work_dir}/Extensions"
    mkdir -p "$ext_dir" "${work_dir}/GhidraMCP/lib"

    # 建立模擬的內層 ZIP（直接含 extension.properties）
    echo "name=GhidraMCP" > "${work_dir}/GhidraMCP/extension.properties"
    echo "jar" > "${work_dir}/GhidraMCP/lib/GhidraMCP.jar"
    (cd "$work_dir" && zip -q -r "${work_dir}/inner.zip" GhidraMCP/)

    run _extract_ghidramcp_plugin "${work_dir}/inner.zip" "$ext_dir"
    [ "$status" -eq 0 ]
    [ -f "${ext_dir}/GhidraMCP/extension.properties" ]

    rm -rf "$work_dir"
}

@test "setup_mcp_mount_extension: skips when already installed" {
    load_module setup_mcp
    local ext_dir="${INSTALL_DIR}/Ghidra/Extensions"
    mkdir -p "${ext_dir}/GhidraMCP"
    echo "name=GhidraMCP" > "${ext_dir}/GhidraMCP/extension.properties"

    run setup_mcp_mount_extension
    [ "$status" -eq 0 ]
    [[ "$output" == *"已安裝"* ]] || [[ "$output" == *"SKIP"* ]]
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

    grep -q "ghidraRun" "$launcher"
    grep -q "MCP_DIR" "$launcher"
    grep -q ".venv" "$launcher"
    grep -q "\-\-ghidra-server" "$launcher"
    grep -q "\-\-transport sse" "$launcher"
    grep -q "\-\-mcp-port" "$launcher"
    grep -q "GHIDRA_PLUGIN_PORT" "$launcher"
    grep -q "_patch_ghidra_plugin_port" "$launcher"
    grep -q "_code_browser.tcd" "$launcher"

    rm -f "$launcher"
}

# ── ADR-002: 本地模型模式（Tier A 離線 agentic） ──

@test "_parse_model_size_b: parses standard ollama tags" {
    load_module setup_mcp
    [ "$(_parse_model_size_b 'qwen2.5:32b')" = "32" ]
    [ "$(_parse_model_size_b 'llama3.1:8b')" = "8" ]
    [ "$(_parse_model_size_b 'qwen2.5-coder:14b')" = "14" ]
    [ "$(_parse_model_size_b 'llama3.3:70b')" = "70" ]
}

@test "_parse_model_size_b: takes largest value for MoE naming" {
    load_module setup_mcp
    # qwen3-30b-a3b 的總參數量為 30B，不應誤判為 3B
    [ "$(_parse_model_size_b 'qwen3-30b-a3b')" = "30" ]
}

@test "_parse_model_size_b: returns empty when size is undeterminable" {
    load_module setup_mcp
    [ -z "$(_parse_model_size_b 'mistral-nemo')" ]
    [ -z "$(_parse_model_size_b 'custom-model:latest')" ]
}

@test "_warn_if_model_too_small: warns below threshold (13b)" {
    load_module setup_mcp
    run _warn_if_model_too_small "deepseek-r1:13b"
    [ "$status" -eq 1 ]
    [[ "$output" == *"低於 agentic 建議門檻"* ]]
}

@test "_warn_if_model_too_small: passes at threshold (14b)" {
    load_module setup_mcp
    run _warn_if_model_too_small "qwen2.5-coder:14b"
    [ "$status" -eq 0 ]
    [[ "$output" == *"符合 agentic 門檻"* ]]
}

@test "_warn_if_model_too_small: skips check when size unknown" {
    load_module setup_mcp
    run _warn_if_model_too_small "mistral-nemo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"略過規模檢查"* ]]
}

@test "_setup_mcp_configure_local_mode: writes MCP_MODE=local with defaults" {
    load_module setup_mcp
    mkdir -p "${MCP_DIR}/GhidraMCP"

    printf '\n\n' | _setup_mcp_configure_local_mode >/dev/null 2>&1

    [ -f "$MCP_ENV_FILE" ]
    grep -q "MCP_MODE=local" "$MCP_ENV_FILE"
    grep -q "OLLAMA_MODEL=qwen2.5:32b" "$MCP_ENV_FILE"
    grep -q "OLLAMA_HOST=http://127.0.0.1:11434" "$MCP_ENV_FILE"
    grep -q "MCP_SERVER_PORT=60006" "$MCP_ENV_FILE"
}

@test "_setup_mcp_configure_local_mode: env file is 644 (contains no secrets)" {
    load_module setup_mcp
    mkdir -p "${MCP_DIR}/GhidraMCP"

    printf '\n\n' | _setup_mcp_configure_local_mode >/dev/null 2>&1

    [ "$(stat -c '%a' "$MCP_ENV_FILE")" = "644" ]
    ! grep -qi "api_key" "$MCP_ENV_FILE"
}

@test "_setup_mcp_configure_local_mode: emits correct ollmcp install command" {
    load_module setup_mcp
    mkdir -p "${MCP_DIR}/GhidraMCP"

    # 函式須在當前 shell 執行（已由 load_module 載入），不可用 run bash -c 另開 shell
    local out
    out="$(printf '\n\n' | _setup_mcp_configure_local_mode 2>&1)"

    # 套件與指令名為 ollmcp；mcp-client-for-ollama 僅為 repo 名稱，pipx 安裝會失敗
    [[ "$out" == *"install --upgrade ollmcp"* ]]
    [[ "$out" != *"pipx install mcp-client-for-ollama"* ]]
}

@test "_setup_mcp_configure_local_mode: honours custom model input" {
    load_module setup_mcp
    mkdir -p "${MCP_DIR}/GhidraMCP"

    printf 'llama3.3:70b\n\n' | _setup_mcp_configure_local_mode >/dev/null 2>&1

    grep -q "OLLAMA_MODEL=llama3.3:70b" "$MCP_ENV_FILE"
}

# ── 離線就緒自檢 ──

@test "setup_mcp_check_offline: reports failure when Ollama is unreachable" {
    load_module setup_mcp
    export OLLAMA_HOST="http://127.0.0.1:1"   # 保證無法連線

    run setup_mcp_check_offline
    [ "$status" -eq 1 ]
    [[ "$output" == *"無法連接 Ollama"* ]]
    [[ "$output" == *"ollama serve"* ]]
}

@test "parse_args: accepts --check-offline" {
    load_install_functions
    CHECK_OFFLINE=false
    parse_args --check-offline
    [ "$CHECK_OFFLINE" = "true" ]
}

# ── Launcher 連接模式提示 ──

@test "setup_mcp_create_launcher: emits per-mode next-step hints" {
    load_module setup_mcp
    mkdir -p "${SCRIPT_DIR}/bin"

    run setup_mcp_create_launcher
    [ "$status" -eq 0 ]

    local launcher="${SCRIPT_DIR}/bin/ghidra-mcp"
    grep -q "MCP_MODE" "$launcher"
    grep -q "ollmcp" "$launcher"
    grep -q "claude mcp add" "$launcher"

    rm -f "$launcher"
}

# ── 回歸：既有模式不受影響 ──

@test "_setup_mcp_configure_cli_mode: still writes MCP_MODE=cli" {
    load_module setup_mcp
    mkdir -p "${MCP_DIR}/GhidraMCP"

    run _setup_mcp_configure_cli_mode
    [ "$status" -eq 0 ]
    grep -q "MCP_MODE=cli" "$MCP_ENV_FILE"
}
