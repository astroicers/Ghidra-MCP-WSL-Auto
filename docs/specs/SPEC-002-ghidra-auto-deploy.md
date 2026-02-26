# SPEC-002：Ghidra 自動部署模組 (setup_ghidra.sh)

> 對應 SRS F2：Ghidra 自動部署

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-002 |
| **關聯 ADR** | ADR-001（初始技術棧選型） |
| **估算複雜度** | 高 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 目標（Goal）

> 從 GitHub Releases 動態取得最新 Ghidra 穩定版，下載解壓至 /opt/ghidra，根據系統 RAM 自動調校 JVM 記憶體，並配置全域 PATH。

---

## 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| GHIDRA_VERSION | string (env) | CLI --ghidra-version | 可選，預設動態取得 latest |
| GHIDRA_XMX | int (env) | CLI / env | 可選，預設自動計算 (MB) |
| INSTALL_DIR | string (env) | env | 可選，預設 /opt/ghidra |

---

## 輸出規格（Expected Output）

**成功情境：**
- /opt/ghidra_\<version\>/ 目錄存在且包含 ghidraRun
- /opt/ghidra → /opt/ghidra_\<version\>/ 符號連結建立
- ghidraRun.vmoptions 中 -Xmx 已調校
- /etc/profile.d/ghidra.sh 已寫入 PATH 設定

**失敗情境：**

| 錯誤類型 | Exit Code | 處理方式 |
|----------|-----------|----------|
| GitHub API 呼叫失敗 | 20 | 顯示手動下載指引 |
| 下載失敗 / 檔案損壞 | 21 | 清理殘檔，提示重試 |
| 解壓失敗 | 22 | 清理殘檔，提示重試 |

---

## 模組介面設計

### 匯出函式

```bash
setup_ghidra_fetch_version()    # GitHub API 取版本，或使用 GHIDRA_VERSION
setup_ghidra_download()         # wget -c 下載 (支援斷點續傳)
setup_ghidra_verify()           # 驗證 ZIP 檔案大小 (>100MB)
setup_ghidra_extract()          # 解壓至 /opt/ 並建立符號連結
setup_ghidra_tune_jvm()         # 計算並寫入 -Xmx 參數
setup_ghidra_configure_path()   # 寫入 /etc/profile.d/ghidra.sh
setup_ghidra_run_all()          # 依序呼叫上述所有步驟
```

### 版本取得流程

```bash
GITHUB_API="https://api.github.com/repos/NationalSecurityAgency/ghidra/releases/latest"

if [[ -n "${GHIDRA_VERSION:-}" ]]; then
    # 使用指定版本，組合下載 URL
else
    RELEASE_JSON=$(curl -sL "$GITHUB_API")
    DOWNLOAD_URL=$(echo "$RELEASE_JSON" | jq -r \
        '.assets[] | select(.name | endswith(".zip")) | .browser_download_url')
    GHIDRA_VERSION=$(echo "$RELEASE_JSON" | jq -r '.tag_name' | sed 's/Ghidra_//')
fi
```

### JVM 記憶體調校公式

```bash
TOTAL_MEM=$(free -m | awk '/Mem:/{print $2}')
XMX_MB=$(( TOTAL_MEM / 4 ))
XMX_MB=$(( XMX_MB < 2048 ? 2048 : XMX_MB ))    # 下限 2GB
XMX_MB=$(( XMX_MB > 16384 ? 16384 : XMX_MB ))  # 上限 16GB
# 可被 GHIDRA_XMX 環境變數覆寫
```

### 冪等性策略

```bash
# 若 /opt/ghidra/ghidraRun 已存在且版本相同 → [SKIP]
# 若版本不同 → 下載新版本，更新符號連結，保留舊版本
# 若 ZIP 已下載且大小正確 → 跳過下載
```

---

## 邊界條件（Edge Cases）

- Case 1：GitHub API rate limit (60 req/hr) → 顯示 `GHIDRA_VERSION=x.y.z` 手動指定方式
- Case 2：下載中途網路中斷 → wget -c 斷點續傳，下次執行自動恢復
- Case 3：/opt 空間不足 → 解壓前檢查可用空間（需 ~1.5GB）
- Case 4：已存在不同版本的 Ghidra → 保留舊版目錄，僅更新符號連結
- Case 5：ghidraRun.vmoptions 格式變更 → 使用 grep + sed 精確匹配 `-Xmx` 行

---

## 驗收標準（Done When）

- [ ] `bash -n scripts/setup_ghidra.sh` 語法正確
- [ ] `make test-filter FILTER=setup_ghidra` 全數通過
- [ ] `make lint` 無 shellcheck error
- [ ] 動態版本取得能正確解析 GitHub API 回應
- [ ] 斷點續傳功能正常（中斷後重跑不重新下載）
- [ ] JVM -Xmx 自動調校值在合理範圍 (2GB~16GB)
- [ ] /opt/ghidra 符號連結指向正確版本

---

## 禁止事項（Out of Scope）

- 不要安裝 GhidraMCP 插件（屬於 SPEC-003）
- 不要處理 API Key（屬於 SPEC-003）
- 不要支援 Ghidra headless-only 模式
- 不要建立 Gradle 編譯環境

---

## 參考資料（References）

- 相關 ADR：ADR-001
- SRS：§3 F2 Ghidra 自動部署
- GitHub：https://github.com/NationalSecurityAgency/ghidra/releases
