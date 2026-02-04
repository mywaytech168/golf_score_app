# Redis 集成指南

## 概述
TaskQueue 現已升級以支持使用 Redis 作為後端存儲，提供分布式任務隊列和持久化功能。

## 主要改動

### 1. 存儲後端
**從:** 內存中的 Python `Queue` 對象
**到:** Redis 列表和哈希表

### 2. Redis 鍵結構

| 鍵名 | 用途 | 類型 |
|------|------|------|
| `task_queue:pending` | 待處理任務隊列 | List |
| `task_queue:processing` | 處理中任務隊列 | List |
| `task_queue:completed` | 已完成任務隊列 | List |
| `task_queue:failed` | 失敗任務隊列 | List |
| `task:{queueItemId}` | 任務詳情 | Hash |
| `task_lock:{queueItemId}` | 任務鎖 | String |

### 3. 新增功能

#### 分布式支持
- 每個 Worker 都有唯一 ID（self.worker_id）
- 支持多個 Worker 並行處理任務
- 任務狀態同步到 Redis

#### 任務持久化
- 任務數據存儲在 Redis，服務重啟不丟失
- 支持自動清理過期任務（cleanup_old_tasks）
- 默認保留 1 天任務數據

#### 增強的狀態追蹤
```
待處理 → 處理中 → 已完成/失敗
```

#### 新增方法
```python
get_task_info(queue_item_id)  # 獲取任務詳情
cleanup_old_tasks(days=7)      # 清理舊任務
```

## 安裝與配置

### 1. 安裝 Redis

**Windows (使用 WSL2 或 Docker):**
```bash
docker run -d -p 6379:6379 redis:latest
```

**或直接下載:**
- https://redis.io/download
- Windows 版本: https://github.com/microsoftarchive/redis/releases

**Linux/Mac:**
```bash
# Ubuntu/Debian
sudo apt-get install redis-server

# macOS (使用 Homebrew)
brew install redis
```

### 2. 安裝 Python 依賴

```bash
pip install redis
```

**requirements.txt:**
```txt
redis>=4.0.0
```

### 3. 啟動 Redis 服務

```bash
# Linux/Mac
redis-server

# Windows (如果使用二進制版本)
redis-server.exe

# Docker
docker run -d -p 6379:6379 --name redis redis:latest
```

### 4. 配置 Python 服務器

在 `server.py` 中修改初始化代碼：

```python
from services.task_queue import get_task_queue

# Redis 配置
REDIS_HOST = os.getenv('REDIS_HOST', 'localhost')
REDIS_PORT = int(os.getenv('REDIS_PORT', 6379))
REDIS_DB = int(os.getenv('REDIS_DB', 0))
REDIS_PASSWORD = os.getenv('REDIS_PASSWORD', None)

# 初始化任務隊列（帶 Redis）
task_queue = get_task_queue(
    csharp_server_url=CSHARP_SERVER_URL,
    redis_host=REDIS_HOST,
    redis_port=REDIS_PORT,
    redis_db=REDIS_DB,
    redis_password=REDIS_PASSWORD
)

task_queue.start_scheduler()
```

### 5. 環境變量配置

**.env 文件:**
```
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_DB=0
REDIS_PASSWORD=

# 或在 docker-compose 中
REDIS_HOST=redis
REDIS_PORT=6379
```

## API 使用示例

### 1. 添加任務
```python
task_queue.add_task(
    queue_item_id="550e8400-e29b-41d4-a716-446655440000",
    video_id="video-123"
)
```

### 2. 獲取隊列狀態
```python
status = task_queue.get_status()
# {
#     'queueSize': 5,              # 待處理任務數
#     'processingSize': 1,         # 處理中任務數
#     'completedSize': 10,         # 已完成任務數
#     'failedSize': 2,             # 失敗任務數
#     'isProcessing': True,
#     'currentTaskId': 'xxx',
#     'workerId': 'abc123',
#     'timestamp': '2026-02-02T10:30:00'
# }
```

### 3. 獲取任務詳情
```python
task_info = task_queue.get_task_info(queue_item_id)
# {
#     'queueItemId': 'xxx',
#     'videoId': 'video-123',
#     'status': 'completed',
#     'workerId': 'abc123',
#     'startedAt': '2026-02-02T10:30:00',
#     'completedAt': '2026-02-02T10:35:00'
# }
```

### 4. 發送狀態更新
```python
# 處理中 - 帶進度
task_queue.send_processing_status(
    queue_item_id="xxx",
    progress_percent=50,
    processing_time=30
)

# 完成
task_queue.send_completed_status(
    queue_item_id="xxx",
    result_data={'stabilization': {...}},
    processing_time=120
)

# 失敗
task_queue.send_failed_status(
    queue_item_id="xxx",
    error="Mesh stabilization failed",
    processing_time=30
)
```

### 5. 清理舊任務
```python
# 清理 7 天前的任務
task_queue.cleanup_old_tasks(days=7)
```

## Docker Compose 集成

**docker-compose.yml:**
```yaml
version: '3.8'

services:
  redis:
    image: redis:latest
    container_name: golf_redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    command: redis-server --appendonly yes
    networks:
      - golf_network
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  python_server:
    build:
      context: ./meshflow_stabilize_with_audio_V2
      dockerfile: Dockerfile
    container_name: golf_python_server
    ports:
      - "5000:5000"
    environment:
      - REDIS_HOST=redis
      - REDIS_PORT=6379
      - REDIS_DB=0
      - CSHARP_SERVER_URL=http://csharp_server:5001
    depends_on:
      redis:
        condition: service_healthy
    networks:
      - golf_network
    volumes:
      - ./meshflow_stabilize_with_audio_V2:/app

  csharp_server:
    # ... 其他配置

volumes:
  redis_data:

networks:
  golf_network:
    driver: bridge
```

## 性能優化

### 1. 連接池
Redis 客戶端已配置 `decode_responses=True` 以自動解碼，提高性能。

### 2. 批量操作
```python
# 效率低
for item_id in items:
    task_queue.add_task(item_id, video_id)

# 效率高 - 使用 pipeline
pipeline = task_queue.redis_client.pipeline()
for item_id in items:
    task_queue.add_task(item_id, video_id)
pipeline.execute()
```

### 3. 過期時間設置
- 任務數據在 Redis 中自動過期（默認 86400 秒 = 1 天）
- 可通過修改 `TASK_RETENTION` 調整

## 監控與調試

### 1. Redis CLI 命令

```bash
# 連接到 Redis
redis-cli

# 查看所有隊列鍵
KEYS task_queue:*

# 查看待處理隊列大小
LLEN task_queue:pending

# 查看任務詳情
HGETALL task:550e8400-e29b-41d4-a716-446655440000

# 監視所有命令
MONITOR
```

### 2. Python 調試

```python
# 檢查連接
redis_client.ping()

# 查看隊列狀態
print(task_queue.get_status())

# 查看特定任務
print(task_queue.get_task_info("queue-item-id"))
```

## 故障排除

### 問題 1: Redis 連接失敗
```
❌ Redis 連接失敗: Connection refused
```

**解決方案:**
1. 確認 Redis 服務已啟動
2. 檢查主機和端口配置
3. 驗證防火牆設置

### 問題 2: 任務丟失
```
Redis 服務重啟後任務數據不存在
```

**解決方案:**
1. 在 docker-compose 中為 Redis 配置持久化
2. 使用 `redis-server --appendonly yes` 啟用 AOF
3. 定期備份 Redis 數據

### 問題 3: 性能下降
**解決方案:**
1. 定期清理過期任務：`cleanup_old_tasks()`
2. 監視 Redis 內存使用情況
3. 考慮增加 Redis 實例或集群

## 遷移指南

如果從舊的內存隊列遷移：

```python
# 舊代碼
from services.task_queue import TaskQueue
task_queue = TaskQueue(csharp_server_url)

# 新代碼（完全兼容）
from services.task_queue import get_task_queue
task_queue = get_task_queue(csharp_server_url)
# 自動使用 Redis 後端
```

API 完全相同，無需修改現有代碼！

## 相關文件
- [task_queue.py](meshflow_stabilize_with_audio_V2/services/task_queue.py) - 核心實現
- [server.py](meshflow_stabilize_with_audio_V2/server.py) - Flask 應用
- [docker-compose.yml](docker-compose.yml) - 容器編排
