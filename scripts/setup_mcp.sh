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

# ── 解包 GhidraMCP 插件 ZIP（處理雙層包裝） ──
_extract_ghidramcp_plugin() {
    local zip_file="$1" target_dir="$2"

    # 檢查 ZIP 內是否直接包含 extension.properties（內層 ZIP 格式）
    if unzip -l "$zip_file" 2>/dev/null | grep -q "extension.properties"; then
        log_info "解壓插件至 ${target_dir}..."
        unzip -q -o "$zip_file" -d "$target_dir"
        return $?
    fi

    # 外層格式：提取內層插件 ZIP（basename 不含 release）
    log_info "偵測到 Release 包裝，解壓內層插件..."
    local inner_zip
    inner_zip=$(unzip -l "$zip_file" 2>/dev/null \
        | grep -oP '\S+\.zip' | while read -r f; do
            local base
            base=$(basename "$f")
            if [[ "$base" == *"GhidraMCP"* && "$base" != *"release"* ]]; then
                echo "$f"
            fi
        done | head -1)

    if [[ -n "$inner_zip" ]]; then
        unzip -q -o "$zip_file" "$inner_zip" -d /tmp/
        local inner_path="/tmp/${inner_zip}"
        unzip -q -o "$inner_path" -d "$target_dir"
        rm -f "$inner_path"
        return 0
    fi

    # 無法識別結構，嘗試直接解壓
    log_warn "無法辨識 ZIP 結構，嘗試直接解壓..."
    unzip -q -o "$zip_file" -d "$target_dir"
}

# ── 掛載插件 ──
setup_mcp_mount_extension() {
    # 動態偵測 Ghidra Extensions 路徑
    local ext_dir
    ext_dir=$(find "$INSTALL_DIR" -path "*/Ghidra/Extensions" -type d 2>/dev/null | head -1)

    if [[ -z "$ext_dir" ]]; then
        ext_dir="${INSTALL_DIR}/Ghidra/Extensions"
        mkdir -p "$ext_dir"
    fi

    # 冪等：已安裝則跳過
    if [[ -f "${ext_dir}/GhidraMCP/extension.properties" ]]; then
        log_skip "GhidraMCP 插件已安裝於 ${ext_dir}/GhidraMCP"
        return 0
    fi

    # 尋找本地預編譯 ZIP
    local extension_zip
    extension_zip=$(find "$MCP_PATH" -name "ghidra_*.zip" -o -name "GhidraMCP*.zip" 2>/dev/null | head -1)

    if [[ -z "$extension_zip" ]]; then
        # 從 GitHub Release 下載
        log_warn "未找到預編譯插件，嘗試從 GitHub Release 下載..."
        local mcp_release_url
        mcp_release_url=$(curl -sL "https://api.github.com/repos/LaurieWired/GhidraMCP/releases/latest" 2>/dev/null \
            | jq -r '.assets[] | select(.name | endswith(".zip")) | .browser_download_url' 2>/dev/null | head -1)

        if [[ -n "$mcp_release_url" && "$mcp_release_url" != "null" ]]; then
            extension_zip="/tmp/ghidramcp_release.zip"
            if ! wget -q -O "$extension_zip" "$mcp_release_url"; then
                log_warn "插件下載失敗，請手動安裝"
                log_warn "下載位址: ${mcp_release_url}"
                rm -f "$extension_zip"
                return 1
            fi
            log_ok "插件已下載: $(basename "$mcp_release_url")"
        else
            log_warn "無法找到預編譯插件，請參考 GhidraMCP README 手動編譯"
            return 1
        fi
    fi

    # 解包插件（自動處理雙層 ZIP）
    _extract_ghidramcp_plugin "$extension_zip" "$ext_dir"

    # 清理暫存
    rm -f /tmp/ghidramcp_release.zip

    # ── 掛載後驗證 ──
    if [[ -f "${ext_dir}/GhidraMCP/extension.properties" ]]; then
        log_ok "GhidraMCP 插件安裝驗證通過: ${ext_dir}/GhidraMCP"
    else
        log_warn "插件安裝驗證失敗: 未找到 extension.properties"
        log_warn "請手動安裝: Ghidra → File → Install Extensions → 選擇 ZIP"
        return 1
    fi
}

# ── MCP 連接模式設定 ──
setup_mcp_configure_connection() {
    if [[ "${NO_INTERACTIVE:-false}" == "true" ]]; then
        log_skip "互動模式已停用 (--no-interactive)"
        _setup_mcp_create_env_template
        return 0
    fi

    # 若已存在 .env 且有設定，詢問是否重新設定
    if [[ -f "$MCP_ENV_FILE" ]] && grep -qE "(MCP_MODE=|LLM_API_KEY=.)" "$MCP_ENV_FILE"; then
        log_skip "MCP 連接已設定 (${MCP_ENV_FILE})"
        read -r -p "是否重新設定連接模式? [y/N]: " overwrite
        [[ ! "$overwrite" =~ ^[Yy]$ ]] && return 0
    fi

    echo ""
    echo "  請選擇 MCP 連接模式："
    echo "    1) Claude Code CLI（推薦）"
    echo "    2) API Key（OpenAI / Anthropic / 自訂）"
    echo ""

    local mode_choice
    read -r -p "  選擇 [1-2] (預設: 1): " mode_choice

    case "${mode_choice:-1}" in
        2) _setup_mcp_configure_api_key ;;
        *) _setup_mcp_configure_cli_mode ;;
    esac
}

_setup_mcp_configure_cli_mode() {
    cat > "$MCP_ENV_FILE" <<'EOF'
# Ghidra-MCP-WSL-Auto 自動產生
MCP_MODE=cli
MCP_SERVER_PORT=60006
EOF
    chmod 644 "$MCP_ENV_FILE"
    log_ok "已選擇 Claude Code CLI 模式"
    echo ""
    echo "  下一步：在 WSL 中安裝 Claude Code"
    echo "    npm install -g @anthropic-ai/claude-code"
    echo ""
    echo "  啟動後執行 'claude mcp add --transport sse ghidra http://127.0.0.1:60006/sse'"
    echo ""
}

_setup_mcp_configure_api_key() {
    echo ""
    echo "  請選擇 LLM 提供者："
    echo "    1) OpenAI"
    echo "    2) Anthropic"
    echo "    3) 自訂"
    echo ""

    local provider_choice provider
    read -r -p "  選擇 [1-3] (預設: 1): " provider_choice
    case "${provider_choice:-1}" in
        1) provider="openai" ;;
        2) provider="anthropic" ;;
        3) read -r -p "  提供者名稱: " provider ;;
        *) provider="openai" ;;
    esac

    local api_key
    read -r -s -p "  請輸入 API Key: " api_key
    echo ""

    if [[ -z "$api_key" ]]; then
        log_warn "未輸入 API Key，跳過設定"
        return 0
    fi

    cat > "$MCP_ENV_FILE" <<EOF
# Ghidra-MCP-WSL-Auto 自動產生
# 請勿將此檔案加入版本控制
MCP_MODE=apikey
LLM_PROVIDER=${provider}
LLM_API_KEY=${api_key}
MCP_SERVER_PORT=60006
EOF

    chmod 600 "$MCP_ENV_FILE"
    chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$MCP_ENV_FILE"

    log_ok "API Key 已設定 (提供者: ${provider})"
}

_setup_mcp_create_env_template() {
    log_info "請手動編輯連接模式: ${MCP_ENV_FILE}"
    if [[ ! -f "$MCP_ENV_FILE" ]]; then
        cp "${SCRIPT_DIR}/config/.env.template" "$MCP_ENV_FILE" 2>/dev/null || {
            cat > "$MCP_ENV_FILE" <<'ENVEOF'
# Ghidra-MCP-WSL-Auto 自動產生
MCP_MODE=cli
MCP_SERVER_PORT=60006
ENVEOF
        }
        chmod 644 "$MCP_ENV_FILE"
    fi
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
    MCP_PORT="${MCP_SERVER_PORT:-60006}"

    # 啟動前檢查 port 是否已被佔用
    if ss -tlnp 2>/dev/null | grep -q ":${MCP_PORT} " || \
       curl -s --max-time 1 "http://127.0.0.1:${MCP_PORT}/" >/dev/null 2>&1; then
        echo "[ERROR] Port ${MCP_PORT} 已被佔用，MCP Bridge 無法啟動"
        echo "[INFO]  請檢查: ss -tlnp | grep :${MCP_PORT}"
        echo "[INFO]  或修改 ${ENV_FILE} 中的 MCP_SERVER_PORT 為其他 port"
        MCP_PID=""
    else
        echo "[INFO] 啟動 MCP Bridge: $(basename "$MCP_BRIDGE")"
        python3 "$MCP_BRIDGE" &
        MCP_PID=$!

        # 等待 MCP 就緒 (最多 30 秒)
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
    setup_mcp_configure_connection
    setup_mcp_create_launcher

    log_ok "=== F3: GhidraMCP 插件整合完成 ==="
}
