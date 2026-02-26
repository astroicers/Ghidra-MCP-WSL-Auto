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

# ── API Key security ──

@test "setup_mcp_configure_api: non-interactive creates template with 600 perms" {
    load_module setup_mcp
    export NO_INTERACTIVE=true
    mkdir -p "${MCP_DIR}/GhidraMCP"

    run setup_mcp_configure_api
    [ "$status" -eq 0 ]

    local env_file="${MCP_DIR}/GhidraMCP/.env"
    [ -f "$env_file" ]

    local perms
    perms=$(stat -c %a "$env_file")
    [ "$perms" = "600" ]

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

    grep -q "ghidraRun" "$launcher"
    grep -q "MCP_DIR" "$launcher"
    grep -q ".venv" "$launcher"

    rm -f "$launcher"
}
