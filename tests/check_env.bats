#!/usr/bin/env bats
# tests/check_env.bats — SPEC-001 環境檢測模組測試

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
        skip "Running as root"
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
