# 參數一致性檢查

## 🔴 發現的差異

### 1. **Kalman Filter 參數** ⚠️ 【重要】

| 參數 | 原版 | 新版 | 差異 |
|------|------|------|------|
| `process_pos_var` | 3.0 | 1.0 | ❌ 不一致 |
| `process_vel_var` | 120.0 | 4.0 | ❌ 不一致 |
| `meas_var` | 10.0 | 2.0 | ❌ 不一致 |

**原版代碼位置：** line 284-287
```python
@dataclass
class KFParams:
    dt: float
    process_pos_var: float = 3.0
    process_vel_var: float = 120.0
    meas_var: float = 10.0
```

**新版代碼位置：** line 118-122
```python
@dataclass
class KFParams:
    dt: float = 0.033
    process_pos_var: float = 1.0
    process_vel_var: float = 4.0
    meas_var: float = 2.0
```

---

### 2. **檢測配置** ⚠️ 【重要】

| 參數 | 原版 | 新版 | 差異 |
|------|------|------|------|
| `show_debug` | True | False | ❌ 不一致 |

新版沒有打印調試圖像！

---

### 3. **其他參數檢查**

#### 轨跡參數
✅ `TRAJ_COLOR_BGR = (255, 220, 160)`
✅ `TRAJ_ALPHA = 0.8`
✅ `TRAJ_THICKNESS = 6`
✅ `TRAJ_DRAW_FROM_P0 = True`
✅ `TRAJ_MIN_POINTS = 2`

#### ROI 參數
✅ `size_init = 200`
✅ `size_min = 80`
✅ `shrink_over_frames = 60`
✅ `center_alpha = 0.4`
✅ `max_center_step = 80`

#### 追蹤參數
✅ `MIN_DX = 3` → `min_dx = 3`
✅ `WAIT_MAX_FRAMES = 180` → `wait_max_frames = 180`
✅ `P1_MUST_APPEAR_NEXT_FRAME = True` → `p1_must_appear_next = True`
✅ `P1_DEADLINE_FRAMES = 1` → `p1_deadline_frames = 1`
✅ `STEP_MODE_AFTER_P1 = False` → `step_mode_after_p1 = False`

#### 藍點參數
✅ `TOO_MANY_CANDS_USE_BLUE_AS_P = True` → `too_many_cands_use_blue = True`
✅ `TOO_MANY_CANDS_THRESHOLD = 4` → `too_many_cands_threshold = 4`
✅ `BLUE_P_OFFSET = -2` → `blue_p_offset = -2`
✅ `BLUE_TO_LASTP_MAX_DIST = 150.0` → `blue_to_lastp_max_dist = 150.0`

#### Y 方向參數
✅ `USE_Y_DIRECTION = True` → `use_y_direction = True`
✅ `Y_TOL = 1` → `y_tol = 1`
✅ `Y_MAX_STEP = 80` → `y_max_step = 80`

#### 動態調整參數
✅ `CFG_SPEED = 0.6` (硬編碼在 `get_dynamic_detect_cfg()`)
✅ `DIFF_MIN = 9`
✅ `CIRC_MIN = 0.60`
✅ `AREA_LO_MIN = 6`

---

## 🔧 修復步驟

### 修復 1: Kalman Filter 參數

需要將新版改為：
```python
@dataclass
class KFParams:
    dt: float = 0.033
    process_pos_var: float = 3.0      # 改為 3.0 ✓
    process_vel_var: float = 120.0    # 改為 120.0 ✓
    meas_var: float = 10.0            # 改為 10.0 ✓
```

### 修復 2: 檢測參數 show_debug

新版默認 `show_debug = False`，原版是 `True`。

為了保持一致，改為：
```python
detect_cfg_base: Dict[str, Any] = field(default_factory=lambda: {
    "area_range": (4, 150),
    "circ_thresh": 0.60,
    "diff_thresh": 16,
    "show_debug": True,  # 改為 True ✓
})
```

---

## 📊 影響分析

### Kalman Filter 參數不一致的影響：

| 參數 | 原版值 | 新版值 | 影響 |
|------|--------|--------|------|
| process_pos_var | 3.0 | 1.0 | **新版對位置變化不敏感，追蹤更平滑但可能延遲** |
| process_vel_var | 120.0 | 4.0 | **新版對速度變化反應緩慢，轉向不夠靈敏** ⚠️ |
| meas_var | 10.0 | 2.0 | **新版更信任測量值，易跳躍** |

**結論：** 新版 Kalman 參數偏向「平滑追蹤」，原版偏向「快速反應」。

這可能導致軌跡點間距變大或變小！

---

## ✅ 推薦修正方案

### 方案 A: 完全一致（推薦）

改為使用原版的 Kalman 參數：

```python
@dataclass
class KFParams:
    dt: float = 0.033
    process_pos_var: float = 3.0      # ✓ 匹配原版
    process_vel_var: float = 120.0    # ✓ 匹配原版
    meas_var: float = 10.0            # ✓ 匹配原版
```

### 方案 B: 保持新版但調試

如果要保留新版參數，至少要啟用 debug 查看什麼地方問題。

---

## 🎯 建議行動

1. **立即修正 Kalman 參數** ← 【最重要】
2. **啟用 show_debug** 以便診斷
3. **重新運行測試**

修正後應該能看到軌跡點更多、更連貫！
