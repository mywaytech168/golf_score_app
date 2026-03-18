# Phase 4 - 数据库集成与认证系统 📊🔐

## 概述

Phase 4 实现了企业级的数据库集成、用户认证、权限管理、任务监控和通知系统。这一阶段是从 Phase 1-3 的处理基础上，添加数据持久化和多用户支持。

## 核心功能

### 1. 数据库模型 (models.py)

✅ 8 个 SQLAlchemy ORM 模型

#### 用户管理
```python
User(id, username, email, password_hash, role, is_active, created_at, updated_at)
  - role: admin, user, guest
  - is_active: 账号是否激活
  - 关系: 1:M ProcessingJob, 1:M APIKey
```

#### API 密钥
```python
APIKey(id, user_id, key_hash, key_prefix, scopes, is_active, expires_at, created_at, last_used_at)
  - key_hash: 密钥加密存储 (不存储明文)
  - key_prefix: 用于日志记录 (仅存储前 10 个字符)
  - scopes: ["read", "write", "delete", "admin"]
  - 关系: M:1 User
```

#### 处理任务
```python
ProcessingJob(
  id, user_id, job_id, status, input_video_url, output_video_url,
  total_frames, current_frame, progress_percentage,
  started_at, completed_at, processing_time_seconds,
  error_message, created_at, updated_at
)
  - status: pending, validating, processing, completed, failed, cancelled
  - 关系: M:1 User, 1:M TaskHistory
```

#### 任务历史
```python
TaskHistory(id, job_id, event_type, details, created_at)
  - event_type: submitted, started, progress, completed, failed
  - details: JSON 格式的事件详情
  - 用于审计和问题排查
```

#### 任务统计
```python
JobStatistics(
  id, user_id, total_jobs, completed_jobs, failed_jobs,
  avg_processing_time, total_frames_processed, last_updated
)
  - 为统计分析优化的聚合数据
  - 定期从 ProcessingJob 聚合更新
```

#### 系统告警
```python
SystemAlert(id, title, content, level, user_id, is_acknowledged, created_at)
  - level: info, warning, error, critical
  - is_acknowledged: 是否已确认
```

#### 通知日志
```python
NotificationLog(
  id, notification_type, title, content, status, result,
  retry_count, failed_at, created_at
)
  - 记录所有通知发送情况
  - 用于重试失败的通知
```

### 2. 认证系统 (auth.py)

✅ 完整的双认证支持 (JWT + API Key)

#### JWT 认证
```python
TokenManager
  - create_access_token(data, expires_delta): 生成 24 小时 JWT
  - create_refresh_token(data): 生成 7 天刷新令牌
  - verify_token(token): 验证并解析 JWT
  
用户数据: {sub: user_id, username, role, exp, iat}
```

#### API 密钥认证
```python
APIKeyManager
  - generate_api_key(): 生成 "meshflow_" 前缀的密钥
  - hash_api_key(key): 使用 bcrypt 哈希密钥
  - verify_api_key(key, hash): 验证密钥
  - get_key_prefix(key): 获取前 10 个字符用于日志
```

#### 密码安全
```python
PasswordManager
  - hash_password(password): 使用 bcrypt 哈希 (cost=12)
  - verify_password(password, hash): 验证密码
  
使用 passlib 的 CryptContext 确保安全
```

#### 权限管理
```python
PermissionManager
  - 角色 → 权限映射:
    * admin: ["read", "write", "delete", "admin"]
    * user: ["read", "write"]
    * guest: ["read"]
  - check_permission(role, permission): 检查权限
```

#### 统一认证接口
```python
AuthManager (主要使用)
  - authenticate_user(username, password): 用户名密码认证
  - authenticate_api_key(key): API 密钥认证
  - create_user(username, email, password): 创建用户
  - create_api_key(user_id, name, scopes): 创建 API 密钥
  - verify_token(token): 验证令牌
```

### 3. 数据库层 (database_v4.py)

✅ ORM 抽象层 + 仓储模式

#### 数据库连接管理
```python
DatabaseManager
  - 连接池: pool_size=20, max_overflow=10
  - 连接回收: pool_recycle=3600 (1小时)
  - 健康检查: pool_pre_ping=True
  - 自动事务管理和回滚
```

#### 通用仓储
```python
BaseRepository<T>
  - create(data): 创建记录
  - get(id): 按 ID 获取
  - update(id, data): 更新记录
  - delete(id): 删除记录
  - get_all(skip, limit): 分页查询
```

#### 专用仓储
```python
UserRepository
  - get_by_username(username): 按用户名查询
  - get_by_email(email): 按邮箱查询
  - get_active_users(): 获取活跃用户

ProcessingJobRepository
  - get_by_job_id(job_id): 获取处理任务
  - get_user_jobs(user_id, status): 获取用户任务列表
  - update_progress(job_id, current_frame, total_frames, percentage)
  - mark_completed(job_id, processing_time, total_frames, output_url)
  - mark_failed(job_id, error_message)

TaskHistoryRepository
  - add_event(job_id, event_type, details): 记录事件
  - get_job_history(job_id): 获取任务历史

JobStatisticsRepository
  - get_or_create_for_user(user_id): 获取或创建统计
  - update_stats(user_id, **stats): 更新统计数据

SystemAlertRepository
- get_unacknowledged_alerts(user_id)
  - acknowledge_alert(alert_id)

NotificationLogRepository
  - get_failed_notifications(): 获取失败的通知
  - retry_notification(log_id): 重试发送
```

### 4. 认证 API (api_v4_auth.py)

✅ 6 个认证端点

#### 用户管理
```
POST   /api/v4/auth/register
  入参: {username, email, password, full_name}
  返回: {id, username, email, role, created_at}
  
POST   /api/v4/auth/login
  入参: {username, password}
  返回: {access_token, refresh_token, token_type, user_id, username, role}
  
GET    /api/v4/auth/me (需要 JWT)
  返回: 当前用户信息
```

#### API 密钥管理
```
POST   /api/v4/auth/api-keys (需要 JWT)
  入参: {name, description, scopes}
  返回: {id, name, key_prefix, api_key (仅创建时), scopes, is_active}
  
GET    /api/v4/auth/api-keys (需要 JWT)
  返回: 用户的所有 API 密钥列表
  
DELETE /api/v4/auth/api-keys/{id} (需要 JWT)
  返回: {message: "API key revoked"}
```

#### JWT 中间件
```python
get_current_user(token: str):
  - 从 Authorization: Bearer <token> 解析
  - 验证令牌有效性和过期时间
  - 返回当前用户对象
```

### 5. 统计 API (api_v4_stats.py)

✅ 5 个分析端点

```
GET    /api/v4/stats/tasks?days=7 (需要 JWT)
  返回: {total, completed, failed, cancelled, processing, success_rate}
  
GET    /api/v4/stats/performance?days=30 (需要 JWT)
  返回: {avg_time, min_time, max_time, total_frames, throughput}
  
GET    /api/v4/stats/me (需要 JWT)
  返回: 当前用户的统计数据
  
GET    /api/v4/stats/daily?days=30 (需要 JWT)
  返回: [{date, stats}, ...] 日每日统计
  
GET    /api/v4/stats/report?type=summary&period=month (需要 JWT)
  返回: 定制化的统计报告
  type: summary, detailed, performance
  period: day, week, month, quarter, year
```

### 6. 通知系统 (notifications.py)

✅ 多渠道通知支持

#### 邮件通知
```python
EmailNotificationService
  - SMTP 配置支持
  - HTML + 纯文本格式
  - STARTTLS 安全连接
```

#### WebHook 通知
```python
WebHookNotificationService
  - 异步 POST 请求
  - 指数退避重试 (3 次)
  - 10 秒超时
```

#### 钉钉通知
```python
DingTalkNotificationService
  - Markdown 格式消息
  - 自动错误码处理
```

#### 企业微信通知
```python
WeComNotificationService
  - Markdown 格式消息
  - 完全兼容企业微信 API
```

#### 通知管理器
```python
NotificationManager
  - send(): 通用发送接口
  - send_email(): 发送邮件
  - send_alert(): 发送告警
  - send_task_completed(): 任务完成通知
  - send_task_failed(): 任务失败通知
  - validate_all_services(): 验证所有配置
```

### 7. 任务监控 (task_monitor.py)

✅ 实时任务监控和告警

#### 单任务监控
```python
TaskMonitor
  - monitor_job(job_id): 监控单个任务
  - _check_timeout(): 检测超时 (>2 小时)
  - _check_performance_metrics(): 检查性能指标
  - _handle_task_completed(): 处理任务完成
  - _handle_task_failed(): 处理任务失败
```

#### 全局监控
```python
GlobalMonitor
  - start_monitoring(check_interval=30s): 启动监控
  - stop_monitoring(): 停止监控
  - _monitor_all_jobs(): 监控所有进行中的任务
  - get_system_health(): 获取系统健康状态
```

#### 监控指标
```
- processing_time: >3600s 时告警
- memory_usage: >80% 时告警
- cpu_usage: >90% 时告警
```

#### 监控钩子
```python
MonitoringHook
  - on_job_status_changed(): 任务状态变化时触发
  - on_performance_degradation(): 性能下降时触发
```

### 8. 系统集成 (phase4_integration.py)

✅ 所有组件的集成管理

```python
Phase4Manager
  - initialize(): 初始化所有组件
  - start_monitoring(): 启动全局监控
  - stop_monitoring(): 停止监控
  - validate_notifications(): 验证通知配置

setup_phase4(app):
  - 初始化 Phase 4 组件
  - 注册 API 路由
  - 设置启动和关闭事件

register_phase4_routes(app):
  - /api/v4/health: 系统健康状态
  - /api/v4/monitoring/status: 监控状态
```

## 配置说明

在 `config.py` 中添加以下配置:

```python
# 数据库配置
DATABASE_URL = "postgresql://user:password@localhost/meshflow"

# JWT 配置
SECRET_KEY = "your-secret-key-here"
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_HOURS = 24
REFRESH_TOKEN_EXPIRATION_DAYS = 7

# API 密钥配置
API_KEY_EXPIRATION_DAYS = 90
MAX_API_KEYS_PER_USER = 5

# 邮件配置
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
SMTP_USER = "your-email@gmail.com"
SMTP_PASSWORD = "your-app-password"
NOTIFICATION_FROM_EMAIL = "noreply@meshflow.com"

# WebHook 配置
WEBHOOK_TIMEOUT = 10
WEBHOOK_RETRY_COUNT = 3

# 钉钉配置
DINGTALK_WEBHOOK_URL = "https://oapi.dingtalk.com/robot/send?access_token=xxx"
DINGTALK_ENABLED = True

# 企业微信配置
WECOM_WEBHOOK_URL = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
```

## 使用示例

### 1. 用户注册和登录

```bash
# 注册新用户
curl -X POST http://localhost:8000/api/v4/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "golfer",
    "email": "golfer@example.com",
    "password": "secure123",
    "full_name": "Tiger Woods"
  }'

# 登录
curl -X POST http://localhost:8000/api/v4/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "golfer",
    "password": "secure123"
  }'

# 响应示例
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "user_id": 1,
  "username": "golfer",
  "role": "user"
}
```

### 2. API 密钥管理

```bash
# 创建 API 密钥
curl -X POST http://localhost:8000/api/v4/auth/api-keys \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mobile App",
    "description": "Used by iOS app",
    "scopes": ["read", "write"]
  }'

# 响应示例
{
  "id": 1,
  "name": "Mobile App",
  "key_prefix": "meshflow_abc123",
  "api_key": "meshflow_abc123def456ghi789jkl012",
  "scopes": ["read", "write"],
  "is_active": true,
  "created_at": "2024-01-15T10:30:00Z"
}

# 使用 API 密钥
curl -X GET http://localhost:8000/api/v4/stats/me \
  -H "Authorization: Bearer meshflow_abc123def456ghi789jkl012"
```

### 3. 获取统计数据

```bash
# 获取最近 7 天的任务统计
curl -X GET "http://localhost:8000/api/v4/stats/tasks?days=7" \
  -H "Authorization: Bearer $TOKEN"

# 获取性能指标 (最近 30 天)
curl -X GET "http://localhost:8000/api/v4/stats/performance?days=30" \
  -H "Authorization: Bearer $TOKEN"

# 获取用户统计
curl -X GET http://localhost:8000/api/v4/stats/me \
  -H "Authorization: Bearer $TOKEN"

# 获取日每日统计
curl -X GET "http://localhost:8000/api/v4/stats/daily?days=30" \
  -H "Authorization: Bearer $TOKEN"

# 生成报告
curl -X GET "http://localhost:8000/api/v4/stats/report?type=detailed&period=month" \
  -H "Authorization: Bearer $TOKEN"
```

### 4. 任务监控和告警

```bash
# 获取系统健康状态
curl -X GET http://localhost:8000/api/v4/health \
  -H "Authorization: Bearer $TOKEN"

# 获取监控状态
curl -X GET http://localhost:8000/api/v4/monitoring/status \
  -H "Authorization: Bearer $TOKEN"
```

## 测试

运行完整的 Phase 4 测试套件:

```bash
# 运行测试
python meshflow_server/test_phase4.py

# 测试覆盖:
# ✓ 密码管理器测试
# ✓ API 密钥管理测试
# ✓ 令牌管理测试
# ✓ 用户认证测试
# ✓ 用户仓储测试
# ✓ 任务仓储测试
# ✓ 任务进度更新测试
# ✓ 任务统计测试
# ✓ 完整工作流集成测试
```

## 安全特性

✅ **密码安全**
- 使用 bcrypt (cost=12) 哈希密码
- 密码永远不以明文存储

✅ **API 密钥安全**
- 密钥使用 bcrypt 哈希存储
- 仅在创建时返回完整密钥
- 支持密钥过期和撤销

✅ **令牌安全**
- JWT 使用 HS256 算法签名
- 支持令牌过期 (24 小时)
- 支持刷新令牌 (7 天)

✅ **权限管理**
- 基于角色的访问控制 (RBAC)
- 3 个内置角色: admin, user, guest
- 灵活的权限映射

✅ **通知安全**
- 邮件使用 STARTTLS 加密
- WebHook 支持重试和错误处理
- 所有通知记录到日志

## 性能优化

✅ **数据库优化**
- 连接池管理 (20 并发)
- 自动连接回收 (1 小时)
- 健康检查 (pool_pre_ping)
- 关键列上的索引

✅ **查询优化**
- 使用仓储模式减少重复代码
- 统计查询使用聚合函数
- 支持分页查询

✅ **异步支持**
- 通知系统完全异步
- 监控系统后台运行
- 不阻塞主应用处理

## 扩展指南

### 添加新的通知渠道

```python
class SlackNotificationService(NotificationService):
    async def send(self, message: Dict[str, Any]) -> bool:
        # 实现 Slack 通知逻辑
        pass
    
    async def validate_config(self) -> bool:
        # 验证 Slack 配置
        pass

# 在 NotificationManager._init_services() 中注册
```

### 添加新的监控指标

```python
# 在 TaskMonitor.__init__() 中添加
self.metrics["new_metric"] = MonitoringMetric("new_metric", 100.0, ">")

# 在 _check_performance_metrics() 中检查
if self.metrics["new_metric"].check(value):
    # 触发告警
```

## 故障排查

### 数据库连接失败
- 检查 DATABASE_URL 配置
- 确保数据库服务运行
- 检查网络连接

### 邮件发送失败
- 验证 SMTP 配置
- 检查应用特定密码 (对于 Gmail 等)
- 查看错误日志

### API 密钥无效
- 确保密钥未过期
- 检查密钥是否已撤销
- 验证密钥权限

## 下一步 (Phase 5)

- 批量处理支持
- 高级分析仪表盘
- 机器学习模型集成
- 分布式处理扩展

## 贡献和支持

详见项目主 README.md

---

**Phase 4 完成状态**: ✅ 100% (核心功能)

最后更新: 2024-01-15
