# Flutter App 架构整理报告

**项目**: Golf Score App (高尔夫挥杆分析应用)  
**日期**: 2026-04-16  
**状态**: 开发中

---

## 📋 目录结构概览

```
lib/
├── config/                              # 配置文件
│   └── app_config.dart                 # 应用配置
├── models/                              # 数据模型层 (3个)
│   ├── hits_summary.dart               # 挥杆总结数据模型
│   ├── recording_history_entry.dart    # 录制历史条目
│   └── statistics_response.dart        # 统计响应模型
├── pages/                               # UI页面层 (13个)
│   ├── external_video_importer_local.dart    # 本地视频导入页
│   ├── highlight_preview_page.dart          # 高光预览页
│   ├── home_page.dart                       # 首页（不完整）
│   ├── learning_hub_page.dart               # 学习中心页
│   ├── local_slice_management_page.dart     # 本地切片管理
│   ├── login_page.dart                      # 登录页
│   ├── profile_edit_page.dart               # 个人资料编辑页
│   ├── recording_history_page.dart          # 录制历史页
│   ├── recording_session_page.dart          # 录制会话页
│   ├── simple_login_page.dart               # 简化登录页
│   ├── today_info_page.dart                 # 今日信息页
│   ├── upgrade_page.dart                    # 升级页面
│   └── video_player_page.dart               # 视频播放页
├── services/                            # 业务逻辑服务层 (24个)
│   ├── ad_service.dart                 # 广告服务
│   ├── audio_analysis_service.dart     # 音频分析
│   ├── audio_analyzer.dart             # 音频分析器
│   ├── auth_token_storage.dart         # 认证令牌存储
│   ├── auto_split_and_upload_service.dart    # 自动切割上传
│   ├── daily_ad_manager.dart           # 每日广告管理
│   ├── external_video_importer.dart    # 外部视频导入
│   ├── highlight_service.dart          # 高光服务
│   ├── hits_summary_storage.dart       # 挥杆总结存储
│   ├── imu_data_logger.dart            # IMU数据日志
│   ├── in_app_purchase_service.dart    # 应用内购买服务
│   ├── keep_screen_on_service.dart     # 屏幕保持唤醒
│   ├── local_slice_repository.dart     # 本地切片存储库
│   ├── pose_estimator_service.dart     # 姿态估计服务
│   ├── purchase_service.dart           # 购买服务
│   ├── recording_history_storage.dart  # 录制历史存储
│   ├── recording_upload_manager.dart   # 录制上传管理
│   ├── statistics_service.dart         # 统计服务
│   ├── swing_clip_upload_manager.dart  # 挥杆片段上传管理
│   ├── swing_split_service.dart        # 挥杆分割服务
│   ├── user_profile_storage.dart       # 用户资料存储
│   ├── video_importer.dart             # 视频导入器
│   ├── video_overlay_processor.dart    # 视频覆盖处理
│   └── video_server_client.dart        # 视频服务器客户端
├── widgets/                             # 可复用UI组件 (8个)
│   ├── ad_check_dialog.dart            # 广告检查对话框
│   ├── hits_summary_widget.dart        # 挥杆总结组件
│   ├── pose_overlay_painter.dart       # 姿态覆盖绘制器
│   ├── purchase_test_panel.dart        # 购买测试面板
│   ├── recording_history_sheet.dart    # 录制历史底表
│   ├── recording_history_tabs.dart     # 录制历史选项卡
│   ├── stance_guide_overlay.dart       # 站姿指南覆盖
│   └── swing_clip_upload_progress_panel.dart    # 上传进度面板
├── main.dart                            # 应用入口
├── home_page.dart                       # 首页（根目录）
├── recorder_page.dart                   # 录制器页面（根目录）
├── video_importer.dart                  # 视频导入器（根目录）
├── watch_imu.dart                       # IMU监控（根目录）
└── swing_split_service.dart             # 挥杆分割服务（根目录）
```

---

## 🏗️ 架构分析

### 1. **项目架构模式**
- **架构模式**: 分层架构 (Layer Architecture)
- **状态管理**: Provider (pubspec.yaml 中声明)
- **设计策略**: Service-based 和 Repository 模式

### 2. **核心层次**

#### **配置层** (config/)
- `app_config.dart`: 应用全局配置

#### **数据模型层** (models/)
- **3个模型文件**: 相对精简
- 主要负责序列化/反序列化后端数据
- 模型：
  - `HitsSummary`: 挥杆统计数据
  - `RecordingHistoryEntry`: 录制历史
  - `StatisticsResponse`: 统计数据响应

#### **业务服务层** (services/) - **最核心层**
- **24个服务文件** - 高度复杂
- 功能分类：
  - **多媒体处理** (6个):
    - 音频分析、视频导入、视频覆盖处理、视频服务器客户端
  - **运动数据处理** (5个):
    - IMU日志、姿态估计、挥杆分割、挥杆上传管理、高光服务
  - **认证和用户** (3个):
    - 认证令牌存储、用户资料存储、购买服务
  - **应用业务** (7个):
    - 广告服务、每日广告管理、录制历史存储、挥杆总结存储、本地切片、自动分割上传、应用内购买
  - **工具服务** (3个):
    - 屏幕保持唤醒、外部视频导入、统计服务

#### **UI层** (pages/ + widgets/)
- **13个页面**: 功能相对完整
- **8个组件**: 可复用UI组件
- 主要功能页面：
  - 登录认证 (login_page, simple_login_page)
  - 录制功能 (recording_session_page, recording_history_page)
  - 视频处理 (video_player_page, highlight_preview_page)
  - 用户管理 (profile_edit_page, today_info_page)
  - 学习中心 (learning_hub_page)
  - 升级功能 (upgrade_page)

### 3. **集成的核心依赖**
```yaml
多媒体:
  - camera: 本地相机录制
  - flutter_audio_capture: 音频捕获
  - video_player: 视频播放
  - video_thumbnail: 视频缩略图
  - tflite_flutter: 机器学习（姿态估计）

蓝牙:
  - flutter_blue_plus: IMU传感器通信

认证:
  - google_sign_in: Google登录

用户系统:
  - shared_preferences: 本地存储
  - sqflite: 本地数据库

购买/盈利:
  - in_app_purchase: 应用内购买
  - google_mobile_ads: Google广告

其他:
  - provider: 状态管理
  - permission_handler: 权限管理
  - file_picker: 文件选择
```

---

## ✅ 完成度评估

### 🟢 **高度完成**
- ✅ **核心录制功能**: 相机、音频、视频处理完整
- ✅ **用户认证**: Google Sign-In 集成
- ✅ **本地存储**: 历史数据、统计数据存储
- ✅ **视频处理管道**: 导入、覆盖、上传完整

### 🟡 **部分完成/需改进**
- ⚠️ **首页逻辑** (`home_page.dart`): 仅有基础UI框架，数据绑定未完全实现
- ⚠️ **服务层耦合度**: 24个服务中存在跨域依赖，可能影响维护性
- ⚠️ **广告和购买**: 集成完成但测试不充分（见 `purchase_test_panel.dart`）
- ⚠️ **根目录文件**: 有4个文件应整理到 pages/ 或 services/
  - `recorder_page.dart` → pages/
  - `video_importer.dart` → 已有 services/video_importer.dart（重复）
  - `watch_imu.dart` → pages/ 或 services/
  - `swing_split_service.dart` → 已有 services/swing_split_service.dart（重复）

### 🔴 **缺失/不完整**
- ❌ **状态管理集中化**: 使用 Provider 但缺少统一的 ViewModel/Provider
- ❌ **错误处理**: 缺少全局错误处理和日志系统
- ❌ **国际化**: 硬编码中文，无 i18n 支持
- ❌ **单元测试**: test/ 目录存在但未见覆盖

---

## 🔧 架构优化建议

### **优先级 1 - 立即执行**
1. **清理根目录重复文件**
   ```
   - 删除或合并根目录 video_importer.dart (重复)
   - 删除或合并根目录 swing_split_service.dart (重复)
   - 移动 recorder_page.dart → lib/pages/
   - 移动 watch_imu.dart → lib/pages/imu_monitor_page.dart
   ```

2. **建立 Provider/ViewModel 层**
   ```
   新建 lib/providers/ 目录
   - app_provider.dart: 全局应用状态
   - auth_provider.dart: 认证状态
   - recording_provider.dart: 录制相关状态
   - statistics_provider.dart: 统计数据状态
   ```

3. **改进 HomePage**
   ```
   - 连接 Provider 获取今日数据
   - 实现数据实时更新
   - 添加主要功能导航
   ```

### **优先级 2 - 后续优化**
4. **服务层整理**
   - 将相关服务组织成模块 (Recording, Statistics, Media, etc.)
   - 提取通用工具到 `lib/utils/` (日志、异常、扩展)

5. **建立 Repository 层**
   ```
   新建 lib/repositories/
   - recording_repository.dart
   - user_repository.dart
   - statistics_repository.dart
   ```

6. **完善错误处理**
   ```
   新建 lib/utils/
   - error_handler.dart
   - logger.dart
   - exceptions.dart
   ```

### **优先级 3 - 长期改进**
7. 添加单元和集成测试
8. 实现国际化 (i18n)
9. 性能监控和分析

---

## 📊 代码规模统计

| 类别 | 数量 | 状态 |
|------|------|------|
| 配置文件 | 1 | ✅ 完整 |
| 数据模型 | 3 | ✅ 完整 |
| 页面 | 13 | 🟡 大部分完整 |
| 服务 | 24 | 🟡 完整但需整理 |
| 组件 | 8 | 🟡 完整但需整理 |
| **总代码单元** | **49** | |
| **整体复杂度** | 中-高 | 需要重构 |

---

## 🎯 下一步行动

1. **立即**: 清理根目录重复文件 (预计 30分钟)
2. **近期**: 建立 Provider 层和改进 HomePage (预计 2-3小时)
3. **中期**: 重构服务层 (预计 1-2天)
4. **长期**: 添加测试和文档 (持续)

---

## 📝 技术栈总结

- **语言**: Dart 3.5+
- **框架**: Flutter 3.x
- **状态管理**: Provider 6.1.0
- **本地数据**: SQLite + SharedPreferences
- **后端通信**: HTTP/REST (via video_server_client)
- **认证**: Google Sign-In + JWT (auth_token_storage)
- **多媒体**: Camera + Audio + TFLite (ML)
- **平台**: Android + iOS (Web/Desktop: 支持但未激活)

