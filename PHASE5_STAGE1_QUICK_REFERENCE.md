# Phase 5 Stage 1 - 快速参考指南

## 📦 模块清单

### 1. distributed_config.py
**配置管理系统** - 管理分布式系统的所有配置

**核心类**:
- `DistributedConfigManager`: 主配置管理器
- `MessageQueueConfig`: 消息队列配置
- `WorkerConfig`: Worker 配置
- `CacheConfig`: 缓存配置
- `DatabaseConfig`: 数据库配置
- `LoadBalancerConfig`: 负载均衡配置
- `FailoverConfig`: 故障转移配置
- `MonitoringConfig`: 监控配置

**常用方法**:
```python
config = get_distributed_config()
config.load_from_file("config.json")          # 加载配置
config.update_config("worker", concurrency=8) # 更新配置
config.validate_config()                       # 验证配置
config.get_config_summary()                    # 获取摘要
config.save_to_file()                          # 保存配置
```

---

### 2. message_queue.py
**消息队列系统** - RabbitMQ 的高级封装

**核心类**:
- `Message`: 消息数据结构
- `RabbitMQConnection`: 连接管理
- `MessageQueueManager`: 队列管理
- `JsonSerializer`: JSON 序列化

**队列常量** (MessageQueueManager.QUEUES):
```python
"video_processing"  → "q.video.processing"
"batch_upload"      → "q.batch.upload"
"stats_update"      → "q.stats.update"
"notifications"     → "q.notifications"
"monitoring"        → "q.monitoring"
"dead_letter"       → "q.dead.letter"
```

**常用方法**:
```python
mq = get_message_queue("localhost", 5672)
mq.publish_message(queue_name, message)      # 发布消息
mq.consume_messages(queue_name, callback)    # 消费消息
mq.get_queue_stats(queue_name)              # 获取队列统计
mq.purge_queue(queue_name)                  # 清空队列
mq.delete_queue(queue_name)                 # 删除队列
```

**消息示例**:
```python
from message_queue import Message, MessageType

msg = Message(
    type=MessageType.VIDEO_PROCESSING.value,
    payload={"video_id": "123", "format": "mp4"},
    correlation_id="corr_456",
    priority=7,
    timeout=300
)
mq.publish_message(mq.QUEUES["video_processing"], msg)
```

---

### 3. worker_manager.py
**Worker 管理系统** - 分布式 Worker 的生命周期管理

**核心类**:
- `WorkerManager`: Worker 管理器
- `WorkerInfo`: Worker 信息
- `WorkerMetrics`: 性能指标
- `WorkerStatus`: Worker 状态枚举
- `HealthStatus`: 健康状态枚举

**Worker 状态**:
- `IDLE`: 空闲
- `PROCESSING`: 处理中
- `OVERLOADED`: 过载
- `UNHEALTHY`: 不健康
- `OFFLINE`: 离线

**健康状态**:
- `HEALTHY`: 健康
- `WARNING`: 警告 (CPU > 80% 或内存 > 85%)
- `CRITICAL`: 严重 (CPU > 95% 或内存 > 95%)

**常用方法**:
```python
manager = get_worker_manager()

# 注册/注销 Worker
manager.register_worker("worker_1", "localhost", 8000, 
                       capabilities=["video_processing"])
manager.unregister_worker("worker_1")

# 处理心跳
manager.heartbeat("worker_1", {
    'cpu_usage': 45.0,
    'memory_usage': 60.0,
    'active_tasks': 5,
    'completed_tasks': 100,
    'failed_tasks': 2,
    'avg_task_time': 5.5,
})

# 故障检测
offline = manager.detect_offline_workers()

# 任务管理
manager.add_task("worker_1", "task_123")
manager.remove_task("worker_1", "task_123")

# 查询和统计
healthy = manager.get_healthy_workers()
least_loaded = manager.get_least_loaded_worker()
stats = manager.get_worker_statistics()
worker_info = manager.get_worker_info("worker_1")

# 清理
manager.cleanup_offline_workers()
```

---

## 🔌 集成示例

### 示例 1: 完整流程

```python
from distributed_config import get_distributed_config
from message_queue import get_message_queue, Message, MessageType
from worker_manager import get_worker_manager

# 初始化系统
config = get_distributed_config()
mq = get_message_queue(
    config.message_queue.host,
    config.message_queue.port
)
manager = get_worker_manager()

# 1. 注册 Worker
manager.register_worker("worker_1", "localhost", 8000)

# 2. Worker 发送心跳
metrics = {
    'cpu_usage': 40.0,
    'memory_usage': 50.0,
    'active_tasks': 0,
    'completed_tasks': 100,
    'failed_tasks': 1,
    'avg_task_time': 5.5,
}
manager.heartbeat("worker_1", metrics)

# 3. 提交任务到消息队列
msg = Message(
    type=MessageType.VIDEO_PROCESSING.value,
    payload={"video_id": "video_123"},
    correlation_id="corr_123",
    priority=5
)
mq.publish_message(mq.QUEUES["video_processing"], msg)

# 4. 为 Worker 分配任务
manager.add_task("worker_1", "task_123")

# 5. 监控 Worker
stats = manager.get_worker_statistics()
print(f"总 Worker: {stats['total_workers']}")
print(f"活跃任务: {stats['total_active_tasks']}")

# 6. 检测故障
offline = manager.detect_offline_workers()
if offline:
    print(f"离线 Worker: {offline}")
```

### 示例 2: 异步任务处理

```python
import threading
from message_queue import get_message_queue, Message

def process_messages():
    mq = get_message_queue()
    
    def callback(msg):
        print(f"处理消息: {msg.payload}")
        return True
    
    # 在单独的线程中消费消息
    mq.consume_messages(mq.QUEUES["video_processing"], callback)

# 启动消费线程
consumer_thread = threading.Thread(target=process_messages)
consumer_thread.daemon = True
consumer_thread.start()

# 主线程发布消息
mq = get_message_queue()
msg = Message(
    type="video.processing",
    payload={"video_id": "123"}
)
mq.publish_message(mq.QUEUES["video_processing"], msg)
```

### 示例 3: 动态配置更新

```python
from distributed_config import get_distributed_config

config = get_distributed_config()

# 更新 Worker 并发数
config.update_config("worker", concurrency=8)

# 更新负载均衡策略
config.update_config("load_balancer", 
                    strategy="least_connections")

# 验证更新
validation = config.validate_config()
print(f"配置有效: {all(validation.values())}")

# 保存到文件
config.save_to_file()
```

---

## 📊 配置文件示例

### config.json

```json
{
  "version": "1.0.0",
  "created_at": "2026-02-02T10:00:00",
  "updated_at": "2026-02-02T10:00:00",
  "message_queue": {
    "backend": "rabbitmq",
    "host": "localhost",
    "port": 5672,
    "username": "guest",
    "password": "guest",
    "vhost": "/",
    "max_connections": 20,
    "connection_timeout": 30,
    "heartbeat": 60
  },
  "worker": {
    "mode": "async",
    "concurrency": 4,
    "prefetch_count": 1,
    "max_retries": 3,
    "timeout": 300,
    "max_memory_mb": 512,
    "task_soft_time_limit": 250,
    "task_hard_time_limit": 300
  },
  "cache": {
    "backend": "redis",
    "host": "localhost",
    "port": 6379,
    "db": 0,
    "password": null,
    "max_connections": 10,
    "socket_timeout": 5,
    "socket_connect_timeout": 5,
    "ttl_seconds": 3600
  },
  "database": {
    "master_url": "postgresql://user:pass@localhost:5432/meshflow",
    "slave_urls": [
      "postgresql://user:pass@slave1:5432/meshflow"
    ],
    "pool_size": 20,
    "max_overflow": 10,
    "pool_timeout": 30,
    "pool_recycle": 3600,
    "read_from_slave": true
  },
  "load_balancer": {
    "strategy": "round_robin",
    "max_retries": 3,
    "retry_delay": 1.0,
    "connection_timeout": 10,
    "read_timeout": 30,
    "health_check_interval": 10,
    "health_check_timeout": 5,
    "sticky_session": false
  },
  "failover": {
    "enabled": true,
    "strategy": "graceful",
    "timeout": 30,
    "max_attempts": 3,
    "rollback_enabled": true,
    "notify_on_failover": true
  },
  "monitoring": {
    "enabled": true,
    "prometheus_port": 9090,
    "metrics_interval": 60,
    "log_level": "INFO",
    "enable_distributed_trace": true,
    "jaeger_agent_host": "localhost",
    "jaeger_agent_port": 6831,
    "sample_rate": 0.1
  }
}
```

---

## 🚀 常见操作

### 操作 1: 启动系统

```bash
# 1. 创建 config.json (参考上面的示例)

# 2. 启动 RabbitMQ
docker run -d --name rabbitmq \
  -p 5672:5672 \
  -p 15672:15672 \
  -e RABBITMQ_DEFAULT_USER=guest \
  -e RABBITMQ_DEFAULT_PASS=guest \
  rabbitmq:3.12-management

# 3. 启动 Redis
docker run -d --name redis \
  -p 6379:6379 \
  redis:7-alpine

# 4. 初始化 Python 环境
pip install pika==1.3.1

# 5. 验证连接
python distributed_config.py
python message_queue.py
python worker_manager.py
```

### 操作 2: 监控 Worker

```python
from worker_manager import get_worker_manager
import time

manager = get_worker_manager()

while True:
    # 检测离线 Worker
    offline = manager.detect_offline_workers()
    
    # 获取统计信息
    stats = manager.get_worker_statistics()
    
    print(f"在线 Worker: {stats['healthy_workers']}/{stats['total_workers']}")
    print(f"活跃任务: {stats['total_active_tasks']}")
    print(f"平均 CPU: {stats['avg_cpu_usage']}%")
    
    time.sleep(10)
```

### 操作 3: 故障转移

```python
from worker_manager import get_worker_manager

manager = get_worker_manager()

# 检测离线 Worker
offline = manager.detect_offline_workers()

for offline_worker in offline:
    print(f"处理离线 Worker: {offline_worker}")
    
    # 获取该 Worker 的任务
    tasks = manager.worker_tasks[offline_worker]
    
    # 转移任务到健康 Worker
    for task_id in tasks:
        new_worker = manager.get_least_loaded_worker()
        if new_worker:
            manager.add_task(new_worker, task_id)
            manager.remove_task(offline_worker, task_id)
            print(f"  任务 {task_id}: {offline_worker} → {new_worker}")

# 清理离线 Worker
removed = manager.cleanup_offline_workers()
print(f"清理了 {removed} 个 Worker")
```

---

## 📈 性能调优

### 消息队列优化

```python
# 增加预取数量以提高吞吐量
config.update_config("worker", prefetch_count=4)

# 调整连接池大小
config.update_config("message_queue", max_connections=30)
```

### Worker 优化

```python
# 增加并发数
config.update_config("worker", concurrency=8)

# 降低任务超时时间
config.update_config("worker", timeout=200)

# 调整软/硬限制
config.update_config("worker", 
                    task_soft_time_limit=150,
                    task_hard_time_limit=200)
```

### 缓存优化

```python
# 增加 TTL
config.update_config("cache", ttl_seconds=7200)

# 增加连接池
config.update_config("cache", max_connections=20)
```

---

## 🔍 故障排查

### 问题 1: 无法连接 RabbitMQ

```python
from message_queue import RabbitMQConnection

try:
    conn = RabbitMQConnection("localhost", 5672, "guest", "guest")
    print("连接成功")
except Exception as e:
    print(f"连接失败: {e}")
    # 检查:
    # 1. RabbitMQ 是否运行
    # 2. 主机和端口是否正确
    # 3. 用户名和密码是否正确
```

### 问题 2: Worker 显示为离线

```python
from worker_manager import get_worker_manager

manager = get_worker_manager()

# 检查 Worker 的最后心跳时间
worker = manager.workers.get("worker_1")
if worker:
    print(f"最后心跳: {worker.last_heartbeat}")
    
    # 重新发送心跳
    metrics = {
        'cpu_usage': 40.0,
        'memory_usage': 50.0,
        'active_tasks': 0,
        'completed_tasks': 100,
        'failed_tasks': 1,
        'avg_task_time': 5.5,
    }
    manager.heartbeat("worker_1", metrics)
```

### 问题 3: 队列堆积消息

```python
from message_queue import get_message_queue

mq = get_message_queue()

# 获取队列统计
stats = mq.get_queue_stats(mq.QUEUES["video_processing"])
print(f"队列中的消息数: {stats['message_count']}")

# 如果需要清空队列
if stats['message_count'] > 10000:
    mq.purge_queue(mq.QUEUES["video_processing"])
    print("队列已清空")
```

---

## 📚 环境变量

支持通过环境变量覆盖配置:

```bash
# 消息队列
export MQ_HOST=mq.example.com
export MQ_PORT=5672
export MQ_USER=admin
export MQ_PASS=password

# Worker
export WORKER_CONCURRENCY=8
export WORKER_MODE=async

# 缓存
export CACHE_HOST=cache.example.com
export CACHE_PORT=6379

# 数据库
export DATABASE_URL=postgresql://...

# 监控
export ENABLE_MONITORING=true
```

---

## ✅ 检查清单

启动系统前:
- [ ] RabbitMQ 已启动并可访问
- [ ] Redis 已启动 (可选)
- [ ] PostgreSQL 已启动 (可选)
- [ ] config.json 已创建
- [ ] 环境变量已设置 (可选)
- [ ] Python 依赖已安装

系统运行中:
- [ ] 定期检查 Worker 心跳
- [ ] 监控队列消息数量
- [ ] 跟踪错误率
- [ ] 检查 Worker 健康状态

---

## 📞 支持

如有问题，请检查:
1. 日志文件 (logging 配置)
2. RabbitMQ 管理界面 (http://localhost:15672)
3. 系统指标 (Worker 统计)
4. 配置文件 (config.json)

---

**Phase 5 Stage 1 完成日期**: 2026-02-02  
**下一阶段**: Stage 2 (Week 3-4) - 批量处理和任务调度
