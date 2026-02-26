# Changelog

所有重要變更記錄於此檔案。格式依循 [Keep a Changelog](https://keepachangelog.com/)。

## [Unreleased]

### Added
- 專案初始化：ASP 框架、.ai_profile、Makefile
- ADR-001：初始技術棧選型（Bash + 模組化架構）— 狀態 Accepted
- SPEC-001：環境檢測模組 (check_env.sh)
- SPEC-002：Ghidra 自動部署模組 (setup_ghidra.sh)
- SPEC-003：GhidraMCP 插件整合模組 (setup_mcp.sh)
- SPEC-004：主腳本與啟動器 (install.sh + bin/ghidra-mcp)
- install.sh 主安裝腳本（CLI 參數、日誌系統、錯誤處理）
- scripts/check_env.sh：WSL2 驗證、root 檢查、磁碟空間、依賴安裝、JDK/Python 驗證
- scripts/setup_ghidra.sh：GitHub API 版本取得、斷點續傳下載、解壓、JVM 調校、PATH 設定
- scripts/setup_mcp.sh：Clone 策略、venv 建置、插件掛載、互動式 API Key 設定、啟動器
- config/.env.template：API Key 設定模板
- config/ghidra.desktop：Linux 桌面快捷方式
- tests/：bats 測試骨架（check_env、setup_ghidra、setup_mcp、install 測試）

### Changed
- tests/：重寫所有 bats 測試，從骨架升級為 35 個真實函式驗證測試
- tests/test_helper.bash：加入 stub log 函式與健壯的模組載入器

### Fixed
- scripts/setup_ghidra.sh：移除 DOWNLOAD_DIR readonly 避免測試重載衝突
- scripts/setup_mcp.sh：移除模組常數 readonly 並加入預設值，增強測試相容性
- docs/architecture.md：系統架構文件（Mermaid 架構圖 + 資料流序列圖）
- Makefile：調整為 Bash 腳本專案（build=語法檢查、test=bats、lint=shellcheck）
