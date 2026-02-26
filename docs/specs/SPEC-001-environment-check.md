# SPEC-001：環境檢測模組 (check_env.sh)

> 對應 SRS F1：環境自動初始化

| 欄位 | 內容 |
|------|------|
| **規格 ID** | SPEC-001 |
| **關聯 ADR** | ADR-001（初始技術棧選型） |
| **估算複雜度** | 中 |
| **建議模型** | Sonnet |
| **HITL 等級** | standard |

---

## 目標（Goal）

> 在 install.sh 執行初期驗證執行環境為 WSL2，並自動安裝所有必要系統依賴（OpenJDK 21、Python 3.10+、工具鏈），確保後續模組可正常運作。

---

## 輸入規格（Inputs）

| 參數名稱 | 型別 | 來源 | 限制條件 |
|----------|------|------|----------|
| SKIP_APT_UPDATE | bool (env) | CLI --skip-update | 可選，預設 false |

---

## 輸出規格（Expected Output）

**成功情境：**
- 所有函式 return 0
- stdout 輸出 `[OK]` 或 `[SKIP]` 標記
- 所有必要套件已安裝

**失敗情境：**

| 錯誤類型 | Exit Code | 處理方式 |
|----------|-----------|----------|
| 非 WSL2 環境 | 10 | 輸出錯誤訊息並終止 |
| 非 root 執行 | 11 | 提示使用 sudo 並終止 |
| 磁碟空間不足 (<5GB) | 12 | 輸出剩餘空間並終止 |
| apt install 失敗 | 1 | 輸出失敗套件名稱，寫入日誌 |

---

## 模組介面設計

### 匯出函式

```bash
check_env_verify_wsl()      # 驗證 /proc/version 含 "microsoft" 或 WSL_DISTRO_NAME 存在
check_env_verify_root()     # 驗證 EUID == 0
check_env_check_disk()      # 驗證可用空間 >= 5GB
check_env_system_update()   # apt update && apt upgrade -y (SKIP_APT_UPDATE 時跳過)
check_env_install_deps()    # 迴圈安裝 APT_PACKAGES，已裝則 [SKIP]
check_env_verify_java()     # 驗證 java -version 含 "21"
check_env_verify_python()   # 驗證 python3 --version >= 3.10
check_env_run_all()         # 依序呼叫上述所有函式
```

### 依賴套件清單

```bash
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
```

### 冪等性策略

```bash
for pkg in "${APT_PACKAGES[@]}"; do
    if dpkg -s "$pkg" &>/dev/null; then
        log_skip "$pkg 已安裝"
    else
        PACKAGES_TO_INSTALL+=("$pkg")
    fi
done
# 一次性 apt install 所有待裝套件
```

---

## 邊界條件（Edge Cases）

- Case 1：非 WSL 的原生 Linux 環境 → exit 10，明確提示「本腳本僅支援 WSL2」
- Case 2：WSL1 環境 → 同 Case 1，WSL_INTEROP 環境變數可區分
- Case 3：apt update 因網路問題失敗 → 重試 1 次，仍失敗則 exit 1
- Case 4：OpenJDK 21 不在 apt 預設 repo（舊版 Ubuntu）→ 提示加入 PPA 或升級系統
- Case 5：磁碟空間剛好在邊界值（5GB）→ 使用 `>=` 比較，通過

---

## 驗收標準（Done When）

- [ ] `bash -n scripts/check_env.sh` 語法正確
- [ ] `make test-filter FILTER=check_env` 全數通過
- [ ] `make lint` 無 shellcheck error
- [ ] 在 WSL2 Ubuntu 22.04 環境實際執行成功
- [ ] 在非 WSL 環境執行時正確以 exit 10 退出
- [ ] 重複執行時，已安裝套件顯示 [SKIP]

---

## 禁止事項（Out of Scope）

- 不要支援非 apt 系統（dnf/yum/pacman）
- 不要安裝 Ghidra 或 MCP（屬於 SPEC-002/003）
- 不要處理 API Key（屬於 SPEC-003）

---

## 參考資料（References）

- 相關 ADR：ADR-001
- SRS：§3 F1 環境自動初始化
- SRS：§4 非功能需求（冪等性、錯誤處理）
