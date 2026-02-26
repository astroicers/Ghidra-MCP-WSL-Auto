#!/usr/bin/env bash
# scripts/setup_mcp.sh — F3: GhidraMCP 插件整合模組
# 關聯 SPEC: SPEC-003 | 關聯 ADR: ADR-001

MCP_REPO="${MCP_REPO_URL:-https://github.com/LaurieWired/GhidraMCP.git}"
MCP_PATH="${MCP_DIR:-/opt/ghidra-mcp}/GhidraMCP"
MCP_VENV="${MCP_PATH}/.venv"
MCP_ENV_FILE="${MCP_PATH}/.env"

# ── Clone 儲存庫 ──
setup_mcp_clone_repo() {
    if [[ -d "${MCP_PATH}/.git" ]]; then
        log_skip "GhidraMCP 已存在，更新中..."
        git -C "$MCP_PATH" pull --ff-only 2>/dev/null || {
            log_warn "git pull 失敗，使用現有版本"
        }
        return 0
    fi

    if [[ -d "$MCP_PATH" ]]; then
        log_warn "目錄存在但非有效 git repo，清理重建..."
        rm -rf "$MCP_PATH"
    fi

    mkdir -p "$MCP_DIR"
    log_info "Clone GhidraMCP..."
    if git clone "$MCP_REPO" "$MCP_PATH"; then
        log_ok "GhidraMCP clone 完成"
    else
        log_error "git clone 失敗，請檢查網路連線"
        exit 30
    fi
}

# ── 建立 venv ──
setup_mcp_create_venv() {
    if [[ -d "${MCP_VENV}/bin" ]]; then
        log_skip "Python venv 已存在"
        return 0
    fi

    log_info "建立 Python venv..."
    if python3 -m venv "$MCP_VENV"; then
        log_ok "Python venv 建立完成"
    else
        log_error "venv 建立失敗，請確認 python3-venv 已安裝"
        exit 31
    fi
}

# ── 安裝 Python 依賴 ──
setup_mcp_install_deps() {
    log_info "安裝 Python 依賴..."

    # 啟用 venv
    # shellcheck source=/dev/null
    source "${MCP_VENV}/bin/activate"

    pip install --upgrade pip -q

    if [[ -f "${MCP_PATH}/requirements.txt" ]]; then
        if pip install -r "${MCP_PATH}/requirements.txt" -q; then
            log_ok "Python 依賴安裝完成"
        else
            log_error "pip install 失敗"
            deactivate 2>/dev/null || true
            exit 32
        fi
    else
        log_warn "未找到 requirements.txt，嘗試安裝 mcp SDK..."
        pip install mcp -q || log_warn "mcp SDK 安裝失敗，可能需手動處理"
    fi

    deactivate 2>/dev/null || true
}

# ── 掛載插件 ──
setup_mcp_mount_extension() {
    # 動態偵測 Ghidra Extensions 路徑
    local ext_dir
    ext_dir=$(find "$INSTALL_DIR" -path "*/Ghidra/Extensions" -type d 2>/dev/null | head -1)

    if [[ -z "$ext_dir" ]]; then
        # Fallback: 嘗試常見路徑
        ext_dir="${INSTALL_DIR}/Ghidra/Extensions"
        mkdir -p "$ext_dir"
    fi

    # 尋找預編譯的插件 ZIP
    local extension_zip
    extension_zip=$(find "$MCP_PATH" -name "ghidra_*.zip" -o -name "GhidraMCP*.zip" 2>/dev/null | head -1)

    if [[ -n "$extension_zip" ]]; then
        ln -sf "$extension_zip" "${ext_dir}/"
        log_ok "插件已掛載: $(basename "$extension_zip") → ${ext_dir}"
    else
        # 嘗試從 GitHub Release 下載
        log_warn "未找到預編譯插件，嘗試從 GitHub Release 下載..."
        local mcp_release_url
        mcp_release_url=$(curl -sL "https://api.github.com/repos/LaurieWired/GhidraMCP/releases/latest" 2>/dev/null \
            | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' 2>/dev/null | head -1)

        if [[ -n "$mcp_release_url" && "$mcp_release_url" != "null" ]]; then
            local zip_name
            zip_name=$(basename "$mcp_release_url")
            if wget -q -O "${ext_dir}/${zip_name}" "$mcp_release_url"; then
                log_ok "插件已下載並掛載: ${zip_name}"
            else
                log_warn "插件下載失敗，請手動安裝"
                log_warn "下載位址: ${mcp_release_url}"
                return 0
            fi
        else
            log_warn "無法找到預編譯插件，請參考 GhidraMCP README 手動編譯"
            return 0
        fi
    fi
}

# ── API Key 設定 ──
setup_mcp_configure_api() {
    if [[ "${NO_INTERACTIVE:-false}" == "true" ]]; then
        log_skip "互動模式已停用 (--no-interactive)"
        log_info "請手動編輯 API Key: ${MCP_ENV_FILE}"
        # 建立模板
        if [[ ! -f "$MCP_ENV_FILE" ]]; then
            cp "${SCRIPT_DIR}/config/.env.template" "$MCP_ENV_FILE" 2>/dev/null || {
                cat > "$MCP_ENV_FILE" <<'ENVEOF'
# Ghidra-MCP-WSL-Auto 自動產生
# 請勿將此檔案加入版本控制
LLM_PROVIDER=openai
LLM_API_KEY=
MCP_SERVER_PORT=8080
ENVEOF
            }
            chmod 600 "$MCP_ENV_FILE"
            chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$MCP_ENV_FILE"
        fi
        return 0
    fi

    # 若已存在 .env 且有 API Key，詢問是否覆寫
    if [[ -f "$MCP_ENV_FILE" ]] && grep -q "LLM_API_KEY=." "$MCP_ENV_FILE"; then
        log_skip "API Key 已設定 (${MCP_ENV_FILE})"
        read -p "是否重新設定 API Key? [y/N]: " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    echo ""
    echo "  請選擇 LLM 提供者："
    echo "    1) OpenAI"
    echo "    2) Anthropic"
    echo "    3) 自訂"
    echo ""

    local provider_choice provider
    read -p "  選擇 [1-3] (預設: 1): " provider_choice
    case "${provider_choice:-1}" in
        1) provider="openai" ;;
        2) provider="anthropic" ;;
        3) read -p "  提供者名稱: " provider ;;
        *) provider="openai" ;;
    esac

    local api_key
    read -s -p "  請輸入 API Key: " api_key
    echo ""

    if [[ -z "$api_key" ]]; then
        log_warn "未輸入 API Key，跳過設定"
        return 0
    fi

    cat > "$MCP_ENV_FILE" <<EOF
# Ghidra-MCP-WSL-Auto 自動產生
# 請勿將此檔案加入版本控制
LLM_PROVIDER=${provider}
LLM_API_KEY=${api_key}
MCP_SERVER_PORT=8080
EOF

    chmod 600 "$MCP_ENV_FILE"
    chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$MCP_ENV_FILE"

    log_ok "API Key 已設定 (提供者: ${provider})"
}

# ── 建立啟動器 ──
setup_mcp_create_launcher() {
    local launcher="${SCRIPT_DIR}/bin/ghidra-mcp"

    cat > "$launcher" <<'LAUNCHER'
#!/usr/bin/env bash
# ghidra-mcp — Ghidra + MCP Bridge 一鍵啟動器
set -euo pipefail

MCP_DIR="${MCP_DIR:-/opt/ghidra-mcp}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ghidra}"
MCP_PATH="${MCP_DIR}/GhidraMCP"
ENV_FILE="${MCP_PATH}/.env"
VENV_DIR="${MCP_PATH}/.venv"

# 載入環境變數
if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$ENV_FILE"
    set +a
fi

# 啟用 venv
if [[ -d "${VENV_DIR}/bin" ]]; then
    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"
fi

# 尋找 MCP Bridge 腳本
MCP_BRIDGE=$(find "$MCP_PATH" -name "bridge*.py" -o -name "server*.py" 2>/dev/null | head -1)

if [[ -n "$MCP_BRIDGE" ]]; then
    echo "[INFO] 啟動 MCP Bridge: $(basename "$MCP_BRIDGE")"
    python3 "$MCP_BRIDGE" &
    MCP_PID=$!

    # 等待 MCP 就緒 (最多 30 秒)
    MCP_PORT="${MCP_SERVER_PORT:-8080}"
    for i in {1..30}; do
        if curl -s "http://127.0.0.1:${MCP_PORT}/" >/dev/null 2>&1; then
            echo "[OK] MCP Bridge 已就緒 (port: ${MCP_PORT})"
            break
        fi
        sleep 1
    done

    if [[ $i -eq 30 ]]; then
        echo "[WARN] MCP Bridge 啟動逾時，Ghidra 仍可正常使用"
    fi
else
    echo "[WARN] 未找到 MCP Bridge 腳本，僅啟動 Ghidra"
    MCP_PID=""
fi

# 啟動 Ghidra
"${INSTALL_DIR}/ghidraRun" "$@"

# 清理
if [[ -n "${MCP_PID:-}" ]]; then
    kill "$MCP_PID" 2>/dev/null || true
fi
LAUNCHER

    chmod +x "$launcher"

    # 複製到 PATH 可見的位置
    cp "$launcher" /usr/local/bin/ghidra-mcp 2>/dev/null || true

    log_ok "啟動器已建立: ${launcher}"
}

# ── 統一入口 ──
setup_mcp_run_all() {
    log_info "=== F3: GhidraMCP 插件整合 ==="

    setup_mcp_clone_repo
    setup_mcp_create_venv
    setup_mcp_install_deps
    setup_mcp_mount_extension
    setup_mcp_configure_api
    setup_mcp_create_launcher

    log_ok "=== F3: GhidraMCP 插件整合完成 ==="
}
