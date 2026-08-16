#!/usr/bin/env bash
# scripts/setup_mcp.sh — F3: GhidraMCP 插件整合模組
# 關聯 SPEC: SPEC-003 | 關聯 ADR: ADR-001

MCP_REPO="${MCP_REPO_URL:-https://github.com/LaurieWired/GhidraMCP.git}"
MCP_PATH="${MCP_DIR:-/opt/ghidra-mcp}/GhidraMCP"
MCP_VENV="${MCP_PATH}/.venv"
MCP_ENV_FILE="${MCP_PATH}/.env"

# 本地模型預設值（Tier A：離線 agentic）
DEFAULT_OLLAMA_MODEL="${DEFAULT_OLLAMA_MODEL:-qwen2.5:32b}"
DEFAULT_OLLAMA_HOST="${OLLAMA_HOST:-http://127.0.0.1:11434}"
# 多步 tool calling 可靠度門檻（B 參數量）；低於此值 agentic 流程失敗率極高
MIN_AGENTIC_MODEL_B="${MIN_AGENTIC_MODEL_B:-14}"

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
    echo "    1) Claude Code CLI（能力最強，需連線至雲端）"
    echo "    2) API Key（OpenAI / Anthropic / 自訂）"
    echo "    3) 本地模型（Ollama + 支援 SSE 的 MCP client，完全離線）"
    echo ""

    local mode_choice
    read -r -p "  選擇 [1-3] (預設: 1): " mode_choice

    case "${mode_choice:-1}" in
        2) _setup_mcp_configure_api_key ;;
        3) _setup_mcp_configure_local_mode ;;
        *) _setup_mcp_configure_cli_mode ;;
    esac
}

_setup_mcp_configure_cli_mode() {
    cat > "$MCP_ENV_FILE" <<'EOF'
# Ghidra-MCP-WSL-Auto 自動產生
MCP_MODE=cli
GHIDRA_PLUGIN_PORT=60005
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
GHIDRA_PLUGIN_PORT=60005
MCP_SERVER_PORT=60006
EOF

    chmod 600 "$MCP_ENV_FILE"
    chown "${SUDO_USER:-$USER}:${SUDO_USER:-$USER}" "$MCP_ENV_FILE"

    log_ok "API Key 已設定 (提供者: ${provider})"
}

# ── 由模型 tag 解析參數量（qwen2.5:32b → 32），無法判斷時回傳空字串 ──
_parse_model_size_b() {
    local model="$1"
    # 取所有 <數字>b 樣式中的最大值：MoE 命名（qwen3-30b-a3b）應以總參數量為準
    echo "$model" \
        | grep -oiE '[0-9]+b([^a-z0-9]|$)' \
        | grep -oE '^[0-9]+' \
        | sort -n | tail -1
}

# ── 模型規模警告：小模型的多步 tool calling 失敗率極高 ──
_warn_if_model_too_small() {
    local model="$1" size
    size="$(_parse_model_size_b "$model")"

    if [[ -z "$size" ]]; then
        log_info "無法由名稱判斷 ${model} 的參數量，略過規模檢查"
        return 0
    fi

    if (( size < MIN_AGENTIC_MODEL_B )); then
        log_warn "模型 ${model} 約 ${size}B，低於 agentic 建議門檻 ${MIN_AGENTIC_MODEL_B}B"
        echo ""
        echo "    小模型在多步 tool calling 上並非「效果較差」，而是會直接失敗："
        echo "      - 3B 級：約 89% 的 tool 初始化失敗率"
        echo "      - 32B 級：約 0%"
        echo "    且誤差會複利累積（每步 95% 成功 × 8 步 ≈ 66% 整體成功）。"
        echo ""
        echo "    建議：改用 ${MIN_AGENTIC_MODEL_B}B 以上模型，或改走模式 1 / 2（雲端）。"
        echo ""
        return 1
    fi

    log_ok "模型 ${model} 約 ${size}B，符合 agentic 門檻（≥ ${MIN_AGENTIC_MODEL_B}B）"
}

_setup_mcp_configure_local_mode() {
    echo ""
    echo "  本地模型模式（完全離線，不會傳送任何資料至雲端）"
    echo ""

    local ollama_model ollama_host
    read -r -p "  Ollama 模型 (預設: ${DEFAULT_OLLAMA_MODEL}): " ollama_model
    ollama_model="${ollama_model:-$DEFAULT_OLLAMA_MODEL}"
    read -r -p "  Ollama 位址 (預設: ${DEFAULT_OLLAMA_HOST}): " ollama_host
    ollama_host="${ollama_host:-$DEFAULT_OLLAMA_HOST}"

    cat > "$MCP_ENV_FILE" <<EOF
# Ghidra-MCP-WSL-Auto 自動產生
MCP_MODE=local
OLLAMA_HOST=${ollama_host}
OLLAMA_MODEL=${ollama_model}
GHIDRA_PLUGIN_PORT=60005
MCP_SERVER_PORT=60006
EOF
    # 本模式不含任何金鑰，權限比照 CLI 模式
    chmod 644 "$MCP_ENV_FILE"
    log_ok "已選擇本地模型模式 (${ollama_model})"

    _warn_if_model_too_small "$ollama_model" || true

    echo "  下一步：安裝 Ollama 與支援 SSE 的 MCP client"
    echo "    curl -fsSL https://ollama.com/install.sh | sh"
    echo "    ollama pull ${ollama_model}"
    echo "    uv tool install --upgrade ollmcp   # 或 pip install --upgrade ollmcp"
    echo ""
    echo "  啟動 ghidra-mcp 後，以下列指令連接既有 SSE 端點："
    echo "    ollmcp --mcp-server-url http://127.0.0.1:60006/sse --model ${ollama_model}"
    echo ""
    echo "  註：60006 為標準 MCP SSE 端點，任何支援 SSE 的 client 皆可連接"
    echo "      （ollmcp / llama.cpp / Cline / 5ire 等）。"
    echo "  完整端到端實測步驟請見 docs/VERIFICATION.md"
    echo ""
}

_setup_mcp_create_env_template() {
    log_info "請手動編輯連接模式: ${MCP_ENV_FILE}"
    if [[ ! -f "$MCP_ENV_FILE" ]]; then
        cp "${SCRIPT_DIR}/config/.env.template" "$MCP_ENV_FILE" 2>/dev/null || {
            cat > "$MCP_ENV_FILE" <<'ENVEOF'
# Ghidra-MCP-WSL-Auto 自動產生
MCP_MODE=cli
GHIDRA_PLUGIN_PORT=60005
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

# Port 設定
MCP_PORT="${MCP_SERVER_PORT:-60006}"
GHIDRA_PORT="${GHIDRA_PLUGIN_PORT:-60005}"

# ── 自動 patch Ghidra 插件 port ──
_patch_ghidra_plugin_port() {
    local ghidra_ver tcd_file
    ghidra_ver=$(basename "$INSTALL_DIR" | sed 's/ghidra_//; s/_PUBLIC//')
    # 支援 ~/.config/ghidra/ 和 ~/.ghidra/ 兩種路徑
    for config_base in "${HOME}/.config/ghidra" "${HOME}/.ghidra"; do
        tcd_file="${config_base}/ghidra_${ghidra_ver}_PUBLIC/tools/_code_browser.tcd"
        [[ -f "$tcd_file" ]] && break
    done

    if [[ ! -f "$tcd_file" ]]; then
        echo "[INFO] Ghidra tool config 尚不存在（首次啟動後會產生）"
        echo "[INFO] 首次啟動後請手動設定插件 port:"
        echo "       Edit → Tool Options → GhidraMCP HTTP Server → Server Port: ${GHIDRA_PORT}"
        return 1
    fi

    python3 - "$tcd_file" "$GHIDRA_PORT" <<'PYEOF'
import sys, xml.etree.ElementTree as ET
tcd_file, port = sys.argv[1], sys.argv[2]
tree = ET.parse(tcd_file)
options = tree.getroot().find('.//OPTIONS')
if options is None:
    sys.exit(0)
cat = options.find("CATEGORY[@NAME='GhidraMCP HTTP Server']")
if cat is None:
    cat = ET.SubElement(options, 'CATEGORY', NAME='GhidraMCP HTTP Server')
state = cat.find("STATE[@NAME='Server Port']")
if state is None:
    ET.SubElement(cat, 'STATE', NAME='Server Port', TYPE='int', VALUE=port)
elif state.get('VALUE') != port:
    state.set('VALUE', port)
else:
    sys.exit(0)
tree.write(tcd_file, xml_declaration=True, encoding='unicode')
print(f"[OK] Ghidra 插件 port 已自動設定為 {port}")
PYEOF
}

# 嘗試自動 patch 插件 port（失敗不中斷）
_patch_ghidra_plugin_port 2>/dev/null || true

# 尋找 MCP Bridge 腳本
MCP_BRIDGE=$(find "$MCP_PATH" -name "bridge*.py" -o -name "server*.py" 2>/dev/null | head -1)

if [[ -n "$MCP_BRIDGE" ]]; then
    # 啟動前檢查 MCP Bridge port 是否已被佔用
    if ss -tlnp 2>/dev/null | grep -q ":${MCP_PORT} " || \
       curl -s --max-time 1 "http://127.0.0.1:${MCP_PORT}/" >/dev/null 2>&1; then
        echo "[ERROR] Port ${MCP_PORT} 已被佔用，MCP Bridge 無法啟動"
        echo "[INFO]  請檢查: ss -tlnp | grep :${MCP_PORT}"
        echo "[INFO]  或修改 ${ENV_FILE} 中的 MCP_SERVER_PORT 為其他 port"
        MCP_PID=""
    else
        echo "[INFO] 啟動 MCP Bridge: $(basename "$MCP_BRIDGE")"
        echo "[INFO] Ghidra 插件 HTTP port: ${GHIDRA_PORT}, MCP SSE port: ${MCP_PORT}"
        python3 "$MCP_BRIDGE" \
            --ghidra-server "http://127.0.0.1:${GHIDRA_PORT}/" \
            --transport sse \
            --mcp-host 127.0.0.1 \
            --mcp-port "${MCP_PORT}" &
        MCP_PID=$!

        # 等待 MCP Bridge 就緒 (最多 30 秒)
        MCP_READY=false
        for i in {1..30}; do
            if curl -s "http://127.0.0.1:${MCP_PORT}/" >/dev/null 2>&1; then
                echo "[OK] MCP Bridge 已就緒 (port: ${MCP_PORT})"
                MCP_READY=true
                break
            fi
            sleep 1
        done

        if [[ "$MCP_READY" != "true" ]]; then
            echo "[WARN] MCP Bridge 啟動逾時，Ghidra 仍可正常使用"
        fi
    fi
else
    echo "[WARN] 未找到 MCP Bridge 腳本，僅啟動 Ghidra"
    MCP_PID=""
fi

# 啟動 Ghidra
"${INSTALL_DIR}/ghidraRun" "$@" &
GHIDRA_PID=$!

# ── 健康檢查：等待 Ghidra 插件 HTTP server 就緒 ──
if [[ -n "${MCP_PID:-}" ]]; then
    echo "[INFO] 等待 Ghidra 插件 HTTP server (port: ${GHIDRA_PORT})..."
    PLUGIN_READY=false
    for j in {1..60}; do
        if curl -s --max-time 1 "http://127.0.0.1:${GHIDRA_PORT}/" >/dev/null 2>&1; then
            echo "[OK] Ghidra 插件 HTTP server 已就緒 (port: ${GHIDRA_PORT})"
            PLUGIN_READY=true
            break
        fi
        sleep 1
    done

    if [[ "$PLUGIN_READY" != "true" ]]; then
        echo "[WARN] Ghidra 插件 HTTP server 未偵測到 (port: ${GHIDRA_PORT})"
        echo "[WARN] 請確認："
        echo "       1. 已啟用 GhidraMCPPlugin (File → Configure → Developer)"
        echo "       2. 插件 port 設為 ${GHIDRA_PORT} (Edit → Tool Options → GhidraMCP HTTP Server)"
        echo "[WARN] MCP Bridge 已啟動但可能無法正常運作"
    fi
fi

# ── 依連接模式提示下一步 ──
if [[ -n "${MCP_PID:-}" ]]; then
    case "${MCP_MODE:-cli}" in
        local)
            echo "[INFO] 連接模式: 本地模型（離線）"
            echo "       ollmcp --mcp-server-url http://127.0.0.1:${MCP_PORT}/sse --model ${OLLAMA_MODEL:-qwen2.5:32b}"
            ;;
        apikey)
            echo "[INFO] 連接模式: API Key (${LLM_PROVIDER:-未指定})"
            echo "       MCP SSE 端點: http://127.0.0.1:${MCP_PORT}/sse"
            ;;
        *)
            echo "[INFO] 連接模式: Claude Code CLI"
            echo "       claude mcp add --transport sse ghidra http://127.0.0.1:${MCP_PORT}/sse"
            ;;
    esac
fi

# 等待 Ghidra 結束
wait "$GHIDRA_PID" 2>/dev/null || true

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

# ── 離線就緒自檢（--check-offline） ──
setup_mcp_check_offline() {
    log_info "=== 離線就緒自檢 ==="
    local failed=0

    if [[ -f "$MCP_ENV_FILE" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "$MCP_ENV_FILE"
        set +a
        log_ok "已載入設定: ${MCP_ENV_FILE} (MCP_MODE=${MCP_MODE:-未設定})"
    else
        log_warn "尚未設定 ${MCP_ENV_FILE}，改以預設值檢查"
    fi

    local ollama_host="${OLLAMA_HOST:-$DEFAULT_OLLAMA_HOST}"
    local ollama_model="${OLLAMA_MODEL:-$DEFAULT_OLLAMA_MODEL}"
    local mcp_port="${MCP_SERVER_PORT:-60006}"

    # 1) Ollama daemon
    local tags_json=""
    if tags_json=$(curl -s --max-time 3 "${ollama_host}/api/tags" 2>/dev/null) && [[ -n "$tags_json" ]]; then
        log_ok "Ollama daemon 運行中: ${ollama_host}"
    else
        log_error "無法連接 Ollama: ${ollama_host}"
        echo "         啟動方式: ollama serve"
        tags_json=""
        ((failed++)) || true
    fi

    # 2) 模型是否已下載
    if [[ -n "$tags_json" ]]; then
        if echo "$tags_json" | grep -qF "\"${ollama_model}"; then
            log_ok "模型已就緒: ${ollama_model}"
        else
            log_error "模型未下載: ${ollama_model}"
            echo "         下載方式: ollama pull ${ollama_model}"
            ((failed++)) || true
        fi
    fi

    # 3) 模型規模是否足以支撐多步 tool calling
    _warn_if_model_too_small "$ollama_model" || { ((failed++)) || true; }

    # 4) MCP SSE 端點
    if curl -s --max-time 2 "http://127.0.0.1:${mcp_port}/" >/dev/null 2>&1; then
        log_ok "MCP SSE 端點可連接: http://127.0.0.1:${mcp_port}/sse"
    else
        log_warn "MCP SSE 端點未回應 (port ${mcp_port})，請先執行 ghidra-mcp"
    fi

    echo ""
    if (( failed == 0 )); then
        log_ok "離線就緒檢查通過，可執行離線 agentic 分析"
        return 0
    fi

    log_error "離線就緒檢查未通過（${failed} 項需處理）"
    return 1
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
