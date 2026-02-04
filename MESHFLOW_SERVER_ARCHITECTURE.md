# MeshFlow 稳定化服务器 - 架构设计文档

## 1. 整体系统架构

```
┌─────────────────────────────────────────────────────────────────┐
│                    Flutter 移动应用                              │
│                (Golf Score App - Recording)                      │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                    API Gateway / Load Balancer                   │
│                     (Nginx / HAProxy)                            │
└────────────────────────┬────────────────────────────────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
    ┌────────┐      ┌────────┐      ┌────────┐
    │ API    │      │ API    │      │ API    │
    │Server 1│      │Server 2│      │Server N│
    │ (FastAPI)    │ (FastAPI)    │ (FastAPI)
    └────┬───┘      └────┬───┘      └────┬───┘
         │               │               │
         └───────────────┼───────────────┘
                         │
        ┌────────────────┼────────────────┐
        ▼                ▼                ▼
    ┌─────────┐    ┌─────────┐    ┌─────────┐
    │ Worker  │    │ Worker  │    │ Worker  │
    │ (Celery)│    │ (Celery)│    │ (Celery)│
    │ + Mesh  │    │ + Mesh  │    │ + Mesh  │
    │Flow     │    │Flow     │    │Flow     │
    └────┬────┘    └────┬────┘    └────┬────┘
         │              │              │
         └──────────────┼──────────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
    ┌─────────┐   ┌─────────┐   ┌─────────┐
    │ Redis   │   │Database │   │ Storage │
    │(Cache + │   │(Job Info)   │(Video  │
    │ Queue)  │   │PostgreSQL   │ Files) │
    └─────────┘   └─────────┘   └─────────┘
                                    │
                    ┌───────────────┼───────────────┐
                    ▼               ▼               ▼
                ┌────────┐     ┌────────┐     ┌────────┐
                │ Local  │     │ S3     │     │ OSS    │
                │Storage │     │ AWS    │     │阿里云  │
                └────────┘     └────────┘     └────────┘
```

---

## 2. 数据流

### 提交任务流程
```
用户上传视频 (Flutter)
    │
    ▼
POST /api/stabilize
  - video_url 或 video_file
  - stabilization_parameters (可选)
    │
    ▼
API Server 验证输入
    │
    ├─ 检查视频格式/大小
    ├─ 验证参数范围
    └─ 生成 job_id (UUID)
    │
    ▼
创建数据库记录
  - status: "pending"
  - created_at: now
    │
    ▼
提交到任务队列 (Redis)
  - Celery Task: process_video_stabilization(job_id)
    │
    ▼
返回给客户端
  {
    "job_id": "uuid-xxx",
    "status": "pending",
    "estimated_duration": 120 (seconds)
  }
```

### 处理任务流程
```
Worker 获取任务
    │
    ▼
更新数据库: status = "processing"
    │
    ▼
从存储下载视频
    │
    ▼
分析视频元数据
  - fps, resolution, duration
  - 检查振动段
    │
    ▼
创建 MeshFlowStabilizer 实例
    │
    ├─ 设置进度回调
    └─ 开始处理
    │
    ▼ (逐帧处理，实时进度报告)
┌─────────────────────────┐
│ for frame in frames:    │
│   - 特征检测            │
│   - 运动估计            │
│   - 稳定化计算          │
│   - 更新进度 → Redis    │
│   - 检查取消信号        │
└─────────────────────────┘
    │
    ▼
生成稳定化视频
    │
    ▼
上传到存储
    │
    ▼
更新数据库
  - status: "completed"
  - output_url: "s3://..."
  - completed_at: now
    │
    ▼
发送通知 (可选: webhook/邮件)
```

### 查询进度流程
```
GET /api/jobs/{job_id}/progress
    │
    ▼
从 Redis 获取进度
    │
    ▼
返回给客户端
  {
    "job_id": "uuid-xxx",
    "status": "processing",
    "progress": {
      "percentage": 45,
      "current_frame": 450,
      "total_frames": 1000,
      "eta_seconds": 65,
      "elapsed_seconds": 55
    }
  }
```

---

## 3. 核心组件详设

### 3.1 API 服务器 (FastAPI)

```python
# main.py
from fastapi import FastAPI, HTTPException, BackgroundTasks
from fastapi.responses import JSONResponse
from contextlib import asynccontextmanager

app = FastAPI(title="MeshFlow Stabilization Server")

# 依赖注入
class AppState:
    db: Database
    cache: Redis
    storage: BaseStorage
    celery: Celery

@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动
    await init_services()
    yield
    # 关闭
    await cleanup_services()

app = FastAPI(lifespan=lifespan)

# ============ 路由 ============

@app.get("/health")
async def health_check():
    """健康检查"""
    return {"status": "ok"}

@app.post("/api/stabilize")
async def submit_stabilization(
    request: StabilizationRequest,
    background_tasks: BackgroundTasks
) -> StabilizationResponse:
    """
    提交视频稳定化任务
    
    request:
      - video_url: str
      - parameters: StabilizationParameters (可选)
    
    response:
      - job_id: UUID
      - status: "pending"
      - estimated_duration: float (秒)
    """
    # 1. 验证
    await validate_video_url(request.video_url)
    params = request.parameters or StabilizationParameters()
    
    # 2. 创建任务记录
    job = await create_job(
        video_url=request.video_url,
        parameters=params.dict()
    )
    
    # 3. 提交到队列
    task = process_video_stabilization.delay(job.id)
    
    return StabilizationResponse(
        job_id=job.id,
        status="pending",
        estimated_duration=estimate_duration(request.video_url)
    )

@app.get("/api/jobs/{job_id}")
async def get_job_status(job_id: UUID) -> JobStatusResponse:
    """获取任务状态"""
    job = await db.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404, detail="Job not found")
    
    return JobStatusResponse(
        job_id=job.id,
        status=job.status,
        output_url=job.output_url,
        error_message=job.error_message
    )

@app.get("/api/jobs/{job_id}/progress")
async def get_job_progress(job_id: UUID) -> ProgressResponse:
    """获取详细进度"""
    job = await db.get_job(job_id)
    if not job:
        raise HTTPException(status_code=404)
    
    progress = await cache.get_progress(job_id)
    
    return ProgressResponse(
        job_id=job_id,
        status=job.status,
        progress=progress
    )

@app.delete("/api/jobs/{job_id}")
async def cancel_job(job_id: UUID):
    """取消任务"""
    job = await db.get_job(job_id)
    await cache.set_cancel_flag(job_id, True)
    return {"status": "cancelled"}

@app.get("/api/parameters/defaults")
async def get_default_parameters():
    """获取默认参数"""
    return StabilizationParameters().dict()

@app.post("/api/parameters/validate")
async def validate_parameters(params: StabilizationParameters):
    """验证参数"""
    try:
        params.validate()
        return {"valid": True}
    except ValidationError as e:
        return {"valid": False, "errors": e.errors()}
```

### 3.2 Celery Worker

```python
# tasks.py
from celery import Celery
from celery.utils.log import get_task_logger
import asyncio

celery_app = Celery("meshflow")
logger = get_task_logger(__name__)

@celery_app.task(
    bind=True,
    max_retries=3,
    default_retry_delay=60
)
def process_video_stabilization(self, job_id: str):
    """
    主处理任务
    
    参数:
      - job_id: 任务 ID
    
    流程:
      1. 从数据库获取任务配置
      2. 下载视频
      3. 运行 MeshFlow 处理
      4. 上传结果
      5. 更新数据库
    """
    try:
        job = db.get_job(job_id)
        job.status = "processing"
        job.started_at = now()
        db.save_job(job)
        
        # 初始化进度跟踪
        progress_tracker = ProgressTracker(job_id, cache)
        
        # 下载视频
        logger.info(f"Downloading video for job {job_id}")
        video_path = download_video(job.video_url)
        
        # 运行 MeshFlow
        logger.info(f"Processing video for job {job_id}")
        processor = VideoProcessor(
            progress_callback=progress_tracker.update
        )
        
        # 检查取消信号
        processor.set_cancel_checker(
            lambda: cache.get_cancel_flag(job_id)
        )
        
        output_path = processor.stabilize(
            video_path=video_path,
            parameters=job.parameters,
            progress_tracker=progress_tracker
        )
        
        # 上传结果
        logger.info(f"Uploading result for job {job_id}")
        output_url = upload_file(output_path, f"outputs/{job_id}/video.mp4")
        
        # 更新数据库
        job.status = "completed"
        job.output_url = output_url
        job.completed_at = now()
        db.save_job(job)
        
        logger.info(f"Job {job_id} completed successfully")
        return {"status": "completed", "output_url": output_url}
        
    except Exception as exc:
        logger.error(f"Job {job_id} failed: {str(exc)}")
        
        job.status = "failed"
        job.error_message = str(exc)
        db.save_job(job)
        
        # 重试逻辑
        if self.request.retries < self.max_retries:
            raise self.retry(exc=exc)
        else:
            logger.error(f"Job {job_id} failed after {self.max_retries} retries")
```

### 3.3 进度跟踪

```python
# progress_tracker.py
class ProgressTracker:
    def __init__(self, job_id: str, cache: Redis):
        self.job_id = job_id
        self.cache = cache
        self.total_frames = None
        self.start_time = time.time()
    
    def set_total_frames(self, total: int):
        self.total_frames = total
    
    def update(self, current_frame: int):
        """更新进度信息"""
        elapsed = time.time() - self.start_time
        
        if current_frame > 0 and self.total_frames:
            # 计算 ETA
            fps = current_frame / elapsed
            remaining = self.total_frames - current_frame
            eta = remaining / fps if fps > 0 else 0
            
            percentage = (current_frame / self.total_frames) * 100
        else:
            eta = 0
            percentage = 0
        
        progress = {
            "percentage": percentage,
            "current_frame": current_frame,
            "total_frames": self.total_frames,
            "eta_seconds": eta,
            "elapsed_seconds": elapsed,
            "updated_at": datetime.now().isoformat()
        }
        
        self.cache.setex(
            f"progress:{self.job_id}",
            3600,  # 1小时过期
            json.dumps(progress)
        )
```

### 3.4 MeshFlow 处理器包装

```python
# meshflow_processor.py
class VideoProcessor:
    def __init__(self, progress_callback=None):
        self.stabilizer = MeshFlowStabilizer()
        self.progress_callback = progress_callback
        self.cancel_checker = None
    
    def set_cancel_checker(self, checker):
        """设置取消检查函数"""
        self.cancel_checker = checker
    
    def stabilize(self, video_path: str, parameters: dict, 
                  progress_tracker=None) -> str:
        """
        稳定化视频
        
        参数:
          - video_path: 输入视频路径
          - parameters: 稳定化参数
          - progress_tracker: 进度跟踪器
        
        返回:
          - 输出视频路径
        """
        # 提取参数
        params = StabilizationParameters(**parameters)
        
        # 读取视频
        frames, fps, num_frames = read_video(video_path)
        progress_tracker.set_total_frames(num_frames)
        
        # 运行稳定化
        result = self.stabilizer.stabilize_segment_only(
            input_path=video_path,
            output_path="/tmp/stabilized.mp4",
            AUTO_SHAKE_SEGMENT=params.auto_shake_detection,
            SHAKE_SMOOTH_WIN=params.shake_smooth_window,
            SHAKE_THRESH_K=params.shake_threshold_k,
            # ... 其他参数
        )
        
        return result["output"]
```

---

## 4. 数据库模型

### Job 表
```sql
CREATE TABLE jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL,
    video_url TEXT NOT NULL,
    status ENUM('pending', 'processing', 'completed', 'failed', 'cancelled'),
    parameters JSONB,
    output_url TEXT,
    error_message TEXT,
    created_at TIMESTAMP DEFAULT now(),
    started_at TIMESTAMP,
    completed_at TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_jobs_user_id ON jobs(user_id);
CREATE INDEX idx_jobs_status ON jobs(status);
CREATE INDEX idx_jobs_created_at ON jobs(created_at DESC);
```

### ProcessingLog 表
```sql
CREATE TABLE processing_logs (
    id SERIAL PRIMARY KEY,
    job_id UUID NOT NULL,
    level VARCHAR(20),
    message TEXT,
    timestamp TIMESTAMP DEFAULT now(),
    FOREIGN KEY (job_id) REFERENCES jobs(id) ON DELETE CASCADE
);

CREATE INDEX idx_logs_job_id ON processing_logs(job_id);
```

---

## 5. 配置管理

```yaml
# config.yaml
server:
  host: "0.0.0.0"
  port: 8000
  workers: 4
  log_level: "INFO"

database:
  url: "postgresql://user:pass@localhost/meshflow"
  pool_size: 20
  echo: false

redis:
  url: "redis://localhost:6379/0"
  timeout: 5

celery:
  broker: "redis://localhost:6379/1"
  backend: "redis://localhost:6379/2"
  workers: 4
  worker_prefetch_multiplier: 1
  worker_max_tasks_per_child: 1000

storage:
  backend: "local"  # local, s3, oss
  local:
    base_path: "/data/meshflow"
  s3:
    bucket: "meshflow-videos"
    region: "us-east-1"
  oss:
    bucket: "meshflow-videos"
    endpoint: "oss-cn-shanghai.aliyuncs.com"

meshflow:
  mesh_row_count: 16
  mesh_col_count: 16
  feature_ellipse_row_count: 10
  feature_ellipse_col_count: 10
  temporal_smoothing_radius: 10
  optimization_num_iterations: 80
  warp_downscale: 0.5
```

---

## 6. 部署拓扑

### 开发环境
```
docker-compose:
  - api (FastAPI, 1个实例)
  - worker (Celery, 1个实例)
  - redis (缓存 + 队列)
  - postgres (数据库)
```

### 测试环境
```
docker-compose:
  - api (FastAPI, 2个实例)
  - worker (Celery, 2个实例)
  - redis (主从)
  - postgres (副本)
  - nginx (负载均衡)
```

### 生产环境 (Kubernetes)
```
- API Deployment (副本: 3-5)
- Worker Deployment (副本: 2-10)
- Redis StatefulSet (主从)
- PostgreSQL (托管)
- Nginx Ingress
- Prometheus + Grafana
- ELK Stack
```

---

## 7. 安全考虑

1. **API 认证**: API Key + 速率限制
2. **输入验证**: 所有输入都验证
3. **存储隔离**: 基于用户 ID 隔离文件
4. **日志脱敏**: 不记录敏感信息
5. **HTTPS**: 所有通信都加密
6. **容器安全**: 非 root 用户运行

---

## 8. 性能优化

1. **帧缓存**: 预加载下一帧，避免 I/O 等待
2. **GPU 支持**: 可选 CUDA/OpenCL 加速
3. **内存管理**: 帧缓冲池，避免频繁分配
4. **异步 I/O**: 使用 aiofiles
5. **CDN 集成**: 输出文件 CDN 加速
6. **增量处理**: 支持从检查点继续

---

## 9. 监控指标

- **API 层**: 请求延迟、错误率、QPS
- **任务层**: 待处理数、完成率、平均耗时
- **资源层**: CPU、内存、磁盘、网络
- **业务层**: 用户配额使用、成功率、成本

---

## 10. 灾难恢复

1. **自动重试**: 任务失败自动重试 (指数退避)
2. **检查点**: 每 N 帧保存处理状态
3. **幂等性**: 相同输入总是产生相同输出
4. **备份**: 数据库定期备份，输出保留 30 天
5. **灰度部署**: 新版本先在 10% 流量测试

---

完成此架构后，系统将能够：
✅ 支持并发处理 100+ 个视频
✅ 平均处理时间可预测
✅ 自动故障恢复
✅ 生产级别的可靠性
✅ 易于水平扩展
