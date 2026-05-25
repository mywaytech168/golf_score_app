# 球追蹤算法三版差異分析

> 比較對象：`ball_tracking_no_cnn_stable_21.py` / `trajectory_tracker_v3_stable.py` / Flutter `ball_tracker.dart`

---

## 1. 架構層（最大差異）

| 項目 | v21 Python | v3 Python (stable) | Flutter (Dart) |
|------|-----------|-------------------|----------------|
| **Blob 偵測位置** | Python / OpenCV 直接處理像素 | Python / OpenCV 直接處理像素 | Kotlin 原生層 → MethodChannel → Dart 決策 |
| **影像前處理** | medianBlur + bilateralFilter | medianBlur + bilateralFilter | Kotlin 端執行（Dart 不處理像素） |
| **輸出** | 直接寫 mp4（VideoWriter） | 直接寫 mp4（VideoWriter） | 呼叫 `renderOverlay` 由 Kotlin 疊圖 |
| **後處理 Smooth** | 無 | 無 | **有**：3 點移動平均消除雜訊 |

---

## 2. ROI 策略

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **ROI 大小** | 隨時間縮小（200 → 80 px） | 固定 400 px | 固定比例（影像寬 37% / 高 21%） |
| **ROI 中心（追蹤中）** | 跟隨 Kalman smooth EMA | 鎖定最後一個有效點 | 鎖定最後一個有效點 |
| **Miss 時 ROI 中心** | 無特別處理 | Kalman 預測中心 + 逐幀擴大 35 px | Kalman 預測中心 + 逐幀擴大 35 px |
| **Miss 時 ROI 最大值** | — | 420 px | 200 px（比例換算） |

---

## 3. 狀態機

| 狀態 | v21 | v3 | Flutter |
|------|-----|----|---------|
| `WAIT_P0` | ✅ | ✅ | ✅ |
| `WAIT_P1` | ✅ | ✅ | ✅ |
| `TRACKING` | ✅ | ✅ | ✅ |
| `TRACK_STOPPED` | ❌（無此狀態，直接 break） | ✅ | ✅ |
| **hitSec 時間窗口** | ❌ | ❌ | ✅（只在 `[hitSec−1s, hitSec+2s]` 搜尋 P0） |

---

## 4. P0 / P1 選取規則

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **P1 方向限制** | **必須在 P0 左側** `x < p0.x − 3` | 無限制 | 無限制，只要距離 > 3 px |
| **P1 Deadline** | 1 幀 | 1 幀 | **3 幀**（更寬鬆） |
| **P0 誤判 Reset** | ✅ | ✅ | ✅ |
| **STRICT_Y_DIRECTION** | **True（硬編碼）** | False | False |

---

## 5. 追蹤候選選取

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **候選 pool 方向** | **必須在上一點左側** `x < lastX − 3` | 無方向限制 | 無方向限制 |
| **Y 方向過濾** | 有（Y_TOL=1, STRICT=**True**） | 有（Y_TOL=1, STRICT=False） | 有（Y_TOL=1, STRICT=False） |
| **Y_MAX_STEP** | 80 px | 80 px | 80 px |
| **候選評分** | 只用距離 Kalman 最近 | 只用距離 Kalman 最近 | **距離 − 0.15 × diffMean**（高對比優先） |
| **候選太多（≥4）** | 用 Kalman 藍點代替 | 用 Kalman 藍點代替 | 用 Kalman 藍點代替 |
| **超多候選停止（≥25）** | ❌ | ✅ | ✅ |

---

## 6. 步長守衛（USE_STEP_DIST_GUARD）

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **啟用** | ❌ | ✅ | ✅ |
| **STEP_EMA_ALPHA** | — | 0.25 | 0.25 |
| **STEP_GROWTH_FACTOR** | — | 1.9 | 1.9 |
| **STEP_ABS_MAX** | — | 140 px | 140 px |
| **STEP_ABS_HARD_MAX** | — | **130 px** | **200 px**（更寬鬆） |
| **PRED_DIST_HARD_MAX** | — | **170 px** | **250 px**（更寬鬆） |
| **Outlier strikes 凍結** | ❌ | 8 次 | 8 次（且需 ≥8 個軌跡點） |

---

## 7. 遠球自適應（FAR_ADAPTIVE）

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **啟用** | ❌ | ✅ | ✅ |
| **Miss 時放寬 area** | — | 依 miss_count 逐步放寬 | 依 miss_count 逐步放寬 |
| **Miss 時放寬 circ** | — | FAR_CIRC_FLOOR = 0.35 | FAR_CIRC_FLOOR = 0.35 |
| **Miss 時放寬 diff** | — | FAR_DIFF_FLOOR = 3 | Kotlin 端處理 |
| **area EMA（追蹤球大小）** | ❌ | ✅（alpha=0.20） | ✅（alpha=0.20） |
| **少候選上限** | — | FAR_FEW_CANDS_MAX = 3 | 3 |

---

## 8. 動態偵測參數

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **CFG_SPEED** | **0.6**（較快放鬆） | **0.4**（較慢放鬆） | 0.4 |
| **area_range 下限** | **4** | **6** | **6** |
| **area_range 上限** | 150 | 150 | 150 |
| **circ_thresh base** | 0.60 | 0.60 | **0.55**（更寬鬆） |
| **CIRC_MIN** | 0.60 | 0.60 | 0.45 |
| **diff_thresh base** | 16 | 16 | Kotlin 端設定 |
| **ROI_CFG size_init** | 200 | 500 | 比例換算 |

---

## 9. No-Candidate 停止機制

| 項目 | v21 | v3 | Flutter |
|------|-----|----|---------|
| **Miss 計數** | ❌ | ✅ | ✅ |
| **NO_CAND_PATIENCE** | — | 4 幀 | 4 幀 |
| **Miss 超限行為** | — | `TRACK_STOPPED` | `stopped` |
| **TRACK_FRAMES 上限** | **300 幀**（硬上限） | None（無上限） | — |

---

## 10. Flutter 特有功能

| 功能 | 說明 |
|------|------|
| **hitSec 時間視窗** | P0 搜尋只在 `[hitSec−1s, hitSec+2s]` 範圍，避免揮桿前誤判球桿頭 |
| **軌跡 Smooth** | 3 點移動平均，頭尾保留原始值，消除 blob centroid 高頻雜訊 |
| **ROI 座標歸一化** | 用影像寬/高比例（0.6519, 0.5646）而非固定像素，適應不同解析度 |
| **blueHist 上限** | 只保留最近 10 筆（Python 無上限） |
| **候選評分（diffMean）** | 多候選時加入 `dist − 0.15 × diffMean` 評分，優先選高對比 blob |
| **Kotlin 分工** | 像素偵測在 Kotlin；決策邏輯在 Dart，彼此通過 MethodChannel 傳遞 |

---

## 11. 演化方向總結

```
v21 Python                v3 Python (stable)         Flutter (Dart)
─────────────────────     ──────────────────────     ──────────────────────────
嚴格左側方向規則    →      移除左側限制          →    完全去除方向硬限制
ROI 隨時間縮小      →      固定 ROI              →    比例化 ROI（多解析度）
無步長守衛          →      步長守衛              →    步長守衛（門檻更寬）
無遠球自適應        →      遠球自適應            →    遠球自適應
無 Miss 停止機制    →      Miss 停止機制         →    Miss 停止機制
STRICT_Y = True     →      STRICT_Y = False      →    STRICT_Y = False
OpenCV 直接偵測     →      OpenCV 直接偵測       →    Kotlin 偵測 + Dart 決策
無後處理            →      無後處理              →    3 點 smooth
無時間窗口          →      無時間窗口            →    hitSec 時間窗口
300 幀硬上限        →      無幀數上限            →    由 hitSec+2s 控制
```

**核心演化邏輯**：
- **v21** 依賴球必然向左飛的幾何假設，適合定點固定角度攝影機
- **v3** 移除方向假設，改以步長守衛 + 遠球自適應維持穩定性，適應更多拍攝角度
- **Flutter** 進一步放寬容忍度（HARD_MAX 更大）並加入 hitSec 時間窗口與平滑後處理，以適應行動裝置不同角度、解析度與實時處理需求
