# Flutter App 整理清单

## 🔴 **紧急执行项** (Week 1)

### 1. 清理重复文件和目录结构
- [ ] 检查根目录的 `video_importer.dart` vs `lib/services/video_importer.dart`
  - [ ] 对比功能，保留完整版本
  - [ ] 删除/合并重复版本
  
- [ ] 检查根目录的 `swing_split_service.dart` vs `lib/services/swing_split_service.dart`
  - [ ] 对比功能，保留完整版本
  - [ ] 删除/合并重复版本

- [ ] 移动根目录文件到合适位置
  - [ ] `recorder_page.dart` → `lib/pages/recorder_page.dart`
  - [ ] `watch_imu.dart` → `lib/pages/imu_monitor_page.dart` (并重命名)
  - [ ] 更新所有导入语句

### 2. 建立状态管理层 (Provider)
- [ ] 创建 `lib/providers/` 目录
- [ ] 建立以下 Provider：
  - [ ] `auth_provider.dart` - 处理认证状态、用户信息
  - [ ] `recording_provider.dart` - 录制会话状态
  - [ ] `statistics_provider.dart` - 今日/历史统计数据
  - [ ] `app_state_provider.dart` - 应用级全局状态

### 3. 完善首页 (HomePage)
- [ ] 移除硬编码的 `todaySwingData` 
- [ ] 连接 `statistics_provider.dart` 获取实时数据
- [ ] 实现数据更新监听
- [ ] 添加主要功能导航卡片
- [ ] 美化UI布局

---

## 🟡 **后续优化项** (Week 2-3)

### 4. 建立通用工具层
- [ ] 创建 `lib/utils/` 目录
- [ ] 提取日志工具：`lib/utils/logger.dart`
- [ ] 提取异常定义：`lib/utils/exceptions.dart`
- [ ] 提取扩展方法：`lib/utils/extensions.dart`
- [ ] 建立全局错误处理：`lib/utils/error_handler.dart`

### 5. 建立 Repository 层 (数据源抽象)
- [ ] 创建 `lib/repositories/` 目录
- [ ] 建立抽象类：
  - [ ] `recording_repository.dart`
  - [ ] `user_repository.dart`
  - [ ] `statistics_repository.dart`
  - [ ] `config_repository.dart`
- [ ] 重构 services 为 repository 实现

### 6. 服务层模块化整理
按功能模块组织 24 个 services：

**多媒体模块** (lib/services/media/):
- [ ] `video_service.dart` (整合 video_importer, video_overlay_processor, video_server_client)
- [ ] `audio_service.dart` (整合 audio_analysis_service, audio_analyzer)

**运动数据模块** (lib/services/motion/):
- [ ] `motion_service.dart` (整合 pose_estimator_service)
- [ ] `imu_service.dart` (整合 imu_data_logger)
- [ ] `swing_service.dart` (整合 swing_split_service, swing_clip_upload_manager)

**用户数据模块** (lib/services/user/):
- [ ] `auth_service.dart` (整合 auth_token_storage)
- [ ] `profile_service.dart` (整合 user_profile_storage)

**应用业务模块** (lib/services/app/):
- [ ] `recording_service.dart` (整合 recording_history_storage, recording_upload_manager, auto_split_and_upload_service)
- [ ] `statistics_service.dart` (现有)
- [ ] `ad_service.dart` (整合 ad_service, daily_ad_manager)
- [ ] `purchase_service.dart` (整合 purchase_service, in_app_purchase_service)

**工具模块** (lib/services/utilities/):
- [ ] `screen_service.dart` (keep_screen_on_service)
- [ ] 其他工具

---

## 🟢 **长期改进项** (Month 2+)

### 7. 测试框架建立
- [ ] 建立 `test/unit/` - 单元测试
  - [ ] Service 层测试
  - [ ] Model 序列化测试
  
- [ ] 建立 `test/widget/` - widget 测试
  - [ ] 关键页面测试

- [ ] 建立 `test/integration/` - 集成测试
  - [ ] 完整流程测试

### 8. 国际化支持 (i18n)
- [ ] 添加 `intl` / `gen_l10n` 配置
- [ ] 创建 `lib/l10n/` 目录
- [ ] 提取所有硬编码文本 (目前全是中文)
- [ ] 支持中文 + 英文

### 9. 文档完善
- [ ] 编写 API 文档 (services)
- [ ] 编写集成指南
- [ ] 编写开发规范

### 10. 性能优化
- [ ] 实现图像缓存
- [ ] 优化视频处理管道
- [ ] 分析内存使用

---

## 📋 按优先级的执行表

| 优先级 | 项目 | 预计时间 | 状态 |
|--------|------|---------|------|
| 🔴 P1 | 清理重复文件 | 30分钟 | 待开始 |
| 🔴 P1 | 建立 Provider 层 | 2小时 | 待开始 |
| 🔴 P1 | 完善 HomePage | 1小时 | 待开始 |
| 🟡 P2 | 建立工具层 | 1.5小时 | 待开始 |
| 🟡 P2 | 建立 Repository 层 | 2小时 | 待开始 |
| 🟡 P2 | 服务层模块化 | 4小时 | 待开始 |
| 🟢 P3 | 测试框架 | 8小时 | 待开始 |
| 🟢 P3 | i18n 国际化 | 4小时 | 待开始 |
| **总计** | | **~23小时** | |

---

## 📝 执行建议

### 本周建议 (优先级 1)
```
Day 1:
  - 清理重复文件 (30min)
  - 建立 Provider 层结构 (1hour)
  
Day 2-3:
  - 编写各 Provider (2hours)
  - 完善 HomePage (1hour)
  - 更新导入和测试 (1hour)
```

### 下周建议 (优先级 2)
```
Week 2:
  - 建立工具和 Repository 层
  - 开始服务层模块化
  
Week 3:
  - 完成服务层整理
  - 添加基础单元测试
```

---

## ✨ 重构完成标志

- ✅ 零重复文件
- ✅ 清晰的分层架构 (Config → Repository → Provider → Services → UI)
- ✅ HomePage 完全功能化
- ✅ 服务模块化分组
- ✅ 基本单元测试覆盖
- ✅ 一致的导入和命名规范

