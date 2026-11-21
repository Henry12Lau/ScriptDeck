你是一位資深 macOS 工程師及產品設計師。請根據以下規格，
開發一個可以在本機編譯和使用的 macOS app。

不要只提供概念或 pseudocode；請建立完整專案、實作核心功能，
並提供編譯及使用說明。

# 1. 產品名稱

ScriptDeck

Tagline:
Your scripts. One deck.

# 2. 產品目的

使用者目前會在多個 Terminal 視窗執行不同用途的本地 script。

ScriptDeck 提供一個輕量 macOS dashboard，讓使用者可以：
- 新增及儲存 script 設定
- 在同一畫面查看所有 script 的執行狀態
- 個別 Start / Stop script
- 修改及移除設定

它是本地 script 控制介面，不是 terminal emulator、
log viewer、排程系統或完整 process supervisor。

# 3. 技術方向

- macOS 原生 app
- Swift + SwiftUI
- Foundation Process 管理由 app 啟動的程序
- 不使用 Electron、WebView 或本地 web server
- 使用穩定版 SDK，明確列出最低支援 macOS 版本
- 以本機個人使用為目標，第一版不以 Mac App Store 上架為前提
- 清楚說明 sandbox 設定及本地檔案執行權限的取捨
- 不要求 sudo，不儲存管理員密碼

# 4. 產品範圍

必須包含：
1. Script 清單
2. Add script
3. Edit script
4. Remove script
5. Start / Stop
6. 執行狀態
7. 本次執行時間
8. 設定持久化
9. 簡單且清楚的啟動失敗訊息

不包含：
- Log viewer
- stdout / stderr 歷史紀錄
- Terminal 視窗
- 排程
- 自動重啟
- 雲端同步
- 遠端執行
- AI 功能
- CPU / RAM 圖表
- 全域快捷鍵
- Menu-bar 模式
- 將既有 Terminal 程序自動匯入或接管

# 5. UI 設計規格

請按以下 wireframe 及設計規格實作。
不要自行改成 menu-bar app、sidebar app 或 terminal 介面。

## 5.1 整體風格

產品名稱：ScriptDeck

介面語言：
- 第一版使用英文

風格：
- 簡潔的 macOS 原生深色 dashboard
- 單一窗口
- 無 sidebar
- 無 tab
- 無 log panel
- 無圖表
- 無漸層、玻璃特效或大型裝飾
- 使用系統字體及 SF Symbols
- 保留標準 macOS 左上角關閉、最小化、放大按鈕
- 不要以自繪圓點代替系統窗口按鈕

窗口：
- 初始尺寸：960 × 620 pt
- 最小尺寸：780 × 460 pt
- 允許縮放
- 主內容距離窗口邊緣約 28 pt
- Script 清單可以垂直捲動
- Header 固定，不隨清單捲動

## 5.2 主畫面 Wireframe

以下為結構示意，不代表使用等寬字體：

┌──────────────────────────────────────────────────────────────────────────┐
│  ● ● ●                       ScriptDeck                                  │
│                                                                          │
│  Your scripts. One deck.                               [ + Add script ]  │
│  2 running · 1 stopped · 1 failed                                         │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ ● Data sync              Running        00:24:18  [ Stop  ] [ ··· ] │  │
│  │   python3 sync.py                                                  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ ● Odds watcher           Running        01:12:06  [ Stop  ] [ ··· ] │  │
│  │   node watcher.js                                                  │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ ● Report builder         Stopped             —   [ Start ] [ ··· ] │  │
│  │   python3 report.py                                                │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
│  ┌────────────────────────────────────────────────────────────────────┐  │
│  │ ● Model pipeline         Failed          00:02:41 [ Start ] [ ··· ] │  │
│  │   zsh run-model.sh        Exit code 1                               │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘

注意：
- 範例資料只用於 SwiftUI Preview，不要預先加入真實使用者清單。
- 不顯示 script output。
- 「Exit code 1」是程序結束狀態，不是 log。
- 不需要底部 footer 或「Local / macOS」字樣。

## 5.3 配色

以以下顏色作為 Dark theme 的設計基準：

Window background：
#1B1E26

Script row background：
#252933

Row hover background：
#2B303C

Primary text：
#E9EDF5

Secondary text：
#969EAF

Running：
#48D6A0

Stopped：
#969EAF

Failed：
#FF8585

Starting / Stopping：
#E8B96A

Start button background：
#326DE6

Start button text：
#FFFFFF

Stop button background：
#374153

Stop button text：
#E9EDF5

優先確保文字可讀性、鍵盤焦點及 disabled 狀態清楚。
狀態必須同時使用文字及顏色，不可只靠顏色區分。

## 5.4 Header

左側：
- Title: Your scripts. One deck.
- 字體約 28 pt，semibold
- Subtitle 字體約 13 pt，secondary color
- Title 與 Subtitle 間距約 6 pt

右側：
- + Add script
- 使用 plus SF Symbol 加文字
- 高度約 36 pt
- 圓角約 8 pt
- 不使用過度鮮艷的主色，讓 Start 按鈕保留辨識度

Subtitle：
- 依實際狀態計算數量
- 只顯示數量非零的類別
- 排序：
  running · starting · stopping · stopped · failed
- 正確處理單複數
- 沒有 script 時不顯示摘要

Header 與第一個 row 間距約 24 pt。

## 5.5 Script Row

每行：
- 高度至少 84 pt
- 圓角約 12 pt
- 水平 padding 約 18 pt
- 垂直 padding 約 14 pt
- 行與行之間約 12 pt
- 無厚重邊框及陰影

使用以下欄位分配：

A. Script 資訊
- 吸收剩餘可用寬度
- 狀態點：約 8 pt
- 名稱：約 16 pt，medium
- 名稱下方顯示 command summary
- Command summary：約 12 pt，secondary color
- 長名稱及長指令單行截斷，不推走右側按鈕

B. 狀態
- 約 112 pt 寬
- 文字約 13 pt
- Failed 時可在下方顯示 Exit code N
- 啟動失敗時顯示簡短原因，例如：
  Executable not found
- 長錯誤截斷，點擊可查看完整系統錯誤描述

C. 執行時間
- 約 82 pt 寬
- 右對齊
- 使用 monospaced digits，避免時間跳動造成位移
- 格式 HH:MM:SS
- 從未執行顯示 —
- 結束後保留本次 duration

D. 操作
- Start / Stop 按鈕固定寬度約 72 pt
- 高度約 32 pt
- 圓角約 8 pt
- 按鈕尺寸不可隨狀態改變

E. More menu
- 使用 ellipsis SF Symbol
- 可點擊區域約 32 × 32 pt
- Menu items：
  Edit…
  Remove…
- 執行中不可 Edit 或 Remove，對應項目 disabled

不同 row 的狀態、時間及按鈕必須垂直對齊。
請使用共享欄寬或 Grid 實作，不要讓每行自行計算欄位位置。

## 5.6 狀態互動

Stopped：
- 灰點
- Stopped
- 藍色 Start 按鈕

Running：
- 綠點
- Running
- 深灰色 Stop 按鈕

Failed：
- 紅點
- Failed
- 藍色 Start 按鈕
- 可顯示 exit code 或簡短啟動錯誤

Starting：
- 暖黃色狀態
- Starting…
- 原操作按鈕區域顯示小型 spinner
- 該 row 禁止重複啟動

Stopping：
- 暖黃色狀態
- Stopping…
- 原操作按鈕區域顯示小型 spinner
- 該 row 禁止重複停止

不要使用 Pause 圖示。
Stop 與 Pause 不同，UI 必須清楚寫 Stop。

Row hover：
- 僅輕微改變背景
- 不觸發 Start / Stop
- 點擊 row 空白處不執行任何 script

## 5.7 Command Summary

主畫面的 command summary 由 executable 與 arguments 產生。

例如：
/Users/me/project/.venv/bin/python
/Users/me/project/sync.py

可簡化顯示為：
python sync.py

要求：
- Hover 顯示完整 executable 與 arguments
- 顯示用字串不得拿來重新解析或執行
- 真正執行永遠使用結構化 executablePath + arguments
- 不在 tooltip 顯示 environment variable values

## 5.8 Add Script Sheet

點擊 + Add script 後，在主窗口顯示 sheet。

建議寬度約 580 pt。
內容可捲動，底部操作列固定。
Advanced 展開後不可超出可用螢幕高度。

Wireframe：

┌───────────────────────────────────────────────────────────┐
│  Add script                                               │
│  Configure a local script to run from ScriptDeck.          │
│                                                           │
│  Name                                                     │
│  ┌─────────────────────────────────────────────────────┐  │
│  │ Data sync                                           │  │
│  └─────────────────────────────────────────────────────┘  │
│                                                           │
│  Executable                                               │
│  ┌───────────────────────────────────────┐ ┌───────────┐  │
│  │ /Users/me/project/.venv/bin/python     │ │ Choose…   │  │
│  └───────────────────────────────────────┘ └───────────┘  │
│                                                           │
│  Arguments                                                │
│  ┌─────────────────────────────────────────────┐ [↑][↓][−]│
│  │ /Users/me/project/sync.py                    │           │
│  └─────────────────────────────────────────────┘           │
│  ┌─────────────────────────────────────────────┐ [↑][↓][−]│
│  │ --interval                                  │           │
│  └─────────────────────────────────────────────┘           │
│  ┌─────────────────────────────────────────────┐ [↑][↓][−]│
│  │ 60                                          │           │
│  └─────────────────────────────────────────────┘           │
│  + Add argument                                           │
│                                                           │
│  Working directory                                        │
│  ┌───────────────────────────────────────┐ ┌───────────┐  │
│  │ /Users/me/project                     │ │ Choose…   │  │
│  └───────────────────────────────────────┘ └───────────┘  │
│                                                           │
│  ▸ Advanced                                               │
│                                                           │
│                                  [ Cancel ] [ Add script ]│
└───────────────────────────────────────────────────────────┘

表單要求：
- 清晰的 label 與輸入框層級
- 欄位組之間約 16 pt 間距
- 路徑可以手動輸入或透過 picker 選擇
- Arguments 每行一個字串
- 提供新增、刪除及上移／下移操作
- 第一行不可上移，最後一行不可下移
- 空 argument 清單亦有效
- 不要自動修剪 argument 值內有意義的空白
- Cancel 關閉表單但不儲存
- Add script 驗證成功後儲存並關閉
- 有錯誤時保留已填內容並顯示欄位錯誤
- 第一次開表單不要立即顯示一堆 required errors

Advanced：
- 預設收合
- 展開後顯示 Environment variables
- 每行 Key / Value / Remove
- 提供 + Add variable
- 顯示提示：
  Values are stored in plain text on this Mac.

## 5.9 Edit Script Sheet

沿用 Add script 相同表單。

差異：
- Title: Edit script
- 預先填入現有設定
- 主要按鈕：Save changes
- Cancel 不改動原設定
- 僅允許非執行中 script 開啟編輯

## 5.10 Remove Confirmation

選擇 Remove… 後顯示原生確認 alert：

Title:
Remove “{script name}”?

Message:
This removes the configuration from ScriptDeck.
The original script file will not be deleted.

Buttons:
Cancel
Remove

Remove 使用 destructive style。

## 5.11 Empty State

沒有 script 時：

┌───────────────────────────────────────────────────────────┐
│                                                           │
│                       No scripts yet                      │
│                                                           │
│             Add a local script to get started.            │
│                                                           │
│                     [ + Add script ]                      │
│                                                           │
└───────────────────────────────────────────────────────────┘

- 保留頁首 Your scripts. One deck.
- 中央顯示上述 empty state
- 不顯示假的 script 資料
- 不需要大型插圖

## 5.12 Quit Confirmation

仍有 script 執行時退出 app，顯示原生 alert：

Title:
Stop scripts and quit?

Message:
Quitting will stop all scripts started by ScriptDeck.

Buttons:
Cancel
Stop & Quit

確認後：
- 進入停止流程
- 不再允許啟動新 script
- 停止完成後退出
- 不立即關閉 app 而留下未處理程序

## 5.13 鍵盤與 Accessibility

- Tab 可以巡覽操作及表單
- 所有 icon-only 按鈕提供 accessibility label
- More menu label 包含 script 名稱
- Start / Stop accessibility label 包含 script 名稱
- 顏色以外必須有狀態文字
- 保留清晰 keyboard focus indicator
- 不加入全域 Enter / Space 直接啟動任意 script 的行為
- 窗口縮小時保持操作按鈕可見，優先截斷名稱與指令

## 5.14 UI 交付及驗收

建立 SwiftUI Previews，覆蓋：
1. Empty
2. 多條 scripts 的混合狀態
3. Starting / Stopping
4. 長名稱與長路徑
5. Add script 表單
6. 表單驗證失敗
7. 最小窗口尺寸

Preview 使用 mock runtime state，
不可因為開啟 Preview 而啟動真實程序。

主畫面驗收：
- 一眼可以看到所有 script 的狀態及 Start / Stop
- 保留 Add script
- 無 log UI
- 欄位對齊
- 無文字重疊
- 最小窗口尺寸仍可操作
- 所有功能按鈕都有真實實作，不能只有外觀

# 6. 狀態模型

支援以下狀態：

Stopped：
- 尚未啟動、正常完成，或由使用者停止
- 可以 Start

Starting：
- 正在啟動
- 禁止重複 Start
- 顯示輕量 loading indicator

Running：
- App 啟動的程序仍然存在
- 可以 Stop

Stopping：
- 已要求停止，正在等待程序退出
- 禁止重複操作
- 顯示輕量 loading indicator

Failed：
- 啟動失敗，或非使用者停止情況下以非零 exit code 結束
- 可以重新 Start
- 顯示簡短 failure reason 或 exit code
- 不顯示 stdout / stderr

狀態必須來自實際程序事件，不可只在按鈕點擊後切換 UI。

Running 僅代表程序仍在執行，
不代表 script 已完成初始化、網絡連線正常或工作有進展。

UI 不使用 Pause / Resume。
Stop 後再次 Start，代表重新執行，不是由中間繼續。

# 7. 操作按鈕

Stopped / Failed：
- 顯示 Start

Running：
- 顯示 Stop

Starting / Stopping：
- 顯示對應處理中狀態
- 暫停該 row 的重複操作

More menu：
- Edit
- Remove

Running / Starting / Stopping 時不可 Edit 或 Remove。
需先停止程序。

不要加入 Start all / Stop all，維持第一版簡潔。

# 8. Add / Edit script 表單

用 sheet 呈現。

欄位：

A. Name
- 必填
- 例如 Data sync

B. Executable
- 必填
- 使用絕對路徑
- 可以輸入或透過檔案選擇器選擇
- 例如：
  /Users/me/project/.venv/bin/python
  /opt/homebrew/bin/node
  /bin/zsh

C. Arguments
- 使用可新增、刪除及排序的 argument 清單
- 每個 argument 是一個獨立字串
- 不要用空白直接 split 一條 command
- 路徑包含空格時仍需正確執行

例子：
Executable:
  /Users/me/project/.venv/bin/python

Arguments:
  /Users/me/project/sync.py
  --interval
  60

另一個例子：
Executable:
  /bin/zsh

Arguments:
  /Users/me/project/run.sh

D. Working directory
- 必填
- 以資料夾選擇器選擇
- 驗證資料夾存在

E. Environment variables
- 放在可展開的 Advanced 區域
- Key / Value 編輯器
- 用作額外環境變數覆寫
- 清楚提示：此處設定會以明文儲存在本機
- 不要聲稱是 secrets vault

表單底部：
- Cancel
- Add script / Save changes

提交前驗證：
- Name 不為空
- Executable 存在且可執行
- Working directory 有效
- Environment key 格式有效
- 驗證失敗時顯示對應欄位錯誤
- 不要在驗證時實際執行 script

不提供任意 shell command 輸入模式。
若使用者需要 pipe、redirect 或多條命令，
請讓使用者自行建立 .sh 檔，再交由 /bin/zsh 執行。

# 9. 執行與環境

- 每個 script 設定同一時間最多一個 instance
- 使用唯一 UUID 辨識設定
- 每次 Start 建立新的 Process instance
- 設定 executableURL、arguments、currentDirectoryURL
- 將 app 環境與使用者指定的環境變數合併
- 不假設 GUI app 環境等同 Terminal
- 不自動載入 ~/.zshrc 或 ~/.zprofile
- 文件說明：如需特定 Python venv，直接指定該 venv 的 interpreter
- PATH 依賴須由使用者設定，或在 script 使用絕對路徑

不需要互動輸入：
- stdin 指向 /dev/null
- 不支援要求輸入密碼、選單或互動 prompt 的 script

不需要 log：
- stdout 與 stderr 指向 /dev/null
- 不建立 log 檔
- 不將 output 累積到記憶體
- 不建立無人讀取的 Pipe
- script 自己寫入檔案的行為不在此限制內

# 10. Stop 行為與子程序

Stop 的設計不能只終止最外層 shell，
而留下由 script 啟動的子程序。

請實作清楚的程序群組或等效程序管理方案：

1. 將每次執行放入可獨立管理的 process group
2. Stop 先對該執行群組發出 SIGTERM
3. 等待約 5 秒
4. 如仍有存活程序，對該執行群組發出 SIGKILL

若 Foundation Process 無法直接滿足所需的 process group 控制，
可加入一個極小的原生 launcher/helper，
但需在專案中完整實作及解釋。

要求：
- 不可只依賴 command 名稱批量 kill
- 不可因為名稱相同而停止其他 Terminal 的程序
- 不可將過去儲存的 PID 當作有效程序直接 kill
- 處理程序恰好已退出的 race condition
- 使用者按 Stop 所造成的結束應記為 Stopped，而非 Failed

限制要清楚：
- 第一版以非互動、foreground scripts 為支援對象
- 不支援自行 daemonize、脫離 process group，
  或透過外部服務啟動長駐工作的 script
- 不要承諾能可靠終止任意第三方程序樹

# 11. 窗口與 App 生命週期

關閉窗口：
- 只隱藏主窗口
- App 繼續運行
- 已啟動 scripts 繼續運行
- 點 Dock icon 可重新開啟主窗口

Quit app：
- 如沒有執行中的 script，直接退出
- 如仍有執行中的 script，顯示：
  Title: Stop scripts and quit?
  Message: Quitting will stop all scripts started by ScriptDeck.
  Buttons: Cancel / Stop & Quit
- Stop & Quit 使用正常停止流程，再退出
- 不提供 Keep scripts running after quit 選項

不要把「窗口關閉」與「App 退出」混為一談。

不承諾 app 被強制結束後仍可管理既有程序。
README 必須說明此限制，不要加入複雜的 crash recovery daemon。

# 12. 執行時間

- Running 時顯示本次 elapsed time
- 格式 HH:MM:SS
- 使用一個共享 timer 更新畫面
- 沒有任何程序執行時停止 timer
- 程序結束後保留本次 duration，直到下次 Start
- 從未執行則顯示 —
- 不透過持續執行 ps 或 shell command 更新狀態

# 13. 設定持久化

儲存位置：
使用 FileManager 取得 Application Support，
在 ScriptDeck 子資料夾儲存 JSON。

資料結構至少包含：
- id
- name
- executablePath
- arguments: [String]
- workingDirectory
- environment: [String: String]

要求：
- 使用 Codable
- 原子寫入
- 檔案限本機使用者讀寫
- 儲存錯誤必須提示使用者
- 不儲存 Process instance、PID 或 Running 狀態
- 重新開啟 app 後不自動執行 scripts
- 第一版不需要執行歷史

# 14. 錯誤與空狀態

沒有 script：
- Title: No scripts yet
- Description: Add a local script to get started.
- Button: Add script

啟動失敗：
- 該 row 切換為 Failed
- 顯示簡短原因，例如 Executable not found
- 可在點擊錯誤提示後查看系統錯誤描述
- 不顯示 log 或 stderr
- 保留設定供修改

非零退出：
- 顯示 Failed · Exit code N

Stop 失敗：
- 不可假裝已停止
- 顯示實際狀態與錯誤提示

Remove：
- 只移除 app 內設定
- 永遠不刪除原始 script 檔案

# 15. 架構建議

分離以下職責：
- ScriptConfiguration：可儲存設定
- ScriptRuntimeState：執行中狀態
- ScriptStore：載入與儲存
- ProcessManager：啟動、停止、退出事件
- DashboardView
- ScriptRowView
- ScriptEditorView

UI 狀態更新在 MainActor。
檔案操作及程序控制不可長時間阻塞主執行緒。

避免為簡單功能加入過多第三方 dependencies。
優先使用 Apple frameworks。

# 16. 資源要求

以低資源使用為設計目標，而非承諾固定 RAM 數字。

- 不使用 WebView
- 不持續掃描所有系統程序
- 不讀取或渲染 log
- 不累積 script output
- 優先使用 termination callback 更新狀態
- 只在有程序執行時更新 elapsed time
- 不加入持續動畫
- 不對 UI 狀態變化做不必要的磁碟寫入

完成後提供量度方式：
- 比較 app idle 與執行多條 script 時的資源
- 將 GUI app 與 script 子程序的資源分開報告
- 只報告實測數字，不虛構 benchmark

# 17. 驗收條件

1. 可以新增 Python、Node、shell script 的執行設定。
2. 檔案路徑包含空格時仍可執行。
3. 可以同時執行多條不同 script。
4. 同一條 script 不可重複啟動。
5. Start 後 UI 反映真實程序狀態。
6. Stop 能停止受支援的 foreground script 及其程序群組。
7. 正常完成顯示 Stopped。
8. 非零退出顯示 Failed 與 exit code。
9. 使用者主動 Stop 不顯示 Failed。
10. 關閉窗口後 script 繼續執行。
11. Quit 時正確處理執行中的 scripts。
12. 重新開 app 後設定仍存在，但不會自動啟動 scripts。
13. 沒有 log UI、log 檔或無限 output buffer。
14. 移除設定不影響原始檔案。
15. App 不影響其他 Terminal 啟動的同名程序。

# 18. 交付要求

請提供：
- 可編譯的完整 macOS 專案
- 清晰的檔案結構
- 核心程序管理實作
- UI 與設定持久化
- 基本單元測試
- 用於手動驗收的小型測試 scripts：
  - 持續運行
  - 正常完成
  - 非零退出
  - 啟動 foreground 子程序
  - 持續大量 stdout / stderr
- README：
  - Build / Run 步驟
  - 新增 Python / Node / shell script 範例
  - 環境變數與 PATH 說明
  - Stop / Quit 行為
  - 支援範圍與限制

請先簡述實作計劃及任何重要技術取捨，再開始建立專案。
避免自行加入規格以外的功能。