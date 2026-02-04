# 🚀 MediaPipe 遷移 - 快速參考卡

**文件**: `meshflow_stabilize_with_audio_V2/functions/openpose_analysis.py`
**狀態**: ✅ 完成 | **測試**: ⏳ 待進行

---

## 📦 快速安裝

```bash
# 安裝必需包
pip install mediapipe opencv-python numpy pandas

# 驗證安裝
python -c \"import mediapipe as mp; print('✓ 安裝成功')\"
```

---

## 🔧 快速測試

### 最小測試示例：
```python
import cv2
from pathlib import Path
from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import (
    MediaPoseConfig,
    run_openpose_analysis
)

# 配置
config = MediaPoseConfig(
    video_path=\"test_video.mp4\",
    output_dir=\"./output\"
)

# 運行分析
df = run_openpose_analysis(config)

# 驗證
print(f\"✓ 成功分析 {len(df)} 幀\")
print(f\"✓ 列名: {df.columns.tolist()}\")
```

---

## 📋 主要類和函數

| 類/函數 | 用途 | 返回類型 |
|---|---|---|
| `MediaPoseConfig` | 配置對象 | dataclass |
| `initialize_pose_detector()` | 初始化檢測器 | Any |
| `extract_pose_keypoints()` | 提取單幀姿勢 | Dict |
| `analyze_swing_phases()` | 分析揮桿階段 | Dict |
| `run_openpose_analysis()` | 完整視頻分析 | DataFrame |

---

## 🎯 關鍵變更

| 項目 | 舊 (OpenPose) | 新 (MediaPipe) |
|---|---|---|
| 導入 | `pyopenpose` | `mediapipe.tasks` |
| 模型 | BODY_25 (25 點) | COCO (33 點) |
| 類名 | `OpenPoseConfig` | `MediaPoseConfig` |
| 頭部點 | `neck` | `nose` |
| API | `WrapperPython` | `PoseLandmarker` |

---

## 📊 輸出 DataFrame 列

```
frame, time_sec, mean_conf, shoulder_angle, hip_angle, x_factor,
nose_x, nose_y,  # ← 變化: 從 neck_x/y 改為 nose_x/y
l_shoulder_x, l_shoulder_y, r_shoulder_x, r_shoulder_y,
l_hip_x, l_hip_y, r_hip_x, r_hip_y,
l_wrist_x, l_wrist_y, r_wrist_x, r_wrist_y,
phase
```

---

## 🔍 33 個 MediaPipe 關鍵點

```
0: NOSE                    23: LEFT_HIP
1: LEFT_EYE_INNER         24: RIGHT_HIP
2: LEFT_EYE               25: LEFT_KNEE
3: LEFT_EYE_OUTER         26: RIGHT_KNEE
4: RIGHT_EYE_INNER        27: LEFT_ANKLE
5: RIGHT_EYE              28: RIGHT_ANKLE
6: RIGHT_EYE_OUTER        29: LEFT_HEEL
7: LEFT_EAR               30: RIGHT_HEEL
8: RIGHT_EAR              31: LEFT_FOOT_INDEX
9: MOUTH_LEFT             32: RIGHT_FOOT_INDEX
10: MOUTH_RIGHT           
11: LEFT_SHOULDER         高爾夫分析核心點:
12: RIGHT_SHOULDER        - 11/12: 肩膀
13: LEFT_ELBOW            - 23/24: 髖部
14: RIGHT_ELBOW           - 15/16: 手腕
15: LEFT_WRIST            
16: RIGHT_WRIST           
17: LEFT_PINKY            
18: RIGHT_PINKY           
19: LEFT_INDEX            
20: RIGHT_INDEX           
21: LEFT_THUMB            
22: RIGHT_THUMB           
```

---

## ⚙️ 配置選項

```python
config = MediaPoseConfig(
    # 必需
    video_path=\"swing.mp4\",
    
    # 可選 - 基本設置
    output_dir=\"./output\",              # 預設: ./phase
    model_asset_path=None,             # 自定義模型路徑
    
    # 可選 - 視頻處理
    rotation_90_clockwise=0,           # 1 = 旋轉 90°
    
    # 可選 - 標籤
    show_rule_label=True,              # 顯示好/壞標籤
    
    # 可選 - 置信度
    min_total_conf=0.30,               # 全身置信度下限
    keypoint_conf_threshold=0.5,       # 單點置信度下限
    
    # 可選 - 輸出
    save_pose_csv=False,               # 保存姿勢 CSV
    save_pose_phase_csv=False,         # 保存階段 CSV
)
```

---

## 🧪 快速測試命令

```bash
# 1. 驗證安裝
python -c \"from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import MediaPoseConfig; print('✓')\"

# 2. 查看所有列
python -c \"from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import run_openpose_analysis, MediaPoseConfig; import sys; c = MediaPoseConfig(sys.argv[1]); df = run_openpose_analysis(c); print(df.columns.tolist())\" \"test.mp4\"

# 3. 統計信息
python -c \"from meshflow_stabilize_with_audio_V2.functions.openpose_analysis import run_openpose_analysis, MediaPoseConfig; import sys; c = MediaPoseConfig(sys.argv[1]); df = run_openpose_analysis(c); print(f'幀數: {len(df)}, 有效置信度: {df[\"mean_conf\"].notna().sum()}')\" \"test.mp4\"
```

---

## 🐛 常見問題快速解決

| 問題 | 解決方案 |
|---|---|
| `ImportError: mediapipe` | `pip install mediapipe` |
| `無法打開影片` | 檢查路徑和格式 |
| `無法檢測人物` | 調整光線或降低 `min_total_conf` |
| `logger not defined` | ✅ 已修正（使用 print） |
| `坐標為 NaN` | 置信度不足，檢查視頻質量 |

---

## 📚 詳細文檔

| 文檔 | 內容 |
|---|---|
| `MEDIAPIPE_TESTING_GUIDE.md` | 完整測試步驟 |
| `MEDIAPIPE_CODE_CHANGES_DETAIL.md` | 代碼變更詳情 |
| `MEDIAPIPE_MIGRATION_COMPLETE.md` | 遷移完成報告 |

---

## ✅ 驗證清單

完成測試前的檢查：

- [ ] MediaPipe 已安裝 (`pip install mediapipe`)
- [ ] 可以導入模塊
- [ ] 測試視頻存在且可播放
- [ ] 輸出目錄可寫
- [ ] ffmpeg 已安裝（用於音頻合併）

---

## 📞 支持資源

- **官方文檔**: https://developers.google.com/mediapipe
- **GitHub**: https://github.com/google/mediapipe
- **本地文檔**: `MEDIAPIPE_*.md` 文檔

---

## 🎯 下一步

1. 按照 `MEDIAPIPE_TESTING_GUIDE.md` 進行測試
2. 驗證輸出質量
3. 比較性能指標
4. 完成生產環境部署

---

**最後更新**: 2024
**快速參考版本**: 1.0
