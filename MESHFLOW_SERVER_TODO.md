# MeshFlow 稳定化系统 - 服务器化设计 TODO

## 整体架构概述

当前：单机脚本（本地文件输入输出）
目标：分布式服务器系统（支持云存储、异步处理、队列管理）

---

## Phase 1: 核心服务器框架 (高优先级)

### 1.1 后端 API 服务
- [ ] 选择框架 (FastAPI / Flask / Django)
  - 推荐: FastAPI (异步支持、自动 OpenAPI 文档)
- [ ] 创建 `meshflow_server.py` 主应用
- [ ] 实现健康检查端点 `GET /health`
- [ ] 实现版本端点 `GET /version`
- [ ] 配置日志系统（结构化日志、日志级别）
- [ ] 配置错误处理中间件（全局异常捕获、标准错误响应）
- [ ] 实现请求/响应日志记录

### 1.2 数据库设计
- [ ] 选择数据库 (PostgreSQL / MongoDB)
- [ ] 创建数据库模型：
  - [ ] `StabilizationJob` - 稳定化任务记录
    - job_id (UUID)
    - video_id (原始视频 ID)
    - status (pending/processing/completed/failed)
    - input_path / input_url
    - output_path / output_url
    - parameters (JSON)
    - start_time / end_time
    - error_message (失败时)
    - created_at / updated_at
  - [ ] `ProcessingLog` - 处理日志详情
  - [ ] `VideoMetadata` - 视频元数据缓存
- [ ] 创建数据库迁移脚本

### 1.3 文件存储方案
- [ ] 支持多种存储后端（本地、S3、阿里云 OSS、Azure Blob）
- [ ] 创建 `storage.py` 抽象层
  - [ ] `BaseStorage` 接口
  - [ ] `LocalStorage` 实现
  - [ ] `S3Storage` 实现
  - [ ] `OSSStorage` 实现
- [ ] 实现文件上传/下载管理
- [ ] 实现临时文件清理机制

---

## Phase 2: 核心处理逻辑重构 (高优先级)

### 2.1 MeshFlow 处理器解耦
- [ ] 创建 `meshflow_processor.py`
  - [ ] 将 `MeshFlowStabilizer` 从脚本改为可重用的类
  - [ ] 支持参数化初始化
  - [ ] 返回结构化结果（不仅仅是文件）
- [ ] 实现进度回调接口
  - [ ] `on_frame_processed(frame_idx, total_frames)`
  - [ ] `on_segment_detected(start, end)`
  - [ ] `on_stabilization_start()`
  - [ ] `on_stabilization_complete()`

### 2.2 处理管道创建
- [ ] 创建 `processing_pipeline.py`
  - [ ] 输入验证（视频格式、分辨率、时长）
  - [ ] 视频加载（支持本地和远程）
  - [ ] 参数提取和验证
  - [ ] 调用 MeshFlow 处理
  - [ ] 输出编码和保存
  - [ ] 结果验证
  - [ ] 错误恢复机制

### 2.3 参数管理
- [ ] 创建 `config.py` - 默认参数配置
  - [ ] MeshFlow 参数
  - [ ] 振动检测参数
  - [ ] FFmpeg 编码参数
  - [ ] 处理超时设置
  - [ ] 资源限制（内存、CPU）
- [ ] 参数验证规则定义
- [ ] 参数文档化

---

## Phase 3: 异步任务处理 (高优先级)

### 3.1 任务队列系统
- [ ] 选择队列系统 (Celery + Redis / RQ / Huey)
- [ ] 创建 `tasks.py` - 异步任务定义
  - [ ] `process_video_stabilization` 任务
  - [ ] 任务超时设置
  - [ ] 任务重试策略
  - [ ] 任务进度跟踪
- [ ] 配置 Worker 进程管理

### 3.2 实时进度跟踪
- [ ] 实现 WebSocket 端点 `WS /jobs/{job_id}/progress`
- [ ] 创建 `progress_tracker.py`
  - [ ] 进度百分比计算
  - [ ] 当前处理帧数
  - [ ] 预计完成时间 (ETA)
  - [ ] 实时日志流
- [ ] Redis/缓存存储进度信息

### 3.3 长期运行保证
- [ ] 实现心跳 (heartbeat) 检测
- [ ] 超时自动中止逻辑
- [ ] 处理 Worker 崩溃的恢复机制
- [ ] 任务持久化（重启后恢复）

---

## Phase 4: API 端点设计 (高优先级)

### 4.1 视频稳定化 API
- [ ] `POST /api/stabilize` - 提交稳定化任务
  - 参数: video_url / video_file, parameters (可选)
  - 返回: job_id, status, estimated_duration
- [ ] `GET /api/jobs/{job_id}` - 查询任务状态
  - 返回: status, progress, error_message, output_url (完成时)
- [ ] `GET /api/jobs/{job_id}/progress` - 详细进度信息
  - 返回: percentage, current_frame, total_frames, eta_seconds
- [ ] `DELETE /api/jobs/{job_id}` - 取消任务
- [ ] `GET /api/jobs` - 列出所有任务（分页、筛选）

### 4.2 参数相关 API
- [ ] `GET /api/parameters/defaults` - 获取默认参数
- [ ] `POST /api/parameters/validate` - 验证参数有效性
- [ ] `GET /api/parameters/schema` - 获取参数 JSON Schema

### 4.3 视频分析 API
- [ ] `POST /api/analyze/shake` - 检测振动段（不稳定化）
  - 返回: shake_segments, scores
- [ ] `GET /api/video-info` - 获取视频元数据
  - 返回: duration, fps, resolution, codec

---

## Phase 5: 认证和安全 (中优先级)

### 5.1 认证系统
- [ ] API Key 认证
  - [ ] 生成和管理 API Keys
  - [ ] 按 API Key 限流
- [ ] JWT Token 支持 (可选)
- [ ] OAuth2 集成 (可选)

### 5.2 授权系统
- [ ] 基于用户的资源隔离
- [ ] 配额管理（每日处理时长限制）
- [ ] 管理员接口

### 5.3 安全加固
- [ ] 输入验证（防止 path traversal）
- [ ] 速率限制（防止 DDoS）
- [ ] 请求签名验证
- [ ] CORS 配置
- [ ] HTTPS/TLS 配置

---

## Phase 6: 监控和日志 (中优先级)

### 6.1 性能监控
- [ ] 指标收集（Prometheus / StatsD）
  - [ ] 处理时间分布
  - [ ] 成功率
  - [ ] 资源使用（CPU、内存、磁盘）
  - [ ] 队列长度
- [ ] 性能仪表板 (Grafana)

### 6.2 日志系统
- [ ] 结构化日志记录 (JSON 格式)
- [ ] 日志收集和分析 (ELK / Loki)
- [ ] 日志保留策略
- [ ] 调试模式支持

### 6.3 告警系统
- [ ] 任务失败告警
- [ ] 资源耗尽告警
- [ ] API 错误率告警
- [ ] 处理时间异常告警

---

## Phase 7: 扩展性和部署 (中优先级)

### 7.1 容器化
- [ ] 创建 `Dockerfile`
  - [ ] 多阶段构建（减小镜像大小）
  - [ ] 非 root 用户运行
  - [ ] 健康检查配置
- [ ] 创建 `docker-compose.yml`
  - [ ] API 服务
  - [ ] Worker 进程
  - [ ] Redis
  - [ ] 数据库
  - [ ] 监控工具

### 7.2 Kubernetes 部署 (可选)
- [ ] 创建 Helm Chart
- [ ] 配置自动扩展 (HPA)
- [ ] 配置持久卷 (PVC)
- [ ] 创建 ConfigMap 和 Secret

### 7.3 负载均衡
- [ ] Nginx / HAProxy 配置
- [ ] 健康检查端点
- [ ] 优雅关闭处理

---

## Phase 8: 客户端集成 (中优先级)

### 8.1 Flutter 应用集成
- [ ] 更新 `VideoServerClient` 添加稳定化 API
  - [ ] `submitStabilizationJob(videoPath, parameters)`
  - [ ] `getJobStatus(jobId)`
  - [ ] `subscribeToProgress(jobId)` (WebSocket)
  - [ ] `cancelJob(jobId)`
- [ ] UI 组件创建
  - [ ] 稳定化参数选择器
  - [ ] 进度条 + 预计时间
  - [ ] 处理结果展示

### 8.2 Web 前端 (可选)
- [ ] React / Vue 管理仪表板
- [ ] 实时任务监控
- [ ] 参数配置界面
- [ ] 结果查看和下载

---

## Phase 9: 测试 (中优先级)

### 9.1 单元测试
- [ ] MeshFlow 处理器单元测试
- [ ] 参数验证单元测试
- [ ] 存储层单元测试
- [ ] 目标覆盖率: >80%

### 9.2 集成测试
- [ ] API 端点集成测试
- [ ] 数据库操作集成测试
- [ ] 任务队列集成测试
- [ ] 存储后端集成测试

### 9.3 性能测试
- [ ] 负载测试 (不同视频大小)
- [ ] 并发处理测试
- [ ] 内存泄漏检查
- [ ] 基准测试

### 9.4 端到端测试
- [ ] 上传 → 处理 → 下载 完整流程
- [ ] 错误场景处理
- [ ] 网络中断恢复

---

## Phase 10: 文档和部署 (低优先级)

### 10.1 API 文档
- [ ] OpenAPI/Swagger 自动生成
- [ ] 使用示例
- [ ] 错误代码文档
- [ ] WebSocket 协议文档

### 10.2 部署文档
- [ ] 本地开发环境设置
- [ ] Docker 部署指南
- [ ] Kubernetes 部署指南
- [ ] 配置文档
- [ ] 故障排查指南

### 10.3 操作文档
- [ ] 监控和告警设置
- [ ] 备份和恢复程序
- [ ] 版本升级程序
- [ ] 日志收集和分析指南

---

## 技术栈建议

```
后端:
  - FastAPI (Web 框架)
  - PostgreSQL (数据库)
  - Celery + Redis (任务队列 + 缓存)
  - Boto3 / Aliyun SDK (云存储)
  - Prometheus + Grafana (监控)
  - ELK / Loki (日志)

容器化:
  - Docker
  - Docker Compose
  - Kubernetes (可选)
  - Helm (可选)

开发工具:
  - pytest (单元测试)
  - pytest-cov (覆盖率)
  - locust (性能测试)
  - black / isort (代码格式)
  - pylint / flake8 (代码检查)
```

---

## 里程碑和优先级

```
Milestone 1 (必须，第1周):
  ✓ Phase 1.1, 1.2, 1.3 - 基础框架
  ✓ Phase 2.1, 2.2, 2.3 - 处理逻辑

Milestone 2 (高优先，第2周):
  ✓ Phase 3 - 异步处理
  ✓ Phase 4 - API 端点
  ✓ Phase 9.1, 9.2 - 测试

Milestone 3 (中优先，第3周):
  ✓ Phase 5 - 安全
  ✓ Phase 6 - 监控
  ✓ Phase 7 - 容器化

Milestone 4 (可选):
  ✓ Phase 8 - 客户端集成
  ✓ Phase 10 - 文档
```

---

## 关键考虑事项

1. **性能**: MeshFlow 是 CPU 密集型，需要考虑：
   - Worker 池管理
   - 帧缓存策略
   - GPU 加速（可选）

2. **存储成本**: 视频文件很大，需要：
   - 自动清理过期文件
   - 压缩存储
   - CDN 集成（可选）

3. **可靠性**: 长期运行任务容易中断，需要：
   - 检查点保存
   - 失败重试
   - 幂等性设计

4. **扩展性**: 从小到大的灵活设计：
   - 单机 → 多 Worker
   - 本地存储 → 云存储
   - 手动扩展 → Kubernetes 自动扩展

---

## 完成后的优势

✅ 支持并发处理多个视频
✅ 异步任务，不阻塞 API
✅ 自动进度报告
✅ 支持多种存储后端
✅ 易于监控和调试
✅ 易于扩展和维护
✅ 可与 Flutter 应用无缝集成
✅ 支持生产级别部署
