# MediaPipe 遷移完成報告

## 項目概述
成功將 openpose_analysis.py 從 OpenPose 遷移至 MediaPipe，以獲得更輕量級、更易安裝的姿勢檢測解決方案。

## 完成的更改

### 1. 頂部導入和初始化 ✅
- 移除了 OpenPose 導入（`openpose.pyopenpose`）
- 添加了 MediaPipe 可用性檢查
- MediaPipe 使用延遲導入，在需要時才安裝

### 2. 姿勢關鍵點索引 ✅
- 更新為 MediaPipe COCO 33 點模型
- 關鍵點定義：
  - `NOSE`: 0
  - `LEFT_SHOULDER`: 11, `RIGHT_SHOULDER`: 12
  - `LEFT_ELBOW`: 13, `RIGHT_ELBOW`: 14
  - `LEFT_WRIST`: 15, `RIGHT_WRIST`: 16
  - `LEFT_HIP`: 23, `RIGHT_HIP`: 24
  - 完整的 33 點定義已包含在代碼中

### 3. 配置類更新 ✅
- 從 `OpenPoseConfig` 重命名為 `MediaPoseConfig`
- 保持所有相同的配置選項
- 移除 OpenPose 特定的參數（如 `openpose_model_dir`）
- 添加 `model_asset_path` 用於自定義模型加載

### 4. 姿勢提取函數 ✅
- **文件**: `extract_pose_keypoints()`
- **更改**:
  - 參數從 `opWrapper` 改為 `pose_detector`
  - 配置類型從 `OpenPoseConfig` 改為 `MediaPoseConfig`
  - 內部邏輯完全重寫以使用 MediaPipe API：
    - 使用 `cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)` 轉換顏色格式
    - 調用 `pose_detector.detect(frame_rgb)` 進行檢測
    - 從 `results.pose_landmarks` 提取關鍵點
    - 計算平均置信度 (`landmark.presence`)
    - 從歸一化座標轉換為像素座標
    - 保持相同的關鍵點名稱（`nose`, `l_shoulder`, 等）

### 5. 揮桿階段分析 ✅
- 更新函數簽名從 `OpenPoseConfig` 改為 `MediaPoseConfig`
- 核心邏輯保持不變（使用相同的關鍵點和計算）

### 6. 初始化函數 ✅
- **新增**: `initialize_pose_detector()`
- **功能**:
  - 導入 MediaPipe 的 tasks 模塊
  - 配置 PoseLandmarkerOptions
  - 創建並返回 PoseLandmarker 實例
  - 適當的錯誤處理和日誌記錄

### 7. 主分析函數 ✅
- **文件**: `run_openpose_analysis()`
- **更改**:
  - 函數名稱保持不變（用於向後兼容性）
  - 配置類型更新為 `MediaPoseConfig`
  - 移除 OpenPose 條件檢查
  - 添加 MediaPipe 導入檢查
  - 調用 `initialize_pose_detector(config)` 而非 OpenPose 初始化
  - 移除 `opWrapper.stop()` 調用
  - 從 OpenPose 的 datum 結構改為 MediaPipe 的結果對象
  - 更新 DataFrame 列名：`neck` → `nose`（MediaPipe 提供鼻尖而不是頸部）

### 8. 主函數 ✅
- 更新為使用 `MediaPoseConfig`

## 關鍵改進

### 性能優勢
- **輕量級**: MediaPipe 比 OpenPose 更小、更快
- **跨平台**: 無需複雜的編譯和模型文件
- **更好的移動支持**: 優化用於邊緣設備

### API 改進
- 歸一化的坐標系統（0-1 範圍）
- 統一的置信度模型（0-1 範圍）
- 內置的多人檢測支持

### 數據兼容性
- 保持相同的 CSV 輸出格式
- 相同的關鍵點名稱和順序
- 相同的角度計算邏輯

## 安裝說明

### 安裝 MediaPipe
```bash
pip install mediapipe opencv-python numpy pandas
```

### 可選：使用特定模型
```python
config = MediaPoseConfig(
    video_path="swing.mp4",
    model_asset_path="/path/to/pose_landmarker.task"
)
```

## 使用示例

```python
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    run_openpose_analysis
)

# 創建配置
config = MediaPoseConfig(
    video_path="your_video.mp4",
    output_dir="./output",
    rotation_90_clockwise=0,
    show_rule_label=True
)

# 運行分析
results_df = run_openpose_analysis(config)
print(f"分析完成：{len(results_df)} 幀")
```

## 測試建議

1. **單幀測試**:
   - 驗證 `extract_pose_keypoints()` 返回正確的數據結構
   - 確認置信度和坐標值在合理範圍內

2. **完整視頻測試**:
   - 運行完整的 `run_openpose_analysis()`
   - 驗證輸出 CSV 和視頻
   - 檢查角度計算和揮桿階段識別

3. **邊界情況**:
   - 低光條件
   - 不同的攝像機角度
   - 快速運動

## 文件位置
- **主文件**: `d:\Projects\golf_score_app\meshflow_stabilize_with_audio_V2\functions\openpose_analysis.py`
- **代碼行數**: ~870 行

## 向後兼容性
✅ 函數名稱保持不變（`run_openpose_analysis`）
✅ 輸出 DataFrame 結構兼容
✅ 配置參數大部分兼容
⚠️ 關鍵點名稱略有改變：`neck` → `nose`
⚠️ 舊代碼導入 `OpenPoseConfig` 需要更新為 `MediaPoseConfig`

## 後續步驟

1. ✅ 完成代碼遷移
2. 👉 運行單元測試驗證功能
3. 👉 與測試視頻進行集成測試
4. 👉 更新依賴項文檔
5. 👉 發布新版本

---

**遷移日期**: 2024
**狀態**: ✅ 完成
**下一步**: 測試和驗證
