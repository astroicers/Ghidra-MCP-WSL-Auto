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

    rm -f "$launcher"
}
