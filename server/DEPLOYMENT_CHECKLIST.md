# 部署和測試檢查表

## ✅ 前期準備

### 環境檢查
- [ ] 已安裝 .NET 6+ SDK
- [ ] 已安裝 MySQL 5.7+
- [ ] 已安裝 Python 3.8+
- [ ] 已安裝必要的 Python 套件 (flask, librosa, mediaipe 等)
- [ ] 防火牆允許埠口 5000 和 5001

### 代碼檢查
- [ ] MeshFlowProcessingService.cs 編譯無誤
- [ ] ProcessQueueController.cs 編譯無誤
- [ ] Program.cs 編譯無誤
- [ ] appsettings.json 配置正確

## 🚀 啟動服務

### Step 1: 資料庫準備

```bash
# 1. 確保 MySQL 服務運行
# Windows: net start MySQL80 (或對應版本)
# Linux: sudo systemctl start mysql

# 2. 驗證連接
mysql -u root -p1qaz@WSX -h 10.1.1.25

# 3. 檢查資料庫
mysql> USE golfscoreapp;
mysql> SHOW TABLES;
```

- [ ] MySQL 服務啟動
- [ ] 資料庫連接成功
- [ ] process_queue 表存在
- [ ] videos 表存在
- [ ] files 表存在

### Step 2: Python MeshFlow API

```bash
# 終端 1
cd d:\Projects\golf_score_app\meshflow_stabilize_with_audio_V2

# 確認 server.py 存在
dir server.py

# 啟動 Flask 伺服器
python -m flask run --port 5001
```

**檢查清單**:
- [ ] Flask 成功啟動
- [ ] 監聽埠口 5001
- [ ] /api/meshflow 端點可用
- [ ] 日誌顯示: `Running on http://localhost:5001`

### Step 3: C# ASP.NET 伺服器

```bash
# 終端 2
cd d:\Projects\golf_score_app\server

# 還原依賴
dotnet restore

# 編譯
dotnet build

# 運行
dotnet run
```

**檢查清單**:
- [ ] 編譯成功無誤
- [ ] 資料庫遷移成功
- [ ] 後台服務已啟動
- [ ] 監聽埠口 5000
- [ ] 日誌顯示: `✅ MeshFlow 後台處理服務已註冊`

## 🧪 功能測試

### Test 1: API 健康檢查

```bash
# 檢查 C# 伺服器
curl http://localhost:5000/videos

# 檢查 Python API
curl http://localhost:5001/api/meshflow -X OPTIONS
```

**期望結果**: 
- [ ] C# 伺服器回應 200
- [ ] Python API 回應 200 或 405 (OPTIONS 不支持)

### Test 2: 查詢隊列統計

```bash
curl http://localhost:5000/api/processqueue/stats
```

**期望結果**:
```json
{
  "success": true,
  "message": "隊列統計資訊已取得",
  "data": {
    "queued": 0,
    "processing": 0,
    "completed": 0,
    "failed": 0
  }
}
```

- [ ] 回應狀態碼 200
- [ ] 包含 success=true
- [ ] data 包含 queued/processing/completed/failed 計數

### Test 3: 添加影片到隊列

首先需要在資料庫中準備測試影片：

```bash
# 在 C# 伺服器所在終端，或使用另一個 PowerShell 終端

# 1. 查詢已上傳的影片
curl http://localhost:5000/api/videos

# 2. 複製一個 videoId

# 3. 添加到隊列
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d '{"videoId": "YOUR_VIDEO_UUID_HERE", "priority": 0}'
```

**期望結果**:
```json
{
  "success": true,
  "message": "影片已添加到處理隊列",
  "data": {
    "videoId": "YOUR_VIDEO_UUID_HERE"
  }
}
```

- [ ] 回應狀態碼 200
- [ ] success=true
- [ ] 隊列項目已建立

### Test 4: 查詢隊列更新

```bash
# 等待 1-2 秒

curl http://localhost:5000/api/processqueue/stats
```

**期望結果**:
- [ ] queued 計數有變化（可能已被後台服務取出）
- [ ] processing 可能顯示 1（取決於 Python API 速度）

### Test 5: 查詢隊列項目

```bash
curl "http://localhost:5000/api/processqueue?status=queued&limit=10"
```

**期望結果**:
```json
{
  "success": true,
  "message": "已取得 X 個隊列項目",
  "data": [
    {
      "id": "queue-id",
      "videoId": "video-id",
      "priority": 0,
      "status": "queued|processing|completed|failed",
      "createdAt": "2024-02-01T10:00:00",
      ...
    }
  ]
}
```

- [ ] 可正常取得隊列項目
- [ ] 項目包含所有必要欄位

### Test 6: 等待自動處理

```bash
# 觀察日誌（每秒一次檢查）
# C# 伺服器日誌應顯示:

# logs/YYYY-MM-DD.log 應包含:
# 📋 找到待處理項目: queue-id
# ⚙️  開始處理隊列項目: queue-id
# 🌐 呼叫 MeshFlow API: http://localhost:5001/api/meshflow
# ✅ 分析完成 - 流程執行成功

# 或者查詢狀態變化
curl http://localhost:5000/api/processqueue/stats

# 應看到:
# queued 數量減少
# completed 或 failed 數量增加
```

**期望結果**:
- [ ] 看到「開始處理」日誌
- [ ] 看到「呼叫 MeshFlow API」日誌
- [ ] 看到「分析完成」或「處理失敗」日誌
- [ ] 隊列統計中 completed 或 failed 計數增加

### Test 7: 批量添加

```bash
curl -X POST http://localhost:5000/api/processqueue/enqueue-batch \
  -H "Content-Type: application/json" \
  -d '{
    "videoIds": ["video-id-1", "video-id-2", "video-id-3"],
    "priority": 0
  }'
```

**期望結果**:
- [ ] success=true
- [ ] 所有影片成功添加到隊列

### Test 8: 重試失敗項目

首先確保有失敗的項目：

```bash
# 1. 查詢失敗項目
curl "http://localhost:5000/api/processqueue?status=failed"

# 2. 複製失敗項目的 ID

# 3. 重試
curl -X PUT http://localhost:5000/api/processqueue/FAILED_ITEM_ID/retry

# 4. 驗證狀態變回 queued
curl http://localhost:5000/api/processqueue/FAILED_ITEM_ID
```

**期望結果**:
- [ ] 重試請求成功
- [ ] 項目狀態變為 queued
- [ ] RetryCount 重置為 0

### Test 9: 清除失敗項目

```bash
curl -X DELETE http://localhost:5000/api/processqueue/clear-failed
```

**期望結果**:
```json
{
  "success": true,
  "message": "已刪除 X 個失敗的隊列項目"
}
```

- [ ] 成功刪除失敗項目
- [ ] 後續查詢中失敗項目消失

## 📊 性能測試

### Test 10: 單個影片處理時間

```bash
# 1. 記錄開始時間
$start = Get-Date

# 2. 添加影片
curl -X POST http://localhost:5000/api/processqueue/enqueue \
  -H "Content-Type: application/json" \
  -d '{"videoId": "test-video-id"}'

# 3. 監控完成
# 持續查詢狀態直到完成
while ($true) {
  $stats = curl http://localhost:5000/api/processqueue/stats | ConvertFrom-Json
  if ($stats.data.processing -eq 0 -and $stats.data.queued -eq 0) {
    break
  }
  Start-Sleep -Seconds 1
}

# 4. 記錄結束時間
$end = Get-Date
$duration = ($end - $start).TotalSeconds
Write-Host "處理時間: $duration 秒"
```

**期望結果**:
- [ ] 處理時間合理（取決於影片長度，通常 5-60 秒）

### Test 11: 批量處理吞吐量

```bash
# 1. 添加 10 個影片
for ($i = 1; $i -le 10; $i++) {
  curl -X POST http://localhost:5000/api/processqueue/enqueue \
    -H "Content-Type: application/json" \
    -d '{"videoId": "video-'$i'"}'
}

# 2. 監控完成速度
# 查詢統計信息觀察吞吐量
while ($true) {
  curl http://localhost:5000/api/processqueue/stats
  Start-Sleep -Seconds 5
}
```

**期望結果**:
- [ ] 隊列逐個被消費
- [ ] completed 計數穩定增加

## 🐛 故障排除

### 如果 Python API 無法連接

```bash
# 1. 檢查 Python 伺服器是否運行
curl http://localhost:5001/

# 2. 檢查防火牆
netstat -ano | findstr :5001

# 3. 檢查 appsettings.json 中的 MeshFlow:ApiBaseUrl
# 應為: http://localhost:5001
```

### 如果資料庫連接失敗

```bash
# 1. 檢查 MySQL 是否運行
netstat -ano | findstr :3306

# 2. 檢查連接字符串
# appsettings.json:
# "DefaultConnection": "Server=10.1.1.25,3306;Database=golfscoreapp;User=root;Password=1qaz@WSX;"

# 3. 測試連接
mysql -u root -p1qaz@WSX -h 10.1.1.25 -e "SELECT 1"
```

### 如果隊列項目卡在 "processing"

```bash
# 1. 檢查日誌
tail -f server/logs/$(Get-Date -Format 'yyyy-MM-dd').log

# 2. 檢查 Python API 是否運行

# 3. 手動重試或刪除
curl -X DELETE http://localhost:5000/api/processqueue/STUCK_ITEM_ID
```

## 📈 監控清單

定期檢查以下指標：

- [ ] 隊列中待處理項目數量 (queued)
- [ ] 當前處理中項目 (processing) - 應為 0 或 1
- [ ] 已完成項目 (completed) - 應穩定增加
- [ ] 失敗項目 (failed) - 應盡量為 0
- [ ] 平均處理時間 - 應在可接受範圍內
- [ ] CPU 使用率 - 應正常
- [ ] 記憶體使用率 - 應穩定

## 🎯 完成簽核

當所有測試通過後：

- [ ] 所有 API 端點功能正常
- [ ] 後台服務每秒檢查隊列
- [ ] 影片正確進行同步處理
- [ ] 成功/失敗項目正確分類
- [ ] 重試邏輯正常工作
- [ ] 日誌記錄完整
- [ ] 性能在可接受範圍內

## 📝 部署備忘錄

### 首次部署

1. 備份現有資料庫
2. 運行 `dotnet ef database update` 應用遷移
3. 驗證 process_queue 表已建立
4. 啟動 Python API
5. 啟動 C# 伺服器
6. 運行完整測試套件

### 日常監控

- 每小時檢查失敗項目計數
- 監控平均處理時間
- 檢查日誌中的警告/錯誤
- 定期清理 clear-failed 項目

### 緊急響應

- 隊列堆積 → 檢查 Python API 或增加伺服器
- 高失敗率 → 查看錯誤日誌
- 記憶體洩漏 → 重啟服務

---

**最後更新**: 2024年  
**版本**: 1.0  
**狀態**: ✅ 就緒部署
