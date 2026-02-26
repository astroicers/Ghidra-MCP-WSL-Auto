#!/usr/bin/env bats
# tests/install.bats — SPEC-004 主腳本測試

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

@test "print_usage: shows usage text" {
    load_install_functions
    run print_usage
    [ "$status" -eq 0 ]
    [[ "$output" == *"使用方式"* ]]
    [[ "$output" == *"--verbose"* ]]
    [[ "$output" == *"--uninstall"* ]]
}

@test "parse_args: --skip-update sets SKIP_APT_UPDATE" {
    load_install_functions
    SKIP_APT_UPDATE=false
    parse_args --skip-update
    [ "$SKIP_APT_UPDATE" = "true" ]
}

@test "parse_args: --no-interactive sets NO_INTERACTIVE" {
    load_install_functions
    NO_INTERACTIVE=false
    parse_args --no-interactive
    [ "$NO_INTERACTIVE" = "true" ]
}

@test "parse_args: --uninstall sets UNINSTALL" {
    load_install_functions
    UNINSTALL=false
    parse_args --uninstall
    [ "$UNINSTALL" = "true" ]
}

@test "parse_args: --ghidra-version sets GHIDRA_VERSION" {
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
    export INSTALL_DIR="/tmp/test-ghidra"
    export MCP_DIR="/tmp/test-ghidra-mcp"
    mkdir -p "$INSTALL_DIR" "$MCP_DIR"

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
