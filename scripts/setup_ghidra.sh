#!/usr/bin/env bash
# scripts/setup_ghidra.sh — F2: Ghidra 自動部署模組
# 關聯 SPEC: SPEC-002 | 關聯 ADR: ADR-001

DOWNLOAD_DIR="${DOWNLOAD_DIR:-/tmp/ghidra_download}"

# ── 版本取得 ──
setup_ghidra_fetch_version() {
    if [[ -n "${GHIDRA_VERSION:-}" ]]; then
        log_info "使用指定版本: Ghidra ${GHIDRA_VERSION}"
        return 0
    fi

    log_info "從 GitHub API 取得最新版本..."

    local release_json=""
    local max_retries=3
    local retry_delay=2
    local attempt

    for attempt in $(seq 1 "$max_retries"); do
        local http_code
        http_code=$(curl -sL -o /tmp/ghidra_api_response.json -w "%{http_code}" "$GHIDRA_GITHUB_API" 2>/dev/null) || http_code="000"

        if [[ "$http_code" == "200" ]]; then
            release_json=$(cat /tmp/ghidra_api_response.json)
            rm -f /tmp/ghidra_api_response.json
            break
        elif [[ "$http_code" == "403" || "$http_code" == "429" ]]; then
            log_warn "GitHub API rate limit (HTTP ${http_code})，第 ${attempt}/${max_retries} 次重試..."
            if [[ "$attempt" -lt "$max_retries" ]]; then
                sleep "$retry_delay"
                retry_delay=$(( retry_delay * 2 ))
            fi
        else
            log_warn "GitHub API 回應異常 (HTTP ${http_code})，第 ${attempt}/${max_retries} 次重試..."
            if [[ "$attempt" -lt "$max_retries" ]]; then
                sleep "$retry_delay"
                retry_delay=$(( retry_delay * 2 ))
            fi
        fi
    done

    rm -f /tmp/ghidra_api_response.json

    if [[ -z "$release_json" ]]; then
        log_error "GitHub API 呼叫失敗（已重試 ${max_retries} 次）"
        log_error "請手動指定版本: sudo GHIDRA_VERSION=11.3.1 ./install.sh"
        exit 20
    fi

    GHIDRA_DOWNLOAD_URL=$(echo "$release_json" | jq -r \
        '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' | head -1)

    if [[ -z "$GHIDRA_DOWNLOAD_URL" || "$GHIDRA_DOWNLOAD_URL" == "null" ]]; then
        log_error "無法從 GitHub Release 解析下載連結"
        exit 20
    fi

    # 從 URL 或 tag 提取版本號
    GHIDRA_VERSION=$(echo "$release_json" | jq -r '.tag_name' | sed 's/Ghidra_//; s/_PUBLIC//')

    log_ok "偵測到最新版本: Ghidra ${GHIDRA_VERSION}"
}

# ── 下載 ──
setup_ghidra_download() {
    mkdir -p "$DOWNLOAD_DIR"

    local zip_name
    zip_name=$(basename "$GHIDRA_DOWNLOAD_URL")
    GHIDRA_ZIP_PATH="${DOWNLOAD_DIR}/${zip_name}"

    # 冪等：檢查是否已下載
    if [[ -f "$GHIDRA_ZIP_PATH" ]]; then
        local file_size
        file_size=$(stat -c%s "$GHIDRA_ZIP_PATH" 2>/dev/null || echo 0)
        # ZIP 應 > 100MB
        if [[ "$file_size" -gt 104857600 ]]; then
            log_skip "Ghidra ZIP 已下載 ($(( file_size / 1048576 ))MB)"
            return 0
        fi
        log_warn "既有 ZIP 檔案不完整，重新下載..."
    fi

    log_info "下載 Ghidra (支援斷點續傳)..."
    if wget -c -q --show-progress -O "$GHIDRA_ZIP_PATH" "$GHIDRA_DOWNLOAD_URL"; then
        log_ok "下載完成: ${zip_name}"
    else
        rm -f "$GHIDRA_ZIP_PATH"
        log_error "下載失敗，請檢查網路連線"
        exit 21
    fi
}

# ── 驗證 ──
setup_ghidra_verify() {
    if [[ ! -f "$GHIDRA_ZIP_PATH" ]]; then
        log_error "ZIP 檔案不存在: ${GHIDRA_ZIP_PATH}"
        exit 21
    fi

    local file_size
    file_size=$(stat -c%s "$GHIDRA_ZIP_PATH")
    if [[ "$file_size" -lt 104857600 ]]; then
        log_error "ZIP 檔案可能損壞 (大小: $(( file_size / 1048576 ))MB, 預期: >100MB)"
        rm -f "$GHIDRA_ZIP_PATH"
        exit 21
    fi

    log_ok "ZIP 檔案驗證通過 ($(( file_size / 1048576 ))MB)"
}

# ── 解壓 ──
setup_ghidra_extract() {
    # 冪等：檢查是否已安裝相同版本
    if [[ -f "${INSTALL_DIR}/ghidraRun" ]]; then
        local installed_version
        installed_version=$(readlink -f "$INSTALL_DIR" 2>/dev/null | grep -oP 'ghidra_\K[^/]+' || echo "unknown")
        if [[ "$installed_version" == *"$GHIDRA_VERSION"* ]]; then
            log_skip "Ghidra ${GHIDRA_VERSION} 已安裝於 ${INSTALL_DIR}"
            return 0
        fi
        log_info "偵測到不同版本 (${installed_version})，安裝新版本..."
    fi

    # 檢查 /opt 可用空間
    local opt_avail
    opt_avail=$(df -BG /opt | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ "$opt_avail" -lt 2 ]]; then
        log_error "/opt 空間不足 (可用: ${opt_avail}GB, 需求: ~2GB)"
        exit 22
    fi

    log_info "解壓 Ghidra 至 /opt/..."
    if unzip -q -o "$GHIDRA_ZIP_PATH" -d /opt/; then
        # 找到解壓後的目錄名
        local extracted_dir
        extracted_dir=$(find /opt -maxdepth 1 -name "ghidra_*" -type d | sort -V | tail -1)

        if [[ -z "$extracted_dir" ]]; then
            log_error "解壓完成但找不到 Ghidra 目錄"
            exit 22
        fi

        # 建立符號連結
        ln -sfn "$extracted_dir" "$INSTALL_DIR"
        chmod -R 755 "$extracted_dir"

        log_ok "Ghidra 解壓至 ${extracted_dir}"
        log_ok "符號連結: ${INSTALL_DIR} → ${extracted_dir}"
    else
        log_error "解壓失敗"
        exit 22
    fi
}

# ── JVM 記憶體調校 ──
setup_ghidra_tune_jvm() {
    local vmoptions_file="${INSTALL_DIR}/support/ghidraRun.vmoptions"

    if [[ ! -f "$vmoptions_file" ]]; then
        log_warn "找不到 vmoptions 檔案: ${vmoptions_file}"
        return 0
    fi

    local xmx_mb
    if [[ -n "${GHIDRA_XMX:-}" ]]; then
        xmx_mb="$GHIDRA_XMX"
        log_info "使用指定 JVM 記憶體: ${xmx_mb}MB"
    else
        local total_mem
        total_mem=$(free -m | awk '/Mem:/{print $2}')
        xmx_mb=$(( total_mem / 4 ))
        [[ $xmx_mb -lt 2048 ]] && xmx_mb=2048
        [[ $xmx_mb -gt 16384 ]] && xmx_mb=16384
        log_info "自動計算 JVM 記憶體: ${xmx_mb}MB (系統 RAM: ${total_mem}MB)"
    fi

    # 替換或新增 -Xmx 參數
    if grep -q "^-Xmx" "$vmoptions_file"; then
        sed -i "s/^-Xmx.*/-Xmx${xmx_mb}m/" "$vmoptions_file"
    else
        echo "-Xmx${xmx_mb}m" >> "$vmoptions_file"
    fi

    log_ok "JVM -Xmx 設定為 ${xmx_mb}MB"
}

# ── PATH 設定 ──
setup_ghidra_configure_path() {
    local profile_file="/etc/profile.d/ghidra.sh"

    cat > "$profile_file" <<EOF
# Ghidra-MCP-WSL-Auto 自動產生
export PATH="${INSTALL_DIR}:\$PATH"
export GHIDRA_INSTALL_DIR="${INSTALL_DIR}"
EOF

    chmod 644 "$profile_file"
    log_ok "PATH 設定已寫入 ${profile_file}"
}

# ── 統一入口 ──
setup_ghidra_run_all() {
    log_info "=== F2: Ghidra 自動部署 ==="

    setup_ghidra_fetch_version
    setup_ghidra_download
    setup_ghidra_verify
    setup_ghidra_extract
    setup_ghidra_tune_jvm
    setup_ghidra_configure_path

    log_ok "=== F2: Ghidra 部署完成 ==="
}
