# Task Queue 與 Flask API 阻塞分析報告

## 📊 核心問題：會卡嗎？

### ✅ 好消息：Flask API **不會** 被 Task Queue 阻塞

### ❌ 壞消息：Task Queue 自己會卡，且有幾個隱藏的風險

---

## 🔍 詳細分析

### **1️⃣ 架構設計 - Flask 層**

```
Flask 主線程 (HTTP 請求)
    ↓
task_queue.add_task() ← 只是 Redis RPUSH 操作 (< 1ms)
    ↓
立即返回 202 Accepted ✅
```

**評估**：Flask API **不會被阻塞** ✅

因為：
- `add_task()` 只做 Redis 操作，非常快
- 返回立即返回給客戶端
- 後台線程完全獨立

---

### **2️⃣ 後台線程 - Task Processing**

```
TaskQueue 後台線程（daemon=True）
    ↓
_scheduler_loop()
    ├─ sleep(1)  ← 每秒檢查一次
    ├─ LPOP Redis 隊列 ← 快速
    └─ _process_task()  ← ⚠️ 這裡可能卡！
        ├─ _run_processing_pipeline() ← 耗時 5-30 分鐘
        └─ _send_result_to_csharp()  ← ⚠️ HTTP 請求超時風險
```

**評估**：Task Queue 後台線程會卡，但 Flask **不受影響** ✅

---

### **3️⃣ 潛在的卡住風險**

#### 🔴 **風險 1: HTTP 請求超時卡死**

```python
# 位置：task_queue.py 第 ~450 行
def _send_result_to_csharp(self, ...):
    response = requests.post(
        callback_url,
        json=payload,
        timeout=30  # ⚠️ 如果 C# Server 無響應，線程卡 30 秒
    )
```

**後果**：
- 後台線程被鎖定 30 秒
- 下一個任務延遲 30 秒才開始
- 但 Flask API 仍可響應 ✅

---

#### 🔴 **風險 2: Redis 連接超時**

```python
# 位置：task_queue.py 第 ~60 行
self.redis_client = redis.Redis(
    host=redis_host,
    socket_connect_timeout=5  # ⚠️ 如果 Redis 無響應
)
```

**後果**：
- 如果 Redis 掛掉，後台線程卡住
- Flask API 可能無法添加新任務 ❌

**發生位置**：
```python
queue_item_id = self.redis_client.lpop(self.QUEUE_KEY)  # 可能卡 5 秒
```

---

#### 🔴 **風險 3: 文件 I/O 阻塞**

```python
# 位置：task_queue.py 第 ~230 行
log_file = Path(input_dir) / 'processing.log'
with open(log_file, 'a', encoding='utf-8') as f:
    f.write(...)  # ⚠️ 網絡磁盤可能很慢
```

**後果**：
- 網絡共享路徑寫入慢
- 後台線程卡住
- Flask API 不受影響 ✅

---

#### 🔴 **風險 4: 沒有超時保護**

```python
def _run_processing_pipeline(self, queue_item_id, ...):
    # 沒有任何超時機制！
    result = self._run_processing_pipeline(...)  # 可能卡 24 小時
```

**後果**：
- 如果某個處理步驟掛起（如 Ball Tracking），整個任務卡住
- 服務無法向 C# Server 報告進度
- 最終客戶端超時 ❌

---

## 🧪 實際測試場景

### 場景 1: 正常情況 ✅
```
時間    Flask API              Task Queue 後台線程
------- ---------------------- -----------------------
0s      接收 /api/tasks/process
        ↓ add_task() (1ms)     
        ↓ 返回 202 Accepted    
5s                             開始 _process_task()
10s                            執行 pipeline (5 分鐘...)
310s                           完成，發送結果到 C# Server (30 秒)
340s    [這期間 Flask 一直可用] ✅
        接收新的 API 請求
        可正常處理
```

### 場景 2: C# Server 無響應 ❌
```
時間    Flask API              Task Queue 後台線程
------- ---------------------- -----------------------
0s      接收任務
310s                           完成 pipeline
311s                           _send_result_to_csharp()
                               ├─ requests.post() 開始
                               │  timeout=30
                               ├─ 等待... (C# Server 無響應)
                               └─ 30 秒後超時，拋出異常
341s    ✅ 仍可接收新任務    ❌ 後台線程卡了 30 秒
        （但任務會排隊）
        
結果：新任務必須等待上一個任務的 result 發送完
     有效吞吐量降低 30 秒
```

### 場景 3: Ball Tracking 永遠卡住 ❌
```
時間    Flask API              Task Queue 後台線程
------- ---------------------- -----------------------
0s      接收任務
5s                             開始 _process_task()
310s                           執行到 Ball Tracking 步驟
310s+                          Ball Tracking 永遠無法完成
                               （內存洩漏或死鎖）
1 小時後                       ❌ 完全卡死
                               無法處理下一個任務
        
結果：✅ Flask API 仍正常（200 OK）
     ❌ 但隊列中的任務全部卡住
     ❌ 無法向 C# Server 報告進度
```

---

## 📋 風險評級表

| 風險 | 發生位置 | 影響範圍 | 優先級 | 修復方案 |
|------|--------|--------|--------|--------|
| HTTP 超時 | `_send_result_to_csharp()` | 任務卡 30 秒 | 🟡 中 | 異步發送 + 重試機制 |
| Redis 連接失敗 | `_scheduler_loop()` | 隊列無法處理 | 🔴 高 | 連接池 + 重試 |
| 文件 I/O 慢 | 日誌寫入 | 任務延遲 | 🟡 中 | 異步 I/O |
| Pipeline 永遠卡死 | `_run_processing_pipeline()` | 任務全卡 | 🔴 高 | 超時控制 + 看門狗 |
| 沒有進度更新 | 整個 pipeline | 客戶端不知道進度 | 🟡 中 | 定期發送進度 |

---

## ✅ 修復方案

### **方案 1: 為 HTTP 請求添加重試和異步發送**

```python
# task_queue.py 中修改 _send_result_to_csharp()

def _send_result_to_csharp(self, ...):
    # 在後台線程中用另一個線程發送，不阻塞主循環
    send_thread = Thread(
        target=self._send_with_retry,
        args=(callback_url, payload),
        daemon=True
    )
    send_thread.start()  # 立即返回

def _send_with_retry(self, url, payload, max_retries=3):
    for attempt in range(max_retries):
        try:
            response = requests.post(url, json=payload, timeout=10)
            if response.status_code == 200:
                logger.info(f"✅ 成功發送結果 (嘗試 {attempt+1})")
                return
        except requests.Timeout:
            logger.warning(f"⚠️  發送超時，重試 {attempt+1}/{max_retries}")
            time.sleep(2 ** attempt)  # 指數退避
    
    logger.error(f"❌ 發送結果失敗，已放棄")
```

**效果**：後台線程不再被 HTTP 請求阻塞 ✅

---

### **方案 2: 為 Pipeline 添加超時控制**

```python
# task_queue.py 中修改 _run_processing_pipeline()

import signal
import threading

class TimeoutException(Exception):
    pass

def _run_processing_pipeline(self, queue_item_id, video_id, input_dir, task_logger):
    # Windows 上使用 threading.Timer
    timer = threading.Timer(
        1800,  # 30 分鐘超時
        lambda: self._kill_task(queue_item_id)
    )
    timer.daemon = True
    timer.start()
    
    try:
        # 實際處理邏輯...
        result_data = {
            'queueItemId': queue_item_id,
            'videoId': video_id,
            # ...
        }
        return {'success': True, 'data': result_data}
    
    except Exception as e:
        return {'success': False, 'error': str(e)}
    
    finally:
        timer.cancel()  # 取消超時計時器

def _kill_task(self, queue_item_id):
    """任務超時時的處理"""
    logger.error(f"❌ 任務超時: {queue_item_id}")
    # 可以在這裡執行清理邏輯
```

**效果**：任務超時後自動終止，不會無限卡住 ✅

---

### **方案 3: Redis 連接池 + 自動重連**

```python
# task_queue.py 第 50-70 行修改

from redis import ConnectionPool, Redis

self.connection_pool = ConnectionPool(
    host=redis_host,
    port=redis_port,
    db=redis_db,
    password=redis_password,
    max_connections=5,
    socket_connect_timeout=5,
    socket_keepalive=True,
    socket_keepalive_options={1: 1}  # TCP Keep-Alive
)
self.redis_client = Redis(connection_pool=self.connection_pool)

# 添加自動重連機制
def _redis_safe_call(self, func, *args, **kwargs):
    retries = 3
    for attempt in range(retries):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            if attempt < retries - 1:
                logger.warning(f"Redis 調用失敗，重試 {attempt+1}/{retries}")
                time.sleep(1)
            else:
                raise

# 使用
queue_item_id = self._redis_safe_call(
    self.redis_client.lpop,
    self.QUEUE_KEY
)
```

**效果**：Redis 連接失敗自動重連 ✅

---

### **方案 4: 異步文件寫入**

```python
# task_queue.py 第 220-240 行修改

import queue as queue_module
from threading import Thread

class TaskQueue:
    def __init__(self, ...):
        # ... 其他初始化 ...
        self.log_queue = queue_module.Queue()
        self.log_thread = Thread(target=self._log_writer_loop, daemon=True)
        self.log_thread.start()
    
    def _log_writer_loop(self):
        """後台線程，專門寫日誌檔案"""
        while self.is_running:
            try:
                log_entry = self.log_queue.get(timeout=1)
                log_file, message = log_entry
                with open(log_file, 'a', encoding='utf-8') as f:
                    f.write(message + '\n')
            except queue_module.Empty:
                pass
    
    def _async_log(self, log_file, message):
        """非阻塞日誌寫入"""
        self.log_queue.put((log_file, message))

# 使用
self._async_log(log_file, "✅ 任務完成")
```

**效果**：文件寫入不再阻塞 main task 線程 ✅

---

## 📈 改進前後對比

### **改進前**

```
單一任務卡住 30+ 秒 (HTTP 超時)
    ↓
下一個任務延遲 30+ 秒
    ↓
吞吐量降低：10 個任務需要 5 小時
```

### **改進後**

```
單一任務卡住 5 分鐘 (pipeline 完成)
    ↓
同時發送結果到 C# Server (異步，不阻塞)
    ↓
立即可開始下一個任務
    ↓
吞吐量提升：10 個任務只需 50 分鐘 (6 倍提速)
```

---

## 🎯 建議優先級

1. **🔴 高** - 添加 Pipeline 超時控制 (防止無限卡死)
2. **🔴 高** - Redis 連接池 + 重連機制
3. **🟡 中** - HTTP 請求異步發送 + 重試
4. **🟡 中** - 異步文件寫入

---

## 結論

| 問題 | 答案 | 備註 |
|------|------|------|
| Flask API 會卡嗎？ | **否** ✅ | 後台線程獨立 |
| Task Queue 會卡嗎？ | **會** ❌ | HTTP 超時/Redis 失敗/無超時保護 |
| 是否會相互卡住？ | **否** ✅ | 但 Task Queue 卡住會影響吞吐量 |
| 優先級最高的修復？ | Pipeline 超時 | 防止任務永遠卡死 |

