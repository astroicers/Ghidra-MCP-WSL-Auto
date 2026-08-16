# 端到端實測指南（Tier A：離線 agentic）

本文件用於驗證**離線 agentic 分析鏈路是否真的可運作**：從本地模型出發，經 MCP client → SSE Bridge → Ghidra 插件，最終成功呼叫工具並取得分析結果。

> **為什麼需要這份文件**
> `MCP_MODE=local` 的設計前提是「MCP Bridge 的 SSE 端點與 client 無關，任何支援 SSE 的 client 皆可連接」。此前提**尚未經實機驗證**（見 [ADR-002](adr/ADR-002-offline-tiering-and-client-agnostic-mcp-mode.md) 待追蹤事項）。本文件即為驗證程序；完成後請依 [§13](#13-回填驗證結果) 回填結論。

鏈路全貌：

```
ollmcp (本地模型)  ──SSE──▶  MCP Bridge :60006  ──HTTP──▶  Ghidra 插件 :60005  ──▶  Ghidra 中已開啟的 program
```

任一環節斷裂，症狀往往都表現為「工具呼叫沒有回應」，因此**請依序驗證，不要跳步**。

---

## 1. 依硬體選擇模型

**先做這一步。** 選錯模型會在 §3 卡住（磁碟／記憶體不足），或在 §12 得到「連線正常但 agent 一直失敗」的誤導結果。

| 可用 VRAM / RAM | 建議模型 | agentic 可用性 |
|-----------------|----------|----------------|
| 32GB+ | `qwen2.5:32b` | 建議值，最穩定 |
| 24GB | `qwen2.5-coder:14b` | 可用，達門檻 |
| < 24GB | — | **多步 tool calling 不可靠**，見下方說明 |

模型需與 Ghidra 共存於同一台機器，兩者皆吃記憶體。必要時以 `GHIDRA_XMX` 調低 Ghidra 的 JVM 上限讓出空間：

```bash
sudo GHIDRA_XMX=4096 ./install.sh
```

> **小模型不是「效果較差」，是會直接失敗。**
> 3B 級模型的 tool 初始化失敗率約 **89%**，32B 級約 **0%**；且誤差會複利累積（每步 95% 成功 × 8 步 ≈ 66% 整體成功）。
> 若硬體低於門檻，本鏈路的 §12 預期會失敗——這是**模型能力限制，不是安裝錯誤**，請改走雲端模式（Tier C）。

---

## 2. 安裝並啟動 Ollama

```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama serve          # 若非以 systemd 服務執行，需保持此終端開著
```

**驗證：**

```bash
curl -s http://127.0.0.1:11434/api/tags
```

| 結果 | 判讀 |
|------|------|
| 回傳 JSON（如 `{"models":[...]}`） | ✅ 通過 |
| `Connection refused` | daemon 未啟動 → 執行 `ollama serve` |
| 指令不存在 | 安裝失敗 → 重跑安裝指令 |

---

## 3. 下載模型

```bash
ollama pull qwen2.5:32b
```

**注意磁碟空間**：32B 量化後約 20GB，14B 約 10GB。先確認 `df -h ~`。

**驗證：**

```bash
ollama list | grep qwen2.5
```

模型名稱出現即通過。下載中斷可重跑 `ollama pull`，支援續傳。

---

## 4. 安裝 MCP client

套件與指令名皆為 **`ollmcp`**（`mcp-client-for-ollama` 是 repo 名稱，不是套件名）：

```bash
uv tool install --upgrade ollmcp
# 或
pip install --upgrade ollmcp
# 或免安裝試跑
uvx ollmcp
```

**驗證：**

```bash
ollmcp --help
```

顯示說明文字即通過。應可看到 `--mcp-server-url` / `-u` 與 `--model` / `-m` 旗標。

---

## 5. 啟用 GhidraMCP 插件（首次啟動必經）

> **這是最常見的卡關點。** 首次啟動時 Ghidra 的 tool config 尚未產生，launcher 的 port 自動設定**必然失敗**並印出警告——這是預期行為，不是錯誤。

```bash
ghidra-mcp        # 首次啟動
```

在 Ghidra 中：

1. **File → Configure → Developer** → 勾選 **GhidraMCPPlugin**
2. **完全關閉 Ghidra**
3. 再次執行 `ghidra-mcp`（此時 launcher 才能成功 patch port）

**驗證：** 第二次啟動時應看到

```
[OK] Ghidra 插件 port 已自動設定為 60005
```

若仍失敗，手動設定：**Edit → Tool Options → GhidraMCP HTTP Server → Server Port: 60005**

---

## 6. 載入待分析的二進位檔

> **極易遺漏，且失敗症狀具誤導性。**
> GhidraMCP 的工具是針對「**當前開啟的 program**」運作的。若 Ghidra 沒有開啟任何檔案，工具會回傳空結果或錯誤——看起來很像連線失敗，實際上連線完全正常。

在 Ghidra 中建立專案並匯入任一二進位檔（`/bin/ls` 之類的系統執行檔即可用於測試），**完成初始 auto-analysis 後**再繼續。

---

## 7. 驗證 Ghidra 插件 HTTP Server

```bash
curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:60005/
```

| 結果 | 判讀 |
|------|------|
| 任何 HTTP 狀態碼 | ✅ 插件 HTTP server 存活 |
| `Connection refused` | 插件未啟用或 port 不符 → 回到 §5 |

---

## 8. 驗證 Bridge SSE 端點

一鍵檢查（涵蓋 §2、§3、§8 與模型規模）：

```bash
./install.sh --check-offline
```

**預期輸出：**

```console
[INFO ] === 離線就緒自檢 ===
[OK   ] 已載入設定: /opt/ghidra-mcp/GhidraMCP/.env (MCP_MODE=local)
[OK   ] Ollama daemon 運行中: http://127.0.0.1:11434
[OK   ] 模型已就緒: qwen2.5:32b
[OK   ] 模型 qwen2.5:32b 約 32B，符合 agentic 門檻（≥ 14B）
[OK   ] MCP SSE 端點可連接: http://127.0.0.1:60006/sse
[OK   ] 離線就緒檢查通過，可執行離線 agentic 分析
```

任一項為 `[ERROR]` 時，輸出會直接附上修復指令。

---

## 9. 連接並列出工具 —— 核心判定點

> **這一步即 [ADR-002](adr/ADR-002-offline-tiering-and-client-agnostic-mcp-mode.md) 核心假設的成立與否。**

保持 `ghidra-mcp` 在另一個終端執行中，然後：

```bash
ollmcp --mcp-server-url http://127.0.0.1:60006/sse --model qwen2.5:32b
```

在 ollmcp 介面中列出可用工具（依版本可能為 `tools` 指令或啟動時自動顯示）。

| 結果 | 判讀 |
|------|------|
| 列出 GhidraMCP 工具（`decompile_function`、`list_functions` 等） | ✅ **核心假設成立** |
| 連上但工具列表為空 | Bridge 未正確代理到插件 → 檢查 §7 |
| 無法連線 | SSE 端點問題 → 回到 §8 |

---

## 10. 實際呼叫單一工具

連線成功不等於可用。請實際觸發一次工具呼叫，例如要求列出當前 program 的函式：

```
列出目前開啟的程式中的所有函式
```

| 結果 | 判讀 |
|------|------|
| 回傳函式清單 | ✅ **端到端成立** |
| 回傳空清單或錯誤 | 多半是 Ghidra 未開啟檔案 → 回到 §6 |

---

## 11. 多步 agentic 驗證

單次呼叫成立後，測試真正的價值所在——**跨函數的多步任務**（這是 Tier A 相對於單次分析工具的核心優勢）：

```
找出 main 函式，反編譯它，接著追蹤它呼叫的每一個函式並說明整體行為
```

| 結果 | 判讀 |
|------|------|
| 完成多步串聯並產出連貫說明 | ✅ **Tier A 完全成立** |
| 前一兩步正常，之後開始亂呼叫或放棄 | 模型能力不足（見 §1），非安裝問題 |

---

## 12. 疑難排解對照表

| 症狀 | 可能原因 | 處理 |
|------|----------|------|
| 工具列表為空 | Ghidra 未開啟任何 program | §6 匯入並完成分析 |
| `Connection refused` (60005) | 插件未啟用 | §5 啟用 GhidraMCPPlugin 後重啟 |
| `Connection refused` (60006) | Bridge 未啟動 | 確認 `ghidra-mcp` 執行中且無 port 衝突 |
| `Port 60006 已被佔用` | 殘留行程或其他服務 | `ss -tlnp \| grep :60006`；或改 `.env` 的 `MCP_SERVER_PORT` |
| port 自動設定失敗 | 首次啟動，tool config 未生成 | §5 為預期行為，啟用插件後重啟即可 |
| 工具呼叫格式錯誤、參數亂填 | 模型規模不足 | §1 換用 ≥14B 模型，或改走 Tier C |
| 多步任務中途放棄 | 同上（誤差複利） | 同上 |

---

## 13. 回填驗證結果

完成後請更新 [ADR-002](adr/ADR-002-offline-tiering-and-client-agnostic-mcp-mode.md) 的「後續追蹤」區塊：

**若 §9 與 §10 通過** — 核心假設成立，勾選：

```markdown
- [x] 實測本地 MCP client 連接既有 SSE 端點，確認可列出並呼叫 GhidraMCP 工具
```

**若 §9 或 §10 失敗** — 核心假設不成立，`MCP_MODE=local` 的設計前提需重新評估。請記錄實際失敗環節與錯誤訊息，並在 ADR-002 補充後果說明；此情況下應考慮修正 Bridge 設定或改採其他 client。

**若僅 §11 失敗**（§9、§10 皆通過）— 鏈路成立但**模型能力不足**。此為已知限制（Tier B 缺口，已記於 [`architecture.md`](architecture.md) 技術債），非本鏈路缺陷。

---

## 附錄：各元件參考

| 元件 | 專案 | 本專案使用方式 |
|------|------|----------------|
| Ghidra | [NationalSecurityAgency/ghidra](https://github.com/NationalSecurityAgency/ghidra) | 安裝至 `/opt/ghidra`（known-good：11.3.2） |
| GhidraMCP | [LaurieWired/GhidraMCP](https://github.com/LaurieWired/GhidraMCP) | 插件（HTTP :60005）+ Bridge（FastMCP，SSE :60006/sse） |
| ollmcp | [jonigl/mcp-client-for-ollama](https://github.com/jonigl/mcp-client-for-ollama) | MCP client，支援 STDIO / SSE / Streamable HTTP 與 agent mode |
| Ollama | [ollama.com](https://ollama.com) | 本地模型執行環境（預設 :11434） |
