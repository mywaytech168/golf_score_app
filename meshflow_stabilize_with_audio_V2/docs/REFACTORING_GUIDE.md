# MeshFlow Stabilize with Audio V2 - 重構指南

## 📋 項目結構

```
meshflow_stabilize_with_audio_V2/
├── main.py                          # ✨ 主入口 - 根據使用順序調用所有步驟
├── functions/                       # 🔧 函數模組包
│   ├── __init__.py
│   ├── split_hits.py               # 步驟1：切分擊球
│   ├── meshflow_stabilization.py   # 步驟2：視頻穩定化
│   ├── audio_analysis.py            # 步驟3：音頻分析
│   ├── audio_scoring.py             # 步驟4：音頻評分
│   ├── openpose_analysis.py         # 步驟5：姿勢分析
│   └── ball_tracking.py             # 步驟6：球軌跡跟蹤
└── original/                        # 📦 原始腳本（保留以供參考）
    └── main_scripts/
        ├── Golf_split_hits_from_csv_phone_demo.py
        ├── meshflow_stabilize_with_audio.py
        ├── classify_golf_audio_analysis_demo.py
        ├── classify_golf_audio_score_demo.py
        ├── video_openpose_demo.py
        └── ball_tracking_no_cnn_stable_21.py
```

## 🚀 快速開始

### 執行完整管線

```bash
# 執行所有步驟（按照使用順序）
python main.py

# 執行特定步驟
python main.py --steps 1 2 3

# 遇到錯誤時跳過該步驟
python main.py --skip

# 只顯示管線摘要
python main.py --summary
```

## 📊 處理管線說明

### 步驟1：Split Hits from CSV and Video
**目的**：根據IMU加速度偵測擊球，切分影片和CSV數據

**輸入**：
- 原始影片 (REC_*.mp4)
- IMU CSV 數據 (REC_*_CHEST.csv, REC_*_RIGHT_WRIST.csv)

**輸出**：
- 切分後的擊球影片 (hit_001.mp4, hit_002.mp4, ...)
- 對應的CSV數據 (hit_001_Codi2.csv, ...)
- 擊球摘要 (hits_summary.csv)

**配置文件**：`functions/split_hits.py`

---

### 步驟2：MeshFlow Video Stabilization
**目的**：使用MeshFlow演算法穩定視頻，移除相機晃動

**輸入**：
- 切分後的擊球影片

**輸出**：
- 穩定化後的影片 (*.stabilized.mp4)

**主要功能**：
- 自動晃動段檢測
- 網格流光學流算法
- 音訊保留

**配置文件**：`functions/meshflow_stabilization.py`

---

### 步驟3：Audio Analysis
**目的**：分析擊球音頻特徵

**輸入**：
- 穩定化後的影片（含音訊）

**輸出**：
- 音頻特徵數據
- 頻譜分析圖表
- 音頻摘要CSV

**提取特徵**：
- 音量 (Peak dBFS, RMS dBFS)
- 頻譜特徵 (Spectral Centroid, 頻帶峰值)
- 時域特徵 (ZCR, MFCC)
- 尖銳度

**配置文件**：`functions/audio_analysis.py`

---

### 步驟4：Audio Score Classification
**目的**：根據音頻特徵評分，判斷擊球品質

**輸入**：
- 音頻特徵數據

**輸出**：
- 擊球品質評分
- 評分規則應用結果
- 評分摘要CSV

**評分維度**：
- RMS音量 (-30.0 ~ -24.0 dBFS)
- 頻譜重心 (3800 ~ 4350 Hz)
- 尖銳度 (> 2.0)
- 高頻帶幅度 (11.0 ~ 32.0)
- Peak dBFS

**配置文件**：`functions/audio_scoring.py`

---

### 步驟5：Video OpenPose Analysis
**目的**：使用OpenPose進行姿勢估計和揮桿動作分析

**輸入**：
- 穩定化後的影片

**輸出**：
- 骨架數據 (pose.csv)
- 揮桿階段標記 (pose_phase.csv)
- 骨架可視化影片 (pose.mp4, pose_phase.mp4)

**識別的揮桿階段**：
- Address（預備姿勢）
- Backswing（回擺）
- Downswing（下擺）
- Impact（接觸球）
- Follow-through（隨揮）

**配置文件**：`functions/openpose_analysis.py`

---

### 步驟6：Ball Tracking Analysis
**目的**：跟蹤高爾夫球軌跡，分析擊球參數

**輸入**：
- 穩定化後的影片（含揮桿階段標記）

**輸出**：
- 球軌跡數據
- 軌跡可視化影片
- 軌跡分析報告

**支持功能**：
- 批量處理
- 固定ROI模式
- 軌跡可視化
- 參數導出

**配置文件**：`functions/ball_tracking.py`

---

## 🔧 配置方式

每個函數文件都可以單獨導入和使用：

```python
from functions import (
    run_split_hits,
    run_meshflow_stabilization,
    run_audio_analysis,
    run_audio_scoring,
    run_openpose_analysis,
    run_ball_tracking,
)

# 執行特定步驟
run_split_hits()
stabilizer = run_meshflow_stabilization()
run_audio_analysis()
run_audio_scoring()
run_openpose_analysis()
run_ball_tracking()
```

## 📝 修改和擴展

### 修改特定步驟的參數

每個 `functions/*.py` 文件都封裝了相應步驟的邏輯。要修改參數：

1. 打開對應的函數文件（例如 `functions/split_hits.py`）
2. 修改函數中的參數或配置
3. 重新運行 `python main.py`

### 添加新的步驟

1. 在 `functions/` 目錄中創建新文件（例如 `functions/new_step.py`）
2. 實現 `run_new_step()` 函數
3. 在 `functions/__init__.py` 中導入
4. 在 `main.py` 中的 `all_steps` 列表中添加新步驟

## 🐛 故障排查

### 找不到原始模組
確保 `original/main_scripts/` 目錄包含所有原始腳本文件。

### 依賴包缺失
安裝所需的Python包：
```bash
pip install opencv-python numpy pandas scipy moviepy librosa soundfile matplotlib
```

### OpenPose 相關錯誤
確保 OpenPose 已正確安裝在指定目錄。

### 路徑問題
檢查配置中的路徑是否正確（例如 `BATCH_DIR`, `INPUT_DIR` 等）。

## 📚 參考文檔

- [使用順序](./original/docs/使用順序.txt)
- [MeshFlow穩定化文檔](./MESHFLOW_SERVER_ARCHITECTURE.md)
- [完成清單](./COMPLETION_SUMMARY.md)

## ✨ 特點

✅ **模組化**：每個步驟獨立可調用
✅ **可組合**：支持執行任意步驟組合
✅ **可擴展**：易於添加新步驟
✅ **易於配置**：清晰的參數設置
✅ **完整文檔**：詳細的使用說明
✅ **錯誤處理**：友善的錯誤提示

