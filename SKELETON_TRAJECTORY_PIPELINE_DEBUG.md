# 骨架 + 球軌跡疊加流程 - 診斷指南

## 當前狀態
- ✅ 有裁切後的影片（hit_1.mp4）
- ❌ 沒有骨架疊加（hit_1_skeleton.mp4）
- ❌ 沒有球軌跡疊加（hit_1_final.mp4）

---

## 快速診斷清單

### 第一步：查看日誌

運行應用後執行擊球偵測，然後在 Logcat 中搜索這些關鍵詞：

```
# 搜索詞
[偵測擊球]
D/SkeletonOverlay
I/MPEG4Writer
E/BallBlobExtractor
```

### 第二步：查找失敗點

根據日誌找出是哪一步失敗：

#### **骨架疊加失敗** ❌

日誌：`[偵測擊球] 第1球 → ❌ 骨架疊加失敗`

**檢查清單：**

1. **CSV 文件是否存在？**
   ```
   logcat 中看是否有：
   [偵測擊球] 第1球 → ❌ CSV 不存在：/path/to/pose_landmarks.csv
   ```
   
   如果 CSV 不存在：
   - 檢查 `VideoAnalysisService` 是否完成運行
   - 檢查輸出路徑是否正確
   - 檢查文件權限

2. **裁切片段是否存在？**
   ```
   logcat 中看是否有：
   [偵測擊球] 第1球 → ❌ 裁切片段不存在：/path/to/hit_1.mp4
   ```
   
   如果不存在：
   - 檢查 `VideoClipService.trimClip()` 是否成功
   - 檢查磁盤空間

3. **SkeletonOverlayRenderer 是否拋出異常？**
   ```
   logcat 中搜索：
   E/MainActivity: 骨架渲染失敗: [異常信息]
   D/SkeletonOverlay: ERROR: encodedFrames=0
   ```
   
   | 異常信息 | 原因 |
   |---------|------|
   | `找不到視頻 track` | 裁切片段損壞或格式不支持 |
   | `无法建立解碼器` | 視頻格式不支持 |
   | `無法從 CSV 推算骨架影像尺寸` | CSV 格式錯誤或坐標無效 |
   | `encodedFrames=0` | 編碼器未輸出幀（我們已修復） |
   | `找不到視頻 track` | 生成的 MP4 沒有有效軌 |

#### **Blob 提取失敗** ❌

日誌：`[偵測擊球] 第1球 → ❌ blob 提取失敗`

原因：骨架疊加成功，但骨架影片無法讀取
- 檢查 `D/SkeletonOverlay: 骨架渲染完成` 是否出現
- 檢查生成的 hit_1_skeleton.mp4 是否真的存在
- 檢查 BallBlobExtractor 日誌

#### **追蹤點不足** ⚠️

日誌：`[偵測擊球] 第1球 → ⚠️  追蹤點不足 (3 個)，略過疊加`

原因：球軌跡不夠清晰或運動範圍太小
- 這是**正常現象**，表示偵測到球但軌跡不完整
- 可能是 blob 提取門檻過高
- 可能是影片質量不夠

#### **軌跡疊加失敗** ❌

日誌：`[偵測擊球] 第1球 → ❌ 軌跡疊加失敗`

原因：TrajectoryOverlayRenderer 渲染失敗
- 檢查 `E/MainActivity: 軌跡疊加失敗` 的異常信息
- 檢查 `E/MPEG4Writer` 是否報告 0 幀

---

## 完整流程驗證

### 場景 1：全部成功

```
[偵測擊球] 第1球 → ✅ 骨架疊加成功：/clips/hit_1_skeleton.mp4
[偵測擊球] 第1球 → 開始球軌跡疊加流程
[偵測擊球] 第1球 → ✅ blob 提取完成：150 幀，fps=30.0，1280×720
[偵測擊球] 第1球 → ✅ 追蹤完成：45 個軌跡點
[偵測擊球] 第1球 → ✅ 球軌跡疊加成功：/clips/hit_1_final.mp4
```

結果：hit_1_final.mp4（含骨架 + 球軌跡）

### 場景 2：骨架失敗，回退到原始

```
[偵測擊球] 第1球 → ❌ CSV 不存在：/path/pose_landmarks.csv
[偵測擊球] 第1球 → ❌ 骨架疊加失敗
[偵測擊球] 第1球 → ⚠️  骨架疊加失敗，略過球軌跡疊加
```

結果：hit_1.mp4（原始裁切，無骨架）

### 場景 3：骨架成功，Blob 失敗

```
[偵測擊球] 第1球 → ✅ 骨架疊加成功：/clips/hit_1_skeleton.mp4
[偵測擊球] 第1球 → 開始球軌跡疊加流程
[偵測擊球] 第1球 → ❌ blob 提取失敗
```

結果：hit_1_skeleton.mp4（只有骨架，無球軌跡）

---

## 重點 Logcat 過濾

### Android Studio Logcat 過濾表達式

```regex
(SkeletonOverlay|MPEG4Writer|BallBlobExtractor|\[偵測擊球\])
```

### 打開 Logcat 中的按優先級過濾

- **Debug** (D)：SkeletonOverlay 的所有詳細日誌
- **Info** (I)：MPEG4Writer 編碼統計
- **Error** (E)：所有錯誤和異常

---

## 常見問題排查

### Q1：CSV 文件為什麼不存在？

**原因**：VideoAnalysisService 未完成或失敗

**解決方案**：
1. 檢查是否有「正在分析骨架...」的進度提示
2. 查看是否有 VideoAnalysisService 的日誌：`D/VideoAnalysis`
3. 確認有足夠的磁盤空間

### Q2：為什麼骨架渲染返回了 false？

**檢查清單**：
1. 查看 `D/SkeletonOverlay: ERROR` 中的 encodedFrames
2. 查看 `I/MPEG4Writer` 的編碼統計
3. 查看 `E/MPEG4Writer: Stop() called but track is not started` 表示 0 幀

### Q3：為什麼 blob 提取返回 null？

**原因**：骨架影片無效或 BallBlobExtractor 異常

**解決方案**：
1. 驗證 hit_1_skeleton.mp4 是否真的存在
2. 驗證文件大小 > 0 KB
3. 查看 `E/BallBlobExtractor` 的具體異常

### Q4：為什麼追蹤點不足？

**原因**：球運動範圍太小或 blob 檢測門檻過高

**解決方案**：
1. 檢查球是否在影片中清晰可見
2. 檢查球的運動距離（應該 > 50px）
3. 考慮調整 BallTracker 的信心門檻

### Q5：軌跡疊加失敗，MPEG4Writer 報告 0 幀？

**原因**：TrajectoryOverlayRenderer 有相同的編碼器問題

**解決方案**：
1. 檢查 TrajectoryOverlayRenderer 是否也需要類似修復
2. 查看 `D/TrajectoryOverlay` 的日誌（如果有的話）

---

## 實時診斷命令

在終端中運行這些命令實時監控日誌：

```bash
# 查看所有骨架相關日誌
flutter logs | grep -E "(SkeletonOverlay|偵測擊球)"

# 只看錯誤
flutter logs | grep -E "ERROR|Error|error|E/"

# 只看骨架渲染的完整流程
flutter logs | grep -A 20 "骨架渲染"
```

---

## 文件路徑驗證

確認這些文件存在的位置（以 hit_1 為例）：

```
📁 sessionDir/
├── 📁 cut/
│   ├── ✅ hit_1.mp4                  # 原始裁切（已生成）
│   ├── ❓ hit_1_skeleton.mp4         # 骨架疊加（應生成）
│   ├── ❓ hit_1_final.mp4            # 球軌跡疊加（應生成）
│   └── ❓ hit_1.jpg                   # 縮圖（應生成）
├── pose_landmarks.csv             # 骨架 CSV（必需）
├── audio.pcm                        # 音頻 PCM（必需）
└── 其他文件
```

---

## 下一步行動

1. **立即執行擊球偵測**
2. **檢查上述任一場景是否匹配**
3. **提供對應的日誌片段**
4. 根據失敗點調整策略

---

## 修復我已應用的內容

✅ SkeletonOverlayRenderer：
- 添加 encodedFrames / samplesWritten 計數
- 修正 Image.close() 時序
- 加強 drainEncoder 日誌
- 添加 encodedFrames 驗證邏輯

✅ recording_history_page.dart：
- 添加 CSV / 裁切片段存在性驗證
- 改進日誌可讀性（❌ ✅ ⚠️）
- 添加壞檔刪除邏輯
- 完整的三階段流程日誌

✅ MainActivity：
- 骨架渲染異常捕獲並報告

---

## 需要進一步修復嗎？

如果診斷後確認需要修復其他組件（如 TrajectoryOverlayRenderer），請提供日誌，我會立即實施修正。
