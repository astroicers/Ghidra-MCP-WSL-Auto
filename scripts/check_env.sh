#!/usr/bin/env bash
# scripts/check_env.sh — F1: 環境檢測與依賴安裝模組
# 關聯 SPEC: SPEC-001 | 關聯 ADR: ADR-001

# ── 依賴套件清單 ──
APT_PACKAGES=(
    openjdk-21-jdk
    python3
    python3-venv
    python3-pip
    wget
    unzip
    git
    curl
    jq
    libxrender1
    libxtst6
    libxi6
)

# ── WSL2 驗證 ──
check_env_verify_wsl() {
    if grep -qi "microsoft\|WSL" /proc/version 2>/dev/null; then
        log_ok "WSL2 環境驗證通過"
        return 0
    fi

    if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
        log_ok "WSL2 環境驗證通過 (${WSL_DISTRO_NAME})"
        return 0
    fi

    log_error "本腳本僅支援 WSL2 環境"
    log_error "請在 Windows WSL2 中執行此腳本"
    exit 10
}

# ── Root 權限驗證 ──
check_env_verify_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "請使用 sudo 執行此腳本: sudo ./install.sh"
        exit 11
    fi
    log_ok "Root 權限確認"
}

# ── 磁碟空間檢查 ──
check_env_check_disk() {
    local available_gb
    available_gb=$(df -BG / | awk 'NR==2 {print $4}' | tr -d 'G')

    if [[ "$available_gb" -ge "$MIN_DISK_GB" ]]; then
        log_ok "磁碟空間足夠 (可用: ${available_gb}GB, 需求: ${MIN_DISK_GB}GB)"
        return 0
    fi

    log_error "磁碟空間不足 (可用: ${available_gb}GB, 需求: ${MIN_DISK_GB}GB)"
    exit 12
}

# ── 系統更新 ──
check_env_system_update() {
    if [[ "${SKIP_APT_UPDATE:-false}" == "true" ]]; then
        log_skip "系統更新 (--skip-update)"
        return 0
    fi

    log_info "執行系統更新..."
    if apt-get update -qq; then
        log_ok "apt update 完成"
    else
        log_warn "apt update 失敗，重試一次..."
        if apt-get update -qq; then
            log_ok "apt update 完成 (第二次嘗試)"
        else
            log_error "apt update 失敗，請檢查網路連線"
            return 1
        fi
    fi

    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq
    log_ok "apt upgrade 完成"
}

# ── 依賴安裝 ──
check_env_install_deps() {
    local packages_to_install=()

    for pkg in "${APT_PACKAGES[@]}"; do
        if dpkg -s "$pkg" &>/dev/null; then
            log_skip "${pkg} 已安裝"
        else
            packages_to_install+=("$pkg")
        fi
    done

    if [[ ${#packages_to_install[@]} -eq 0 ]]; then
        log_ok "所有依賴已滿足"
        return 0
    fi

    log_info "安裝 ${#packages_to_install[@]} 個套件: ${packages_to_install[*]}"
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${packages_to_install[@]}"; then
        log_ok "依賴安裝完成"
    else
        log_error "依賴安裝失敗: ${packages_to_install[*]}"
        return 1
    fi
}

# ── Java 驗證 ──
check_env_verify_java() {
    if ! command -v java &>/dev/null; then
        log_error "Java 未安裝"
        return 1
    fi

    local java_version
    java_version=$(java -version 2>&1 | head -1 | awk -F'"' '{print $2}' | cut -d. -f1)

    if [[ "$java_version" -ge "$REQUIRED_JDK_VERSION" ]]; then
        log_ok "Java ${java_version} 已安裝 (需求: ${REQUIRED_JDK_VERSION}+)"
        return 0
    fi

    log_error "Java 版本不足: ${java_version} (需求: ${REQUIRED_JDK_VERSION}+)"
    return 1
}

# ── Python 驗證 ──
check_env_verify_python() {
    if ! command -v python3 &>/dev/null; then
        log_error "Python3 未安裝"
        return 1
    fi

    local py_version
    py_version=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')

    # 比較版本 (major.minor)
    local py_major py_minor min_major min_minor
    py_major=$(echo "$py_version" | cut -d. -f1)
    py_minor=$(echo "$py_version" | cut -d. -f2)
    min_major=$(echo "$MIN_PYTHON_VERSION" | cut -d. -f1)
    min_minor=$(echo "$MIN_PYTHON_VERSION" | cut -d. -f2)

    if [[ "$py_major" -gt "$min_major" ]] || \
       [[ "$py_major" -eq "$min_major" && "$py_minor" -ge "$min_minor" ]]; then
        log_ok "Python ${py_version} 已安裝 (需求: ${MIN_PYTHON_VERSION}+)"
        return 0
    fi

    log_error "Python 版本不足: ${py_version} (需求: ${MIN_PYTHON_VERSION}+)"
    return 1
}

# ── 統一入口 ──
check_env_run_all() {
    log_info "=== F1: 環境檢測與依賴安裝 ==="

    check_env_verify_wsl
    check_env_verify_root
    check_env_check_disk
    check_env_system_update
    check_env_install_deps
    check_env_verify_java
    check_env_verify_python

    log_ok "=== F1: 環境檢測完成 ==="
}
