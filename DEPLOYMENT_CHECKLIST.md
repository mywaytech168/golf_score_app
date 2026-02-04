# 🚀 部署清單 - 6 大問題修復

## 📋 預部署檢查

- [x] `server_improved.py` 已創建 (282 行)
- [x] `task_queue.py` 已更新 (4 個改進)
- [x] `test_six_fixes.py` 已創建 (500+ 行)
- [x] 所有文檔已準備

## 🔍 環境驗證

```bash
# 1. 檢查 Python 版本 (3.8+)
python --version

# 2. 檢查依賴
pip list | grep -E "flask|redis|requests"

# 3. 檢查 Redis 連接
redis-cli ping
# 應返回: PONG

# 4. 檢查 C# Server
curl http://localhost:5001/health
# 應返回: 200 OK
```

## 📦 部署步驟

### 第 1 步: 備份原始文件

```bash
cd d:\Projects\golf_score_app\meshflow_stabilize_with_audio_V2

# 備份原始文件
cp server.py server_backup_$(date +%Y%m%d_%H%M%S).py
cp services/task_queue.py services/task_queue_backup_$(date +%Y%m%d_%H%M%S).py
```

### 第 2 步: 部署改進的 server.py

```bash
# 用新的 server_improved.py 替換原始 server.py
cp server_improved.py server.py

# 驗證文件
ls -la server.py
# 應顯示新的時間戳
```

### 第 3 步: 驗證 task_queue.py 更新

task_queue.py 已包含以下改進:
```
✅ _send_result_with_retry() - 異步 HTTP 發送 (3 次重試)
✅ Pipeline 30 分鐘超時控制
✅ Redis 連接池 + TCP Keep-Alive
✅ _redis_safe_call() - 安全 Redis 調用 (3 次重試)
```

驗證方式:
```bash
grep -n "_send_result_with_retry\|_redis_safe_call\|threading.Timer" \
  services/task_queue.py

# 應找到多個匹配
```

### 第 4 步: 啟動服務

```bash
# 停止舊的 Flask 服務 (如果運行)
# 可以用 Ctrl+C

# 啟動新的 Flask 服務
python server.py

# 預期輸出:
# [INFO] Starting Flask server...
# [INFO] Registering routes...
# [INFO] Starting task queue scheduler...
# [INFO] Flask running on http://127.0.0.1:5000
```

### 第 5 步: 驗證服務健康

```bash
# 1. 健康檢查
curl http://localhost:5000/api/health
# 應返回:
# {
#   "status": "healthy",
#   "version": "2.0.0",
#   "service": "MeshFlow API",
#   "dependencies": {
#     "redis": "connected",
#     "csharp_server": "connected"
#   }
# }

# 2. API 信息
curl http://localhost:5000/api/info
# 應返回改進清單
```

### 第 6 步: 運行完整測試

```bash
# 啟動另一個終端窗口
cd d:\Projects\golf_score_app\meshflow_stabilize_with_audio_V2

# 運行測試
python test_six_fixes.py

# 預期:
# ✅ 異步 Flask API - PASS
# ✅ 任務隊列 - PASS
# ✅ 異常處理 - PASS
# ✅ API 文檔 - PASS
# ✅ 健康檢查 - PASS
# ✅ 並發請求 - PASS
# 
# 🎉 所有測試通過 (6/6)
```

## 🔄 驗證測試詳解

### 測試 1: 異步 Flask API (非阻塞)

```bash
# 測試快速響應
time curl -X POST http://localhost:5000/api/tasks/process \
  -H "Content-Type: application/json" \
  -d '{
    "input_dir": "/path/to/video",
    "output_dir": "/path/to/output",
    "video_id": "test-123"
  }'

# 應 < 100ms 返回 202 Accepted
# 實際時間應在 10-50ms 之間
```

### 測試 2: 任務隊列工作流

```bash
# 1. 提交任務
TASK_ID=$(curl -s -X POST http://localhost:5000/api/tasks/process \
  -H "Content-Type: application/json" \
  -d '...' | jq -r '.task_id')

# 2. 檢查隊列狀態
curl http://localhost:5000/api/tasks/status

# 3. 檢查任務進度
curl http://localhost:5000/api/tasks/$TASK_ID

# 應顯示: "status": "queued" 或 "processing"
```

### 測試 3: 異常處理

```bash
# 測試 1: 驗證失敗 (缺少 input_dir)
curl -X POST http://localhost:5000/api/tasks/process \
  -H "Content-Type: application/json" \
  -d '{}'

# 應返回 400 Bad Request

# 測試 2: 超時異常
# (需要在 task_queue 模擬)

# 測試 3: 網絡異常
# (需要 C# Server 離線)
```

### 測試 4: 並發請求

```bash
# 提交 10 個並發請求
for i in {1..10}; do
  curl -X POST http://localhost:5000/api/tasks/process \
    -H "Content-Type: application/json" \
    -d "{
      \"input_dir\": \"/path/to/video$i\",
      \"output_dir\": \"/path/to/output$i\",
      \"video_id\": \"test-$i\"
    }" &
done

# 應全部 < 100ms 返回
# 任何一個不應超過 1 秒
```

## ⚠️ 回滾計劃

如果發現問題，可以快速回滾:

```bash
# 恢復原始文件
cp server_backup_*.py server.py
cp services/task_queue_backup_*.py services/task_queue.py

# 重啟服務
pkill -f "python server.py"
python server.py
```

## 📊 上線後監控

### 關鍵指標

```python
# 在日誌中監控:

# 1. Flask 響應時間
# [INFO] POST /api/tasks/process - 0.012s (< 100ms ✅)

# 2. 隊列大小
# [INFO] Queue size: 5 (< 100 ✅)

# 3. Redis 連接
# [INFO] Redis connection pool status: 8/10 (OK ✅)

# 4. 任務成功率
# [INFO] Task success rate: 98.5% (> 95% ✅)

# 5. 超時事件
# [INFO] Task timeout: video_123 (監控 ⚠️)
```

### 告警條件

```
🔴 RED: 任何端點響應 > 1 秒
🔴 RED: 隊列大小 > 500
🔴 RED: Redis 連接失敗 3 次
🔴 RED: 任務成功率 < 90%

🟡 YELLOW: Flask 響應 > 500ms
🟡 YELLOW: 隊列大小 > 100
🟡 YELLOW: 超時事件 > 5%
```

## ✅ 最終檢查清單

部署前必須檢查:

- [ ] 所有備份文件已創建
- [ ] Redis 服務運行正常
- [ ] C# Server 可連接
- [ ] 所有依賴已安裝
- [ ] 測試全部通過 (6/6)
- [ ] 團隊已通知部署時間
- [ ] 回滾計劃已備好
- [ ] 監控已配置
- [ ] 文檔已更新

部署中必須檢查:

- [ ] server.py 已替換
- [ ] task_queue.py 已更新
- [ ] 服務已啟動
- [ ] 健康檢查通過
- [ ] 首個請求成功
- [ ] 日誌正常輸出

## 📞 支持聯繫

部署問題聯繫:

- Python Server: 檢查 `server.py` 日誌
- Task Queue: 檢查 `services/task_queue.py` 日誌
- Redis 連接: 檢查 `redis-cli ping`
- C# Server: 檢查 C# 服務日誌

---

## 🎉 部署完成

所有 6 大問題已解決，現在可以安心部署到生產環境！

部署時間估計: 5-10 分鐘
停機時間: < 1 分鐘
回滾時間: < 2 分鐘

