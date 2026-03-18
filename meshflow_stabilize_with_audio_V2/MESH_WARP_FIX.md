# 🔧 GPU MeshFlow Mesh Warp 修復 - 2026-02-04

## 問題描述

**症狀**: 視頻穩定化後，晃動部分被完全移除，而不是平穩地穩定化

**原因**: Mesh warp 變形應用了錯誤的位移
- ❌ 原始代碼使用 `stab_displacements`（平滑位移）進行變形
- ✅ 應該使用 `residual_displacements = unstab - stab`（殘差/晃動分量）進行變形

## 核心原理

### 位移定義

```
unstab_disp[t, r, c] = 幀 t 時網格點 (r,c) 的「實際」位移（包含晃動）
stab_disp[t, r, c]   = 幀 t 時網格點 (r,c) 的「平滑」位移（去除晃動）
residual_disp        = unstab - stab = 需要移除的晃動分量
```

### Mesh Warp 變形

```
目標：消除晃動，同時保留正常運動

方法：在源圖像中反向採樣
  map_x[y, x] = x - residual_disp[y, x]
  map_y[y, x] = y - residual_disp[y, x]

効果：
  - residual_disp > 0（向右晃動）→ 向左採樣 → 向右補償 ✓
  - residual_disp < 0（向左晃動）→ 向右採樣 → 向左補償 ✓
```

## 修復內容

### 1. 位移計算 (核心修復)
```python
# ❌ 原始（錯誤）
disp = stab_displacements[i, ri, ci]
map_x[ry, cx] = cx - disp[0]

# ✅ 修正（正確）
residual_disp = unstab_displacements[i] - stab_displacements[i]
# 然後用 residual_disp 進行雙線性插值到像素網格
```

### 2. 插值方法 (改進)
```python
# 使用 scipy.interpolate.RegularGridInterpolator
# 從網格點位移插值到像素位移
# 支持邊界外的值用 0 填充（保持透視）
```

### 3. 邊界計算 (對應修復)
```python
# ❌ 原始
diff_disp = unstab - stab

# ✅ 修正（保持一致，用於裁剪邊界）
residual_disp = unstab - stab
# 邊界反映的是殘差（晃動）的範圍
```

## 技術細節

### 雙線性插值流程

```
網格點位移（16×16）
        ↓ [RegularGridInterpolator]
像素位移映射（1920×1080）
        ↓ [cv2.remap]
變形圖像
```

### 數據流

```
frames (T, H, W, 3)
    ↓
unstab_disp (T, R+1, C+1, 2) ──┐
                                ├─→ residual = unstab - stab
stab_disp (T, R+1, C+1, 2) ────┘
    ↓
interpolate to (H, W)
    ↓
map_x, map_y (H, W)
    ↓
cv2.remap(frame, map_x, map_y)
    ↓
stabilized_frames (T, H', W', 3)
```

## 驗證方法

### 視覺檢查
```
1. 播放穩定化視頻
2. 檢查是否有平穩的運動（而不是突然移動）
3. 確認邊界裁剪量合理（不超過 50 像素）
```

### 數值檢查
```python
# 檢查位移範圍
print(np.min(residual_disp), np.max(residual_disp))  # 應該在 ±50 以內

# 檢查裁剪邊界
print(crop_boundaries)  # 應該是 {'left': xx, 'right': xx, ...}
```

## 相關參數調整

如果效果仍不理想，調整：

| 參數 | 默認值 | 調整建議 |
|------|--------|---------|
| `temporal_smoothing_radius` | 10 | 增加→更平滑，減少→保留細節 |
| `optimization_num_iterations` | 80 | 增加→更收斂，減少→更快 |
| `mesh_row_count` | 16 | 增加→更細緻，減少→更快 |
| `mesh_col_count` | 16 | 增加→更細緻，減少→更快 |
| `adaptive_weights_definition` | 0 | 改為 2 或 3 嘗試不同權重 |

## 文件修改

- **文件**: `meshflow_stabilization_gpu.py`
- **函數**: `get_stabilized_frames_and_crop_boundaries()`
- **行數**: ~140 行（整個函數重寫）
- **關鍵更改**:
  1. 使用 `residual_disp = unstab - stab` 而不是直接用 `stab`
  2. 使用 `RegularGridInterpolator` 進行雙線性插值
  3. 更新文檔和註解

## 向後相容性

✅ **完全相容**
- 配置類 `MeshFlowGPUConfig` 無改變
- 函數簽名無改變
- API 無改變
- 只是內部算法修正

## 預期效果

### 修復前
```
晃動幀 → (錯誤變形) → 移除晃動但損失內容
影響：視頻看起來被"切掉"了邊緣部分
```

### 修復後
```
晃動幀 → (正確變形) → 平穩補償但保留內容
影響：自然平穩的穩定化效果
```

---

**修復時間**: 2026-02-04  
**驗證狀態**: ✅ 語法檢查無誤  
**測試狀態**: 待用戶反饋
