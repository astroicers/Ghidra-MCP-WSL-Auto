# SPEC-003：GhidraMCP 插件整合模組 (setup_mcp.sh)

> 對應 SRS F3：GhidraMCP 插件整合

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-003 |
| **關聯 ADR** | ADR-001（初始技術棧選型） |
| **估算複雜度** | 高 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 目標（Goal）

> Clone GhidraMCP 儲存庫，建立隔離的 Python venv 環境安裝 MCP 依賴，將插件掛載至 Ghidra 擴充路徑，並透過互動式引導設定 MCP 連接模式（Claude Code CLI 或 API Key）。

---

## 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| MCP_DIR | string (env) | env | 可選，預設 /opt/ghidra-mcp |
| INSTALL_DIR | string (env) | env | 可選，預設 /opt/ghidra (Ghidra 安裝路徑) |
| NO_INTERACTIVE | bool (env) | CLI --no-interactive | 可選，跳過連接模式設定 |

---

## 輸出規格（Expected Output）

**成功情境：**
- /opt/ghidra-mcp/GhidraMCP/ 為有效 git repo
- /opt/ghidra-mcp/GhidraMCP/.venv/ 已建立且含 MCP SDK
- Ghidra Extensions/ 目錄下已掛載 MCP 插件
- .env 檔案已建立，含 MCP 連接模式設定（CLI 模式 chmod 644 / API Key 模式 chmod 600）

**失敗情境：**

| 錯誤類型 | Exit Code | 處理方式 |
|----------|-----------|----------|
| git clone 失敗 | 30 | 輸出網路錯誤，提示檢查 GitHub 連線 |
| venv 建置失敗 | 31 | 輸出 Python 版本，提示重裝 python3-venv |
| pip install 失敗 | 32 | 輸出失敗套件，提示網路或版本問題 |
| 插件掛載失敗 | 33 | 提示 Ghidra Extensions 路徑不存在 |

---

## 模組介面設計

### 匯出函式

```bash
setup_mcp_clone_repo()        # git clone 或 git pull (冪等)
setup_mcp_create_venv()       # python3 -m venv 建置
setup_mcp_install_deps()      # pip install -r requirements.txt
setup_mcp_mount_extension()   # 掛載 .zip 至 Ghidra Extensions/
setup_mcp_configure_connection()  # 互動式 MCP 連接模式設定
setup_mcp_create_launcher()   # 建立 bin/ghidra-mcp 啟動器
setup_mcp_run_all()           # 依序呼叫上述所有步驟
```

### Clone 策略

```bash
MCP_REPO="https://github.com/LaurieWired/GhidraMCP.git"
MCP_PATH="${MCP_DIR}/GhidraMCP"

if [[ -d "$MCP_PATH/.git" ]]; then
    # 有效 git repo → git -C "$MCP_PATH" pull
    log_skip "GhidraMCP 已存在，更新中..."
elif [[ -d "$MCP_PATH" ]]; then
    # 目錄存在但非 git repo → 清理重建
    rm -rf "$MCP_PATH"
    git clone "$MCP_REPO" "$MCP_PATH"
else
    git clone "$MCP_REPO" "$MCP_PATH"
fi
```

### MCP 連接模式設定

```bash
setup_mcp_configure_connection() {
    [[ "${NO_INTERACTIVE:-false}" == "true" ]] && { _setup_mcp_create_env_template; return 0; }

    echo "請選擇 MCP 連接模式："
    echo "  1) Claude Code CLI（推薦）"
    echo "  2) API Key（OpenAI / Anthropic / 自訂）"
    read -r -p "選擇 [1-2] (預設: 1): " mode_choice

    case "${mode_choice:-1}" in
        2) _setup_mcp_configure_api_key ;;   # API Key 互動設定
        *) _setup_mcp_configure_cli_mode ;;  # CLI 模式，建立基本 .env
    esac
}
```

### 插件掛載

```bash
# 優先使用 GitHub Release 預編譯 ZIP
# 備選：本機 Gradle 編譯（需額外設定）
EXTENSION_DIR="${INSTALL_DIR}/Ghidra/Extensions"
mkdir -p "$EXTENSION_DIR"

# 方案 A: 符號連結
ln -sf "${MCP_PATH}/dist/"*.zip "$EXTENSION_DIR/"

# 方案 B: 複製（fallback）
# cp "${MCP_PATH}/dist/"*.zip "$EXTENSION_DIR/"
```

---

## 邊界條件（Edge Cases）

- Case 1：GhidraMCP 上游 requirements.txt 變更 → venv 存在時仍執行 pip install（更新依賴）
- Case 2：選擇 CLI 模式 → 跳過 API Key，建立含 MCP_MODE=cli 和 MCP_SERVER_PORT 的 .env
- Case 3：--no-interactive 模式 → 跳過連接模式設定，建立預設模板
- Case 4：Ghidra Extensions 路徑在不同版本可能不同 → 動態偵測 `find $INSTALL_DIR -name Extensions -type d`
- Case 5：.env 已存在 → 提示是否覆寫，預設保留現有設定

---

## 驗收標準（Done When）

- [ ] `bash -n scripts/setup_mcp.sh` 語法正確
- [ ] `make test-filter FILTER=setup_mcp` 全數通過
- [ ] `make lint` 無 shellcheck error
- [ ] venv 環境可成功 `import mcp`（或對應 SDK）
- [ ] .env 檔案權限正確（CLI 模式 644 / API Key 模式 600），不被 git 追蹤
- [ ] 重複執行時 clone 步驟顯示 [SKIP]，執行 git pull
- [ ] --no-interactive 模式正確跳過連接模式設定

---

## 禁止事項（Out of Scope）

- 不要修改 Ghidra 核心檔案
- 不要在 .env 以外的位置儲存 API Key（若使用 API Key 模式）
- 不要安裝 Gradle 或從原始碼編譯插件（v1.0 使用預編譯版本）

---

## 參考資料（References）

- 相關 ADR：ADR-001
- SRS：§3 F3 GhidraMCP 插件整合
- 上游：https://github.com/LaurieWired/GhidraMCP
