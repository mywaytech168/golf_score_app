# ORVIA 高爾夫揮桿分析 App — 系統架構與功能流程

> 用途：本文件可直接貼給 GPT / Gemini 以生成簡報（PPT）、技術文件或對外說明。
> 末段附「PPT 生成 Prompt」可一鍵套用。

---

## 0. 一句話定位

ORVIA 是一款 **裝置端推論（on-device）** 的高爾夫揮桿分析 App：用手機錄影，
本機即時跑骨架（MediaPipe）與球體偵測（YOLOv8）、自動切片每一桿、判定擊球時刻，
產出發射角/節奏/甜蜜點分析。僅軌跡 JSON 與使用者「主動上傳」的檔案送雲端，**無背景遙測**。

| 項目 | 內容 |
|---|---|
| 前端 | Flutter（iOS + Android），Riverpod 狀態管理，四語系 i18n |
| 原生層 | Android Kotlin / iOS Swift，~17 條 MethodChannel |
| 裝置端 AI | MediaPipe 骨架、YOLOv8 INT8 球偵測(~1.7MB)、Kalman Filter |
| 後端 | .NET 8 API（IIS，站台 ORVIA）+ Google Gemini AI 分析 |
| 資料 | MySQL（雲端）、Backblaze B2（檔案）、sqflite（本機） |
| 金流 | App 內購（訂閱 + 球數包）、AdMob SSV 獎勵 |

---

## 1. 系統總架構（四層）

```
┌─────────────────────────────────────────────────────────────┐
│ FLUTTER APP（iOS / Android）                                  │
│  錄影/SHOT · 歷史切片 · 分析面板 · 獎勵/設定 · i18n 四語系      │
└─────────────────────────────────────────────────────────────┘
            │ MethodChannel × ~17
┌─────────────────────────────────────────────────────────────┐
│ 原生推論層（on-device）                                       │
│  MediaPipe 骨架 · YOLOv8 球偵測 · 擊球判定/切片 · 匯出合成      │
└─────────────────────────────────────────────────────────────┘
            │ HTTPS（使用者主動上傳）
┌──────────────────────────────┬──────────────────────────────┐
│ 後端 .NET 8 API（IIS/ORVIA）  │ 雲端 / 資料                   │
│  Auth · 獎勵/訂閱             │  Backblaze B2 · MySQL · sqflite│
│  AI 分析（Google Gemini）     │                               │
└──────────────────────────────┴──────────────────────────────┘
```

**核心設計原則**
- 推論在裝置端完成（骨架/球皆 on-device），延遲低、隱私佳。
- 球軌跡偵測完全在裝置端（YOLOv8 INT8 + Kalman），無後端運算。
- 雲端只接收：使用者主動上傳的影片/CSV（含診斷 meta.json），AI 教練分析由 Gemini 完成。
- iOS 原生鏡像 Android 演算法，跨平台行為一致。

---

## 2. 主功能流程（端到端）

```
站姿確認(提示音) → 原生擷取 + MediaPipe 推論(錄 mp4 + 骨架 CSV)
   → 即時擊球判定(弧底對位 · 雙手閘門 · 光暈回饋)
   → 偵測模式分流：V1 骨架 / V2 音訊 / V3 混合
   → 自動切片(逐段預覽·勾選·自由切) + 切片音訊評分(甜蜜點 金/藍/灰)
   → 球軌跡偵測(YOLOv8 P0 SAHI + Kalman → 軌跡 JSON)
   → 揮桿分析面板(發射角 · 節奏比 · 飛行時間)
   → [自訂匯出下載：疊圖燒錄·免費版浮水印] / [上傳獎勵：B2→審核→+3 球]
```

**擊球判定關鍵邏輯**：以 live impacts 判桿數，音訊峰值僅在窗內做時間精修；
即時與離線判定一致（`preserveHitSec` 不被離線覆蓋）。

---

## 3. 各區塊架構

### 3.1 Flutter App 層（lib/）
| 區塊 | 數量 | 代表檔案 |
|---|---|---|
| Pages | 25 | main_shell · record/shot · history/player · ai_coach/home · upgrade/login |
| Providers (Riverpod) | 8 | app · auth · user · plan · recording · video · statistics · locale |
| Services | 51 | video_analysis/v3/pipeline · swing_impact_detector · auto_clip · audio_engine · ball_tracker · export_composer · overlay_burn · in_app_purchase · reward · video_server_client |
| Recording | 16 | native_camera_service · live_swing_detector · pose_csv(loader/writer) · skeleton/trajectory painter |
| 橫切 | — | Models · Widgets · l10n(4 ARB) · theme · utils |

### 3.2 原生推論層（MethodChannel × Android/iOS）
| Channel | 用途 | Android(Kotlin) | iOS(Swift) |
|---|---|---|---|
| camera_recorder | 原生錄影+幀擷取 | CameraRecorderChannel + MediaPipeVideoAnalyzer | MediaPipeCameraChannel |
| pose_analyzer | MediaPipe 骨架 | MediaPipePoseHelper | PoseAnalyzerChannel |
| ball_trajectory | YOLOv8 球偵測 | BallYoloDetector / BallBlobExtractor | BallTrajectory / BallYoloDetector |
| skeleton_overlay | 骨架疊圖燒錄 | SkeletonOverlayRenderer(EGL/JNI) | SkeletonOverlayChannel |
| export_composer | 單 pass 元素合成 | ExportComposerRenderer | ExportComposerChannel |
| video_export/trimmer/transcoder | 剪輯·轉碼·下載 | VideoTrimmer/Transcoder/Export | 對應 Channel |
| frame_extractor/golf_analysis | 抽幀·音訊·協調 | VideoFrameExtractor·AudioImpactDetector | FrameExtractor/GolfAnalysisChannel |
| analysis_progress | 進度串流(EventChannel) | progress events | AnalysisProgressSink |
| keep_screen_on/volume/share | 系統整合 | MainActivity 直接處理 | AppDelegate |

> 加速：NativeLib(JNI) 提供 yuvToNv12 / compositeOverlay。
> Channel 前綴混用：新 `com.aethertek.orvia/*`、舊 `com.example.golf_score_app/*`（內部字串，不影響功能）。

### 3.3 後端 .NET 8 API（server/）
| 區塊 | 數量 | 代表 |
|---|---|---|
| Middleware | — | Logging & RateLimit · JWT · Kestrel 600MB |
| Controllers | 8 | Auth · User · Analysis · Admin · Share · Webhook |
| Services | 18 | AuthService · AppleTokenValidator · GolfSwingAnalyzer · Subscription · B2Service · GeminiService · AdMobSsvVerifier |
| 背景 Worker | — | AiCoachWorker（Gemini AI 分析·扣球） |
| 資料層 | 15 entities | EF Core VideoDbContext（User·UserAuth·AnalysisRecord·DatasetUpload·Purchase·Feedback…） |
| 外部整合 | — | MySQL · Backblaze B2 · Google Gemini · Apple/AdMob |

> 部署：IIS（站台 ORVIA，pubxml，MSDeploy/WMSvc，/health 探測 DB）。測試 server.Tests 37/37。

### 3.4 偵測 / 分析管線
| 階段 | 位置 | 內容 |
|---|---|---|
| 骨架 | 裝置端 | MediaPipe 每幀 33 點 → CSV |
| 即時擊球 | 裝置端 | LiveSwingDetector 弧底開火 + 雙手閘門 + 錨點 V4(anchor.json) |
| 音訊精修 | 裝置端 | AudioImpactDetector 峰值僅做時間精修 |
| 自動切片 | 裝置端 | SwingAutoClip 8 階段 · preserveHitSec · detect_log |
| 球軌跡 | 裝置端 | YOLOv8 INT8 · P0 SAHI + Kalman → 軌跡 JSON |
| 評分/統計 | 裝置端 | ClipAudioScore(甜蜜點) · SwingStats(發射角/節奏/飛行時間) |
| AI 教練 | 後端 | Google Gemini：ONNX 揮桿錯誤分類 + 語意建議（唯一後端分析） |

---

## 4. 資料流摘要

1. **錄影** → 本機產出 `swing.mp4` + `pose CSV` + `audio.wav`。
2. **切片** → 每桿一個 session 資料夾（含 anchor.json / detect_log.txt / phases.json）。
3. **本機儲存** → sqflite（RecordingHistoryEntry，含備註/平台來源）。
4. **上傳（使用者主動）** → B2 presigned PUT（影片+CSV+meta.json）。
   - 路徑 A：上傳獎勵（dataset/，審核制，核准 +3 球）
   - 路徑 B：AI 分析（ai_coach/，後端 Gemini AI 分析）
5. **回傳** → AI 教練建議（球軌跡/統計已在裝置端產出，不經後端）。

---

## 5. 技術亮點（給簡報用 bullet）

- 全鏈裝置端推論，低延遲、保護隱私，無背景遙測。
- 即時擊球弧底對位 + 雙手握桿判定 + 錨點 V4，準確標記觸球瞬間。
- 即時與離線判定一致化（preserveHitSec）。
- 單 pass 匯出合成（軌跡/骨架/浮水印/光暈一次燒錄，畫質只損一次）。
- 跨平台 iOS/Android 演算法鏡像，行為一致。
- 後端精簡：唯一分析職責為 Gemini AI 教練（AI 扣球失敗回滾、/health 探測 DB）。
- 變現：訂閱（月/年）+ 球數包 + AdMob SSV 獎勵 + 上傳審核獎勵。

---

## 6. PPT 生成 Prompt（複製給 GPT / Gemini）

```
你是資深技術簡報設計師。請根據以下「ORVIA 高爾夫揮桿分析 App」的架構資料，
產出一份 12–15 頁的技術簡報大綱，每頁含：標題、3–5 條要點、建議視覺（圖表/流程/架構圖）。
語言：繁體中文，技術術語保留英文。風格：簡潔、專業、適合對技術主管簡報。

頁面建議：
1. 封面與一句話定位
2. 產品概觀與核心價值（on-device、隱私、即時）
3. 系統總架構（四層：Flutter / 原生推論 / 後端 / 雲端）
4. 主功能端到端流程
5. Flutter App 層（Pages/Providers/Services/Recording）
6. 原生推論層（MethodChannel × Android/iOS 對應表）
7. 偵測管線（骨架→擊球判定→切片→球軌跡→分析）
8. 擊球判定演算法（弧底對位/雙手/錨點 V4）
9. 後端 .NET 8（Controllers/Services/Worker/EF Core）
10. 後端 Gemini AI 教練（唯一後端分析職責）
11. 資料流與儲存（B2/MySQL/sqflite，上傳兩路徑）
12. 技術亮點與韌性設計
13. 變現模式（訂閱/球數包/獎勵）
14. 部署與測試（IIS、測試覆蓋）
15. 結語 / Roadmap

請在需要圖的頁面，附上可用 Mermaid 或 PlantUML 描述的圖碼。

[在此貼上本文件第 1–5 節內容]
```

---

*資料來源：D:\Projects\golf_score_app 實際程式碼結構盤點（lib/ · android/ · ios/ · server/ · python/）。*
