# [ADR-002]: 離線分層與 client 無關的 MCP 連接模式

| 欄位 | 內容 |
|------|------|
| **狀態** | `Accepted` |
| **日期** | 2026-07-28 |
| **決策者** | 專案負責人 |

---

## 背景（Context）

> ADR-001 將本專案定位為「WSL2 一鍵部署 Ghidra + GhidraMCP」，並將 MCP 連接模式限定為 CLI（Claude Code）與 API Key 兩種。經重新檢視，此定位有三個前提不成立：
>
> 1. **WSL2 專門化不構成差異化**：實際使用者僅專案負責人本人，且其他環境亦可正常運作。WSL2 相關處理應視為實作細節，而非產品賣點。
> 2. **「安裝困難」的立論不成立**：上游 GhidraMCP 本身已提供預編譯 release ZIP，安裝流程為 GUI 六步驟加一支 Python bridge，自動化的邊際效益低於原先估計。
> 3. **離線能力是唯一真實且未被滿足的需求**：逆向工程的實務場景（惡意程式樣本、受 NDA 約束的韌體、涉及出口管制的二進位檔）經常在法規上禁止將反編譯結果傳送至雲端服務。現行設計 `_setup_mcp_configure_cli_mode()` 寫入 `MCP_MODE=cli` 並引導使用者安裝 Claude Code，使整套流程綁定於雲端。
>
> **關鍵技術事實**：現行 launcher（`scripts/setup_mcp.sh`）已以 `--transport sse --mcp-host 127.0.0.1 --mcp-port 60006` 啟動 bridge。SSE 端點本質上與 client 無關，任何支援 SSE 的 MCP client 皆可連接。**離線障礙並非架構限制，而是設定與文件層的自我綁定。**
>
> 需要決定：如何在不變更架構的前提下解除 client 綁定，以及離線情境下應提供何種能力分層。

---

## 評估選項（Options Considered）

### 選項 A：新增 `MCP_MODE=local`，以既有 SSE 端點承接本地 MCP client

- **作法**：在既有連接模式選單新增第三項，寫入 `MCP_MODE=local` 與 Ollama 相關設定；引導使用者以支援 SSE 的本地 client（如 `mcp-client-for-ollama`——套件與指令名為 `ollmcp`、或 llama.cpp 內建 MCP client）連接 `http://127.0.0.1:60006/sse`。
- **優點**：
  - 不需變更架構，launcher 與 bridge 完全不動
  - 實作規模約 30 行，風險極低
  - 保持 client 無關性，未來新增任何 MCP client 皆無須改碼
  - 完全離線，無金鑰儲存需求（`.env` 權限比照 CLI 模式 644）
- **缺點**：
  - 不自動安裝 Ollama 或拉取模型，使用者仍需自行準備
  - agentic 能力受本地模型規模限制
- **風險**：
  - 小規模模型的多步 tool calling 可靠度極低（實測 qwen2.5:3b 約 89% tool 初始化失敗；32b 級為 0%），若不主動警告，使用者會將模型能力不足誤判為本專案缺陷

### 選項 B：整併 GhidraGPT（Java 擴充套件）以取得離線能力

- **作法**：新增 `--with-ghidragpt` 旗標，clone/下載並掛載 GhidraGPT，透過其內建 Ollama 支援達成離線。
- **優點**：
  - 原生 UI 右鍵操作，不需任何 MCP client
  - 單次任務（Explain 單一函數）在小模型上仍可靠
- **缺點**：
  - 新增 Maven 建置工具鏈依賴
  - 僅支援單一函數分析，無跨函數（interprocedural）能力，無法取代 agentic 流程
  - 需重構既有 `_extract_ghidramcp_plugin()`（硬編碼 `GhidraMCP` 字串）與 release 下載邏輯（硬編碼上游 repo URL）
- **風險**：
  - 與本專案 pin 的 Ghidra 11.3.2 相容性未經驗證（其宣告相容 12.1.x）
  - 兩套金鑰儲存機制並存，造成設定介面混淆

### 選項 C：維持現狀，僅補充文件說明可改用其他 client

- **優點**：零程式碼變更
- **缺點**：使用者仍會依選單預設走向 Claude Code；無模型規模警告，離線失敗時無從診斷
- **風險**：實際上未解決離線需求，僅將問題轉嫁給使用者

---

## 決策（Decision）

> 我們選擇 **選項 A**，並將**選項 B 明確擱置**為條件性後續工作。
>
> 理由：離線障礙的根因是設定層綁定，而非架構缺陷。選項 A 以最小變更（約 30 行）解除綁定，且保留 client 無關性——此為本專案既有 SSE 接線的真實資產價值。選項 B 雖能覆蓋小模型情境，但引入建置依賴與版本相容風險，且其單函數限制無法取代 agentic 能力，應僅在硬體無法支撐 32B 級模型時才作為降級層採用。
>
> 同時確立**離線能力三層架構**：
>
> | Tier | 條件 | 路徑 |
> |------|------|------|
> | **A** | 可執行 32B 級本地模型 | 本地 MCP client + 既有 SSE 60006 → 離線 agentic |
> | **B** | 僅可執行 7B/14B | agentic 不可靠 → GhidraGPT 單次分析（**本次擱置**） |
> | **C** | 允許連線至雲端 | Claude Code + MCP（能力最強） |
>
> 並將 **WSL2 由產品賣點降為實作細節**，不再投入專屬功能開發。

---

## 後果（Consequences）

**正面影響：**
- 解除單一廠商綁定，任何支援 SSE 的 MCP client 皆可使用
- 取得完全離線能力，涵蓋法規上禁止上雲的逆向工程場景
- 既有 SSE bridge 接線的資產價值得以顯現，無需新增架構
- 模型規模警告可在安裝階段預先阻斷可預期的失敗

**負面影響 / 技術債：**
- 連接模式由 2 種增為 3 種，設定選單與文件維護成本略增
- 不自動安裝 Ollama 或拉取模型（刻意排除，避免隱式觸發數十 GB 下載），使用者需自行準備執行環境
- 模型規模警告採用 tag 字串解析（如 `qwen2.5:32b` → 32），對不含規模資訊的自訂 tag 無法判斷，僅能略過警告
- Tier B 缺口在硬體不足時仍然存在，須待後續決策

**後續追蹤：**
- [ ] 實測本地 MCP client 連接既有 SSE 端點，確認可列出並呼叫 GhidraMCP 工具（此為本 ADR 核心假設，若不成立須重新評估）
- [ ] 取得專案負責人硬體規格（GPU/RAM），判定是否需啟動 Tier B（選項 B）
- [ ] 更新 README 與 `docs/architecture.md` 為三層定位，移除 WSL2 賣點論述

---

## 關聯（Relations）

- 取代：（無）
- 被取代：（無）
- 參考：
  - ADR-001（初始技術棧選型）— 本 ADR 修正其 MCP 連接模式僅限 CLI / API Key 的假設，並調整 WSL2 專門化的定位
  - SPEC-003（GhidraMCP 插件整合）
  - `scripts/setup_mcp.sh` — `setup_mcp_configure_connection()`、launcher SSE 啟動段落
