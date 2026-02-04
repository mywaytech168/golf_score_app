# 🏌️ Golf Score App - Phase 4 集成指南

## 📌 概述

本指南说明如何将 Phase 4 的企业级功能（数据库、认证、通知等）集成到主应用中。

---

## 🚀 快速开始

### 1. 基本设置

```bash
# 进入 meshflow_server 目录
cd meshflow_server

# 安装 Phase 4 依赖
pip install -r requirements.txt

# 配置环境变量
export DATABASE_URL="postgresql://user:password@localhost/meshflow"
export SECRET_KEY="your-secret-key-here"
export JWT_EXPIRATION_HOURS=24

# 初始化数据库
python -m alembic upgrade head
```

### 2. 集成到主应用

在 `main.py` 中添加 Phase 4 集成:

```python
from phase4_integration import setup_phase4

# 创建应用
app = create_app()

# 在应用启动时设置 Phase 4
@app.on_event("startup")
async def startup():
    await setup_phase4(app)

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)
```

### 3. 运行应用

```bash
# 启动应用
python main.py

# 或使用 uvicorn
uvicorn main:app --reload

# 或使用 Flutter 任务
flutter run
```

---

## 📚 核心概念

### 认证流程

```
用户登录
   ↓
POST /api/v4/auth/login
   ↓
验证用户名和密码 (auth.py)
   ↓
生成 JWT 令牌 (24 小时)
   ↓
返回 access_token 和 refresh_token
   ↓
使用 Bearer <token> 访问受保护端点
```

### API 密钥流程

```
创建 API 密钥
   ↓
POST /api/v4/auth/api-keys
   ↓
生成随机密钥 (meshflow_xxxxx)
   ↓
存储密钥哈希到数据库
   ↓
仅在创建时返回完整密钥
   ↓
使用密钥作为 Bearer 令牌访问 API
```

### 数据库架构

```
User (用户表)
 ├── APIKey (API 密钥)
 └── ProcessingJob (处理任务)
      └── TaskHistory (任务历史)

JobStatistics (任务统计)
SystemAlert (系统告警)
NotificationLog (通知日志)
```

---

## 🔧 配置说明

### 数据库配置

```python
# config.py
DATABASE_URL = "postgresql://user:password@host:5432/meshflow_db"

# SQLAlchemy 引擎选项
SQLALCHEMY_ECHO = False  # 调试时设置为 True
SQLALCHEMY_POOL_SIZE = 20
SQLALCHEMY_POOL_RECYCLE = 3600
```

### 认证配置

```python
# 密钥管理 (生成密钥: openssl rand -hex 32)
SECRET_KEY = "your-very-secret-key-minimum-32-chars"
JWT_ALGORITHM = "HS256"
JWT_EXPIRATION_HOURS = 24
REFRESH_TOKEN_EXPIRATION_DAYS = 7
API_KEY_EXPIRATION_DAYS = 90
MAX_API_KEYS_PER_USER = 5
```

### 通知配置

```python
# 邮件
SMTP_SERVER = "smtp.gmail.com"
SMTP_PORT = 587
SMTP_USER = "your-email@gmail.com"
SMTP_PASSWORD = "your-app-password"
NOTIFICATION_FROM_EMAIL = "noreply@meshflow.com"

# WebHook
WEBHOOK_TIMEOUT = 10
WEBHOOK_RETRY_COUNT = 3
WEBHOOK_URL = "https://your-webhook-endpoint.com/notify"

# 钉钉
DINGTALK_WEBHOOK_URL = "https://oapi.dingtalk.com/robot/send?access_token=xxx"
DINGTALK_ENABLED = True

# 企业微信
WECOM_WEBHOOK_URL = "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=xxx"
```

---

## 💻 常见操作

### 创建新用户

```bash
curl -X POST http://localhost:8000/api/v4/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "golfer",
    "email": "golfer@example.com",
    "password": "secure123",
    "full_name": "Tiger Woods"
  }'
```

### 用户登录

```bash
curl -X POST http://localhost:8000/api/v4/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "golfer",
    "password": "secure123"
  }'

# 响应包含 access_token
```

### 使用 JWT 令牌

```bash
TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# 获取用户信息
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v4/auth/me

# 获取统计数据
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v4/stats/me
```

### 创建 API 密钥

```bash
curl -X POST http://localhost:8000/api/v4/auth/api-keys \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Mobile App",
    "description": "Used by iOS app",
    "scopes": ["read", "write"]
  }'

# 返回包含 api_key，仅在创建时显示
```

### 获取任务统计

```bash
# 最近 7 天的任务统计
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/v4/stats/tasks?days=7"

# 获取性能指标
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/v4/stats/performance?days=30"

# 生成报告
curl -H "Authorization: Bearer $TOKEN" \
  "http://localhost:8000/api/v4/stats/report?type=detailed&period=month"
```

---

## 🧪 测试

### 运行单元测试

```bash
# 运行所有 Phase 4 测试
python test_phase4.py

# 运行特定测试
pytest test_phase4.py::test_auth_manager_create_user -v

# 生成覆盖率报告
pytest --cov=. test_phase4.py --html=coverage.html
```

### 测试认证

```bash
# 测试用户注册
curl -X POST http://localhost:8000/api/v4/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "test123"
  }'

# 测试登录
curl -X POST http://localhost:8000/api/v4/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "test123"
  }'
```

---

## 🔍 调试

### 启用详细日志

```python
# config.py
LOG_LEVEL = "DEBUG"

# main.py
setup_logging(LOG_LEVEL)
```

### 查看数据库查询

```python
# config.py
SQLALCHEMY_ECHO = True  # 在日志中打印所有 SQL 查询
```

### 测试通知

```python
from notifications import get_notification_manager

notif_manager = get_notification_manager()

# 测试邮件
await notif_manager.send_email(
    to_email="test@example.com",
    subject="Test",
    body_html="<h1>Test Email</h1>"
)

# 验证所有通知服务
results = await notif_manager.validate_all_services()
print(results)
```

---

## 📊 监控

### 检查系统健康状态

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v4/health
```

### 检查监控状态

```bash
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:8000/api/v4/monitoring/status
```

### 查看日志

```bash
# 实时日志
tail -f logs/meshflow.log

# 错误日志
tail -f logs/meshflow_error.log

# 搜索特定内容
grep "ERROR" logs/meshflow.log
```

---

## 🐛 故障排查

### 数据库连接失败

```
错误: could not connect to server
解决:
1. 检查 PostgreSQL 是否运行
2. 检查 DATABASE_URL 配置
3. 检查网络连接
4. 运行: psql -U user -d meshflow_db -h localhost
```

### 认证失败

```
错误: Invalid credentials
解决:
1. 确认用户已注册
2. 检查密码是否正确
3. 查看 auth.py 中的认证日志
4. 检查 JWT_EXPIRATION_HOURS 配置
```

### 邮件发送失败

```
错误: SMTP authentication failed
解决:
1. 检查 SMTP 配置
2. 对于 Gmail，使用应用特定密码
3. 检查防火墙是否阻止 SMTP
4. 启用不太安全的应用 (Gmail)
```

---

## 📖 文档资源

### Phase 4 文档

| 文档 | 用途 |
|------|------|
| [PHASE4_IMPLEMENTATION.md](PHASE4_IMPLEMENTATION.md) | 完整功能说明 |
| [PHASE4_QUICK_REFERENCE.md](PHASE4_QUICK_REFERENCE.md) | API 快速参考 |
| [PHASE4_COMPLETION_CHECKLIST.md](PHASE4_COMPLETION_CHECKLIST.md) | 完成检查表 |

### 外部资源

- [FastAPI 文档](https://fastapi.tiangolo.com/)
- [SQLAlchemy 文档](https://docs.sqlalchemy.org/)
- [PyJWT 文档](https://pyjwt.readthedocs.io/)
- [PostgreSQL 文档](https://www.postgresql.org/docs/)

---

## 🚀 部署

### 开发环境

```bash
# 本地运行
python main.py

# 或使用 uvicorn
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

### 生产环境

```bash
# 使用 gunicorn
gunicorn -w 4 -b 0.0.0.0:8000 main:app

# 或使用 Docker
docker build -t meshflow:latest .
docker run -p 8000:8000 meshflow:latest
```

### Kubernetes 部署

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: meshflow
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: meshflow
        image: meshflow:latest
        ports:
        - containerPort: 8000
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: meshflow-secret
              key: database-url
```

---

## 💡 最佳实践

### 安全

✅ **密钥管理**
- 使用环境变量存储敏感信息
- 定期轮换 API 密钥
- 不在代码中存储密钥

✅ **认证**
- 使用 HTTPS (生产环境)
- 定期更新依赖
- 监控异常登录活动

✅ **数据**
- 定期备份数据库
- 启用 SSL/TLS 加密
- 遵守数据保护法规

### 性能

✅ **优化**
- 启用数据库连接池
- 使用异步处理
- 添加查询缓存
- 定期优化索引

✅ **扩展**
- 使用负载均衡
- 分离读写数据库
- 考虑分片方案
- 监控性能指标

### 维护

✅ **监控**
- 设置告警规则
- 监控日志
- 跟踪性能指标
- 定期备份

✅ **更新**
- 定期更新依赖
- 应用安全补丁
- 测试新版本
- 计划升级时间

---

## 📞 支持

### 获取帮助

1. 📖 查看文档
2. 🔍 搜索已知问题
3. 🐛 提交 Issue
4. 💬 加入社区讨论

### 报告问题

请包含以下信息：
- 操作系统和 Python 版本
- 错误消息和堆栈跟踪
- 复现步骤
- 期望行为

---

## 🎯 下一步

### 立即可做

- [ ] 阅读 PHASE4_IMPLEMENTATION.md
- [ ] 运行测试套件
- [ ] 尝试 API 端点
- [ ] 配置通知

### 后续计划

- [ ] Phase 5 - 分布式处理
- [ ] 高级分析功能
- [ ] 移动应用集成
- [ ] 企业版功能

---

## 📝 许可证

MIT License - 详见 LICENSE 文件

---

## 🙏 致谢

感谢所有为本项目贡献代码和反馈的人!

---

**Happy Coding! ⛳🏌️**

更新时间: 2024-01-15
