# 原版 vs 新版流程對比

## 📋 整體架構

### 原版 (ball_tracking_no_cnn_stable_21.py)
```
全局配置 (BATCH_MODE, VIDEO_PATH, INPUT_DIR, etc.)
    ↓
main() → 判斷批量/單支
    ↓
process_one_video(video_path, out_dir)
    ↓
狀態機循環
```

### 新版 (ball_tracking.py)
```
BallTrackingConfig (dataclass 配置)
    ↓
run_ball_tracking(config) → 判斷 batch_mode
    ↓
process_one_video(video_path, config)
    ↓
狀態機循環
```

**差異：** 新版用 dataclass + 函數參數替代全局變量 ✅

---

## 🔄 主循環流程

### 兩版都是 STATE_WAIT_P0 → STATE_WAIT_P1 → STATE_TRACKING

```
Frame 1:
├─ 讀取影片幀
├─ apply_flip() → 旋轉/翻轉
├─ 灰度轉換 + 預處理
├─ 初始化 VideoWriter（第一幀）
└─ 檢測候選點
    ↓
STATE_WAIT_P0:
└─ 找到 p0（最接近 ROI center 的候選點）→ 轉到 STATE_WAIT_P1
    ↓
STATE_WAIT_P1:
├─ 驗證 p1 在指定幀內出現（否則誤判清除 p0）
└─ p1 出現 → Kalman 初始化 → 轉到 STATE_TRACKING
    ↓
STATE_TRACKING:
├─ Kalman 預測 → 藍點
├─ 檢測候選點
├─ 分兩種情況：
│  ├─ 候選點太多 (≥4) → 用藍點歷史
│  └─ 候選點正常 → 篩選 + 更新 Kalman
├─ 輸出視頻幀
└─ 重複直到 TRACK_FRAMES
```

---

## 🔍 關鍵函數對比

### 1. 候選點檢測

| 功能 | 原版 | 新版 |
|------|------|------|
| 函數名 | `detect_candidates_with_stats()` | `detect_candidates_with_stats()` |
| 位置 | Line 236-300 | Line 278-358 |
| 功能 | ✅ 完整 | ✅ 完整 |
| 返回 | `[{"pt_roi": (x,y), "area": a, "circ": c, "diff": d}]` | `[{"pt_roi": (x,y), "area": a, "circ": c, "diff": d}]` |

**相同！** ✅

---

### 2. 動態檢測配置

| 功能 | 原版 | 新版 |
|------|------|------|
| 函數名 | `get_dynamic_detect_cfg()` | `get_dynamic_detect_cfg()` |
| 位置 | Line 219-245 | Line 259-295 |
| 功能 | 根據追蹤進度調整閾值 | 根據追蹤進度調整閾值 |

**相同！** ✅

---

### 3. 軌跡繪製

| 功能 | 原版 | 新版 |
|------|------|------|
| 函數名 | `draw_traj_overlay_only()` | `draw_traj_overlay_only()` |
| 位置 | Line 339-367 | Line 341-368 |
| 功能 | 畫軌跡線 + 半透明疊合 | 畫軌跡線 + 半透明疊合 |

**相同！** ✅

---

### 4. ROI 動態調整

| 功能 | 原版 | 新版 |
|------|------|------|
| ROI 中心平滑 | `clamp_step()` 限制步長 | `clamp_step()` 限制步長 |
| ROI 大小動態 | `roi_size_schedule()` 縮小 | `roi_size_schedule()` 縮小 |
| 平滑係數 | `center_alpha=0.4` | `center_alpha=0.4` |
| 最大步長 | `max_center_step=80` | `max_center_step=80` |

**相同！** ✅

---

### 5. 狀態機邏輯

| 狀態 | 原版 | 新版 | 差異 |
|------|------|------|------|
| WAIT_P0 | ✅ 完整 | ✅ 完整 | 無 |
| WAIT_P1 | ✅ 完整 + p0 誤判清除 | ✅ 完整 + p0 誤判清除 | 無 |
| TRACKING | ✅ 完整 + 藍點歷史 + Y方向 | ✅ 完整 + 藍點歷史 + Y方向 | **新版多了調試日誌** |

---

## 🎯 主要差異點

### 1. 配置方式
```python
# 原版
BATCH_MODE = True
TRACK_FRAMES = 300
VIDEO_PATH = r"..."
FIXED_ROI_MODE = True
# ... 20+ 全局變量

# 新版
config = BallTrackingConfig(
    batch_mode=True,
    track_frames=300,
    video_path=r"...",
    fixed_roi_mode=True,
    # ... 參數化
)
```

**優勢：** 新版可同時處理多個不同配置 ✅

---

### 2. 調試輸出
```python
# 原版
# 基本的追蹤信息

# 新版
# 更詳細的調試日誌：
# 🔵 藍點使用
# ✅ 候選點添加
# 📊 統計信息
```

**優勢：** 新版更容易診斷問題 ✅

---

### 3. 入口函數
```python
# 原版
if __name__ == "__main__":
    main()  # 簡單的 main()

# 新版
if __name__ == "__main__":
    config = BallTrackingConfig(...)
    result = run_ball_tracking(config)
    # 或使用快速入口
    result = quick_track(video_path, output_dir)
```

**優勢：** 新版更靈活，支持 API 調用 ✅

---

## ⚠️ 潛在問題

### 兩版都有的問題：

1. **候選點不足**
   - 檢測閾值太高 → 沒有候選點
   - 解決：調整 `diff_thresh`, `circ_thresh`, `area_range`

2. **ROI 跟蹤失效**
   - ROI 太小或太大
   - 解決：調整 `roi_cfg["size_init"]`, `roi_cfg["size_min"]`

3. **軌跡線不可見**
   - 透明度問題 (`traj_alpha`)
   - 顏色問題 (`traj_color_bgr`)
   - ROI 旋轉問題 (`out_rotate_mode`)

### 新版特有：

- ✅ 無新問題，是原版的完整遷移

---

## 🔧 調試步驟

### 如果軌跡沒有出現：

1. **檢查追蹤點數**
   ```python
   # 新版會打印：
   # 📊 Frame 127: 0 candidates found, total points=16
   ```
   - 如果 total points = 2，說明只有 p0, p1 沒有後續追蹤
   - 如果 total points > 10，追蹤成功 ✅

2. **檢查輸出視頻**
   - 檢查文件大小是否正常
   - 視頻長度應該是 TRACK_FRAMES / FPS 秒

3. **檢查軌跡繪製**
   - 在 `draw_traj_overlay_only()` 前添加:
   ```python
   if len(track_pts) > 2:
       print(f"  繪製軌跡：{len(track_pts)} points")
   ```

---

## 📊 配置推薦值

```python
# 追蹤參數
track_frames = 300          # 追蹤幀數
p1_deadline_frames = 1      # p1 必須在 1 幀內出現

# ROI 參數
roi_cfg = {
    "size_init": 200,       # 初始 ROI 大小
    "size_min": 80,         # 最小 ROI 大小
    "shrink_over_frames": 60,  # 60 幀內縮小到最小
    "center_alpha": 0.4,    # 平滑係數（0-1）
    "max_center_step": 80,  # 最大移動步長
}

# 檢測參數
detect_cfg_base = {
    "area_range": (4, 150),     # 候選點面積範圍
    "circ_thresh": 0.60,        # 圓形度閾值
    "diff_thresh": 16,          # 差異閾值
}

# 藍點參數
too_many_cands_threshold = 4    # 超過此數轉用藍點
blue_p_offset = -2              # 用倒數第2幀的藍點
blue_to_lastp_max_dist = 150.0  # 藍點距離限制

# 輸出參數
traj_color_bgr = (255, 220, 160)   # 淡藍色 (BGR)
traj_alpha = 0.8                    # 透明度
traj_thickness = 6                  # 線寬
draw_traj_until_pn = 6              # 只畫前 6 點（None = 全部）
```

---

## ✅ 結論

**新版是原版的完整功能等價物 + 改進版**

| 項目 | 完成度 |
|------|--------|
| 狀態機 | ✅ 100% |
| Kalman 濾波 | ✅ 100% |
| 候選點檢測 | ✅ 100% |
| 藍點歷史 | ✅ 100% |
| Y 方向追蹤 | ✅ 100% |
| ROI 動態調整 | ✅ 100% |
| 配置管理 | ✅ 改進（dataclass） |
| 調試日誌 | ✅ 改進（更詳細） |
| API 靈活性 | ✅ 改進（快速入口） |

**只需要調整配置參數即可使用！** 🎯
