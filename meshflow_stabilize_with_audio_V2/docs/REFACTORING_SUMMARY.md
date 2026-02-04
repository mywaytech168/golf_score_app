# MeshFlow Stabilize with Audio V2 - 重構完成總結

## 📌 重構概述

成功將 meshflow_stabilize_with_audio_V2 的 6 個主要腳本重構成模組化的函數文件，並通過 `main.py` 按照使用順序統一調用。

## 🗂️ 項目結構

### 重構前（原始結構）
```
original/main_scripts/
├── Golf_split_hits_from_csv_phone_demo.py
├── meshflow_stabilize_with_audio.py
├── classify_golf_audio_analysis_demo.py
├── classify_golf_audio_score_demo.py
├── video_openpose_demo.py
└── ball_tracking_no_cnn_stable_21.py
```

### 重構後（新結構）
```
meshflow_stabilize_with_audio_V2/
├── main.py                          ✨ 主入口（根據使用順序調用）
├── functions/                       🔧 函數模組包
│   ├── __init__.py
│   ├── split_hits.py               # 步驟1
│   ├── meshflow_stabilization.py   # 步驟2
│   ├── audio_analysis.py            # 步驟3
│   ├── audio_scoring.py             # 步驟4
│   ├── openpose_analysis.py         # 步驟5
│   └── ball_tracking.py             # 步驟6
├── original/                        📦 原始腳本（保留）
│   └── main_scripts/
│       └── [6個原始腳本]
├── REFACTORING_GUIDE.md             📖 重構指南
├── USAGE_EXAMPLES.py                📚 使用範例
└── README.md（或其他現有文檔）
```

## 📋 6 個步驟說明

### 步驟1：Split Hits from CSV and Video
**函數文件**：[functions/split_hits.py](functions/split_hits.py)
- **功能**：根據IMU加速度偵測擊球時間點，切分影片和CSV數據
- **調用方式**：`run_split_hits()`
- **原始腳本**：Golf_split_hits_from_csv_phone_demo.py

### 步驟2：MeshFlow Video Stabilization
**函數文件**：[functions/meshflow_stabilization.py](functions/meshflow_stabilization.py)
- **功能**：使用MeshFlow演算法穩定視頻，移除相機晃動
- **調用方式**：`stabilizer = run_meshflow_stabilization()`
- **原始腳本**：meshflow_stabilize_with_audio.py

### 步驟3：Audio Analysis
**函數文件**：[functions/audio_analysis.py](functions/audio_analysis.py)
- **功能**：分析擊球音頻特徵（音量、頻譜、尖銳度等）
- **調用方式**：`run_audio_analysis(batch_dir=...)`
- **原始腳本**：classify_golf_audio_analysis_demo.py

### 步驟4：Audio Scoring
**函數文件**：[functions/audio_scoring.py](functions/audio_scoring.py)
- **功能**：根據音頻特徵評分，判斷擊球品質
- **調用方式**：`run_audio_scoring(target_folder=...)`
- **原始腳本**：classify_golf_audio_score_demo.py

### 步驟5：OpenPose Analysis
**函數文件**：[functions/openpose_analysis.py](functions/openpose_analysis.py)
- **功能**：姿勢估計和高爾夫揮桿動作分析
- **調用方式**：`run_openpose_analysis(input_dir=...)`
- **原始腳本**：video_openpose_demo.py

### 步驟6：Ball Tracking
**函數文件**：[functions/ball_tracking.py](functions/ball_tracking.py)
- **功能**：跟蹤高爾夫球軌跡，分析擊球參數
- **調用方式**：`run_ball_tracking(input_dir=..., batch_mode=True)`
- **原始腳本**：ball_tracking_no_cnn_stable_21.py

## 🚀 使用方式

### 方式1：命令行執行（推薦）

```bash
# 執行所有步驟
python main.py

# 只顯示摘要
python main.py --summary

# 執行特定步驟
python main.py --steps 1 2 3

# 遇到錯誤時跳過
python main.py --skip

# 組合選項
python main.py --steps 1 2 3 --skip
```

### 方式2：Python 程式化調用

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
run_audio_analysis(batch_dir=r'Z:\Data\golf\20260126\cut\stabilized')
```

## ✨ 重構的優勢

✅ **模組化**：每個步驟獨立為一個函數文件
✅ **可組合**：支持執行任意步驟組合
✅ **易於擴展**：新增步驟只需創建新的函數文件
✅ **清晰的執行流**：main.py 按照使用順序調用所有步驟
✅ **參數靈活性**：每個函數都支持自定義參數
✅ **友善的錯誤處理**：完整的錯誤提示和恢復機制
✅ **保留原始代碼**：原始腳本保存在 original/ 目錄中
✅ **完整文檔**：包含使用指南和範例

## 📖 文檔

- **[REFACTORING_GUIDE.md](REFACTORING_GUIDE.md)**：詳細的重構和使用指南
- **[USAGE_EXAMPLES.py](USAGE_EXAMPLES.py)**：實用的使用範例
- **[使用順序.txt](original/docs/使用順序.txt)**：原始腳本的執行順序

## 🔧 修改配置

要修改某個步驟的配置：

1. 打開對應的函數文件（例如 `functions/split_hits.py`）
2. 在函數內修改參數
3. 保存文件
4. 重新執行 `python main.py`

## ⚙️ 系統要求

- Python 3.7+
- 依賴包：opencv-python, numpy, pandas, scipy, moviepy, librosa, soundfile, matplotlib
- OpenPose（步驟5 需要）

## 🐛 故障排查

### 找不到模組
確保 `original/main_scripts/` 目錄中包含所有 6 個原始腳本。

### 依賴包缺失
```bash
pip install opencv-python numpy pandas scipy moviepy librosa soundfile matplotlib
```

### OpenPose 相關錯誤
確保 OpenPose 已正確安裝在指定目錄。

## 📊 執行流程圖

```
main.py (主入口)
    ↓
┌───────────────────────────────────────┐
│ 解析命令行參數 (--steps, --skip, etc) │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 步驟1：Split Hits                    │
│ └─ run_split_hits()                   │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 步驟2：MeshFlow Stabilization        │
│ └─ run_meshflow_stabilization()      │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 步驟3：Audio Analysis                │
│ └─ run_audio_analysis()               │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 步驟4：Audio Scoring                 │
│ └─ run_audio_scoring()                │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 步驟5：OpenPose Analysis             │
│ └─ run_openpose_analysis()            │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 步驟6：Ball Tracking                 │
│ └─ run_ball_tracking()                │
└───────────────────────────────────────┘
    ↓
┌───────────────────────────────────────┐
│ 生成執行摘要和統計                    │
└───────────────────────────────────────┘
```

## 🎯 後續改進建議

1. 添加配置文件支持（YAML/JSON）
2. 實現步驟間的數據流傳遞
3. 添加進度條顯示
4. 實現日誌記錄功能
5. 添加更多的錯誤恢復機制
6. 創建 Web UI 控制面板

## 📝 版本信息

- **重構日期**：2026年2月2日
- **原始項目**：meshflow_stabilize_with_audio_V2
- **重構版本**：1.0
- **狀態**：✅ 完成

## 📞 聯絡和反饋

如有任何問題或建議，請參考相關文檔或查看函數文件中的詳細註釋。

---

**🎉 重構完成！** 系統已準備就緒。
