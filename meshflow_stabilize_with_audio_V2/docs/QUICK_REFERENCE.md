# 快速參考卡片

## 🚀 最快開始方式

```bash
# 進入項目目錄
cd meshflow_stabilize_with_audio_V2

# 執行所有步驟
python main.py

# 完成！
```

## 📋 常用命令

| 命令 | 說明 |
|------|------|
| `python main.py` | 執行全部 6 個步驟 |
| `python main.py --summary` | 只顯示管線摘要 |
| `python main.py --help` | 顯示幫助信息 |
| `python main.py --steps 1 2 3` | 只執行步驟 1, 2, 3 |
| `python main.py --skip` | 遇到錯誤時跳過該步驟 |

## 🎯 6 個處理步驟

1. **Split Hits** - 根據IMU偵測擊球，切分影片和CSV
2. **Stabilize** - MeshFlow視頻穩定化
3. **Audio Analysis** - 分析擊球音頻特徵
4. **Audio Scoring** - 根據音頻評分擊球品質
5. **OpenPose** - 姿勢估計和揮桿動作分析
6. **Ball Tracking** - 球軌跡跟蹤

## 📁 重要文件

| 文件 | 說明 |
|------|------|
| `main.py` | 主程式入口 |
| `functions/` | 函數模組包 |
| `REFACTORING_GUIDE.md` | 詳細使用指南 |
| `USAGE_EXAMPLES.py` | 代碼範例 |
| `original/main_scripts/` | 原始腳本 |

## 🔧 Python 程式化使用

```python
# 方式1：導入函數
from functions import run_split_hits, run_audio_analysis

run_split_hits()
run_audio_analysis(batch_dir=r'Z:\Data\golf\20260126\cut\stabilized')

# 方式2：使用 main 函數
from main import run_full_pipeline
results = run_full_pipeline(steps=[1, 2, 3])
```

## ⚙️ 修改配置

1. 打開 `functions/` 中的相應文件（如 `split_hits.py`）
2. 在函數中修改參數
3. 保存後重新執行 `python main.py`

## 📚 文檔導航

```
📖 REFACTORING_GUIDE.md ───── 詳細的重構和使用指南
📖 USAGE_EXAMPLES.py ───────── 實用的代碼範例
📖 REFACTORING_SUMMARY.md ──── 系統架構和流程圖
📖 COMPLETION_REPORT.md ──────── 完成報告和統計
📖 本文件 ─────────────────────── 快速參考
```

## ✨ 主要特性

- ✅ 模組化：每個步驟獨立為函數
- ✅ 靈活：支持任意步驟組合
- ✅ 易用：統一的命令行界面
- ✅ 完整：詳細的文檔和範例
- ✅ 可靠：完善的錯誤處理

## 🆘 常見問題

### Q: 如何只執行某些步驟？
A: 使用 `--steps` 參數：
```bash
python main.py --steps 1 2 3
```

### Q: 如何跳過失敗的步驟？
A: 使用 `--skip` 參數：
```bash
python main.py --skip
```

### Q: 如何修改步驟參數？
A: 編輯 `functions/` 中的相應文件，然後重新執行。

### Q: 支持的 Python 版本？
A: Python 3.7 及以上

### Q: 在哪裡找原始代碼？
A: 保存在 `original/main_scripts/` 目錄中

## 📞 需要幫助？

- 查看 `REFACTORING_GUIDE.md` 了解更多詳情
- 查看 `USAGE_EXAMPLES.py` 學習代碼用法
- 查看各函數文件的註釋了解實現細節

---

**開始使用：** `python main.py`
