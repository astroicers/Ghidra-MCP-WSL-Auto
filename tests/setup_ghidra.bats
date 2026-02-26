#!/usr/bin/env bats
# tests/setup_ghidra.bats — SPEC-002 Ghidra 部署模組測試

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
    mkdir -p "${INSTALL_DIR}/support"
    echo "-Xmx1024m" > "${INSTALL_DIR}/support/ghidraRun.vmoptions"

    run setup_ghidra_tune_jvm
    [ "$status" -eq 0 ]

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

@test "setup_ghidra_tune_jvm: warns when vmoptions file missing" {
    load_module setup_ghidra
    run setup_ghidra_tune_jvm
    [ "$status" -eq 0 ]
    [[ "$output" == *"WARN"* ]] || [[ "$output" == *"找不到"* ]]
}

# ── Extract idempotency ──

@test "setup_ghidra_extract: skips when same version installed" {
    load_module setup_ghidra
    export GHIDRA_VERSION="11.3.1"

    local ver_dir="/tmp/test-ghidra_11.3.1_PUBLIC"
    mkdir -p "$ver_dir"
    touch "$ver_dir/ghidraRun"
    # Remove directory first so ln -sfn replaces it (not creates inside it)
    rm -rf "$INSTALL_DIR"
    ln -sfn "$ver_dir" "$INSTALL_DIR"

    run setup_ghidra_extract
    [ "$status" -eq 0 ]
    [[ "$output" == *"SKIP"* ]] || [[ "$output" == *"已安裝"* ]]

    rm -rf "$ver_dir"
}

# ── PATH config ──

@test "setup_ghidra_configure_path: requires root" {
    load_module setup_ghidra
    if [[ $EUID -eq 0 ]]; then
        run setup_ghidra_configure_path
        [ "$status" -eq 0 ]
        [ -f "/etc/profile.d/ghidra.sh" ]
        grep -q "GHIDRA_INSTALL_DIR" /etc/profile.d/ghidra.sh
    else
        skip "Requires root to write /etc/profile.d/"
    fi
}
