# Flutter 架构设计 - 改进前后对比

## 📊 当前架构

```
┌─────────────────────────────────────────────────────────────┐
│                    🎨 UI Layer (Pages + Widgets)           │
│  ┌─────────────┬──────────────┬──────────────┬────────────┐│
│  │   Pages     │   Widgets    │ Components   │    Views   ││
│  │ (13个)      │  (8个)       │              │            ││
│  └─────────────┴──────────────┴──────────────┴────────────┘│
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│                  📦 Services Layer (24个)                   │
│  ├─ AudioAnalysisService      ├─ RecordingUploadManager    │
│  ├─ VideoImporter             ├─ StatisticsService         │
│  ├─ PoseEstimatorService      ├─ AdService                 │
│  ├─ AuthTokenStorage          ├─ PurchaseService           │
│  ├─ SwingClipUploadManager    ├─ DailyAdManager            │
│  ├─ HitsSummaryStorage        └─ ... (11个其他)            │
│  └─ RecordingHistoryStorage                                │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│              📱 Models + Config Layer                       │
│  ├─ HitsSummary                                            │
│  ├─ RecordingHistoryEntry                                 │
│  ├─ StatisticsResponse                                    │
│  └─ AppConfig                                             │
└──────────────────────────┬──────────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────────┐
│            🔌 External Dependencies                         │
│  ├─ Google Sign-In     ├─ SQLite    ├─ TFLite (姿态估计)  │
│  ├─ Camera            ├─ SharedPref ├─ Google Ads         │
│  ├─ Audio             ├─ In-App Pay ├─ Flutter Blue Plus  │
│  └─ Video             └─ REST API   └─ ...                │
└─────────────────────────────────────────────────────────────┘

⚠️  问题:
  ❌ Pages 直接依赖 24 个 Services (耦合度过高)
  ❌ 无状态管理层，数据流向混乱
  ❌ Services 之间存在交叉依赖
  ❌ 缺少通用工具/异常处理层
  ❌ 重复文件散落在根目录
```

---

## 🎯 目标架构 (改进后)

```
┌──────────────────────────────────────────────────────────────┐
│                   🎨 UI Layer                               │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Pages (改善的页面) + Widgets (重用组件)             │  │
│  │  ├─ HomePage (连接 Providers)                        │  │
│  │  ├─ RecordingSessionPage                            │  │
│  │  ├─ VideoPlayerPage                                 │  │
│  │  └─ ... (13个pages)                                  │  │
│  └───────────────────────────────────────────────────────┘  │
└──────────────────────────┬─────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────┐
│              📊 StateManagement Layer (NEW!)              │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Providers (6个)                                  │   │
│  │  ├─ AuthProvider (認證状態)                      │   │
│  │  ├─ RecordingProvider (錄製狀態)                 │   │
│  │  ├─ StatisticsProvider (統計數據)               │   │
│  │  ├─ AppStateProvider (全局狀態)                 │   │
│  │  ├─ VideoProvider (視頻數據)                     │   │
│  │  └─ UserProvider (用戶信息)                      │   │
│  └──────────────────────────────────────────────────┘   │
└──────────────────────────┬────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────┐
│              🏢 Repository Layer (NEW!)                   │
│  ├─ AuthRepository ──┐                                    │
│  ├─ RecordingRepo ───┼─ (抽象数据源)                      │
│  ├─ StatsRepository ─┤                                    │
│  ├─ UserRepository ──┤                                    │
│  └─ ConfigRepository─┘                                    │
└──────────────────────────┬────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────┐
│         📦 Services Layer (重新组织)                       │
│  ├─ Media Module:                                         │
│  │  ├─ video_service.dart                               │
│  │  └─ audio_service.dart                               │
│  ├─ Motion Module:                                       │
│  │  ├─ pose_service.dart                                │
│  │  ├─ imu_service.dart                                 │
│  │  └─ swing_service.dart                               │
│  ├─ User Module:                                         │
│  │  ├─ auth_service.dart                                │
│  │  └─ profile_service.dart                             │
│  ├─ App Module:                                          │
│  │  ├─ recording_service.dart                           │
│  │  ├─ ad_service.dart                                  │
│  │  ├─ purchase_service.dart                            │
│  │  └─ statistics_service.dart                          │
│  └─ Utilities Module:                                    │
│     └─ screen_service.dart, ...                          │
└──────────────────────────┬────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────┐
│         🛠️  Utilities Layer (NEW!)                         │
│  ├─ logger.dart (日志)                                   │
│  ├─ exceptions.dart (異常定義)                           │
│  ├─ error_handler.dart (全局錯誤處理)                    │
│  ├─ extensions.dart (擴展方法)                           │
│  └─ constants.dart (常數)                                │
└──────────────────────────┬────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────┐
│          📱 Models Layer                                   │
│  ├─ HitsSummary                                          │
│  ├─ RecordingHistoryEntry                               │
│  ├─ StatisticsResponse                                  │
│  └─ User, Recording, Video, ... models                  │
└──────────────────────────┬────────────────────────────────┘
                           │
┌──────────────────────────▼────────────────────────────────┐
│      🔌 External Dependencies (不變)                       │
│  ├─ Google Sign-In     ├─ SQLite      ├─ TFLite         │
│  ├─ Camera             ├─ SharedPref  ├─ REST API       │
│  ├─ Audio              ├─ In-App Pay  ├─ Bluetooth      │
│  └─ Video              └─ Google Ads  └─ ...            │
└──────────────────────────────────────────────────────────┘

✅ 改進:
  ✓ 清晰的分層架構 (6層)
  ✓ 統一的狀態管理 (Provider)
  ✓ 抽象的 Repository 層
  ✓ 模塊化的 Services
  ✓ 集中的工具和異常處理
  ✓ 耦合度大幅降低
  ✓ 易於測試和維護
```

---

## 🔄 数据流示例

### 当前 (直接耦合):
```
HomePage 
  → Services (4个） 
    → 数据混乱，更新困难
```

### 改进后 (清晰流向):
```
HomePage 
  → StatisticsProvider (监听状态变化)
    ↓
    ← StatisticsRepository (获取数据)
        ↓
        ← StatisticsService (业务逻辑)
            ↓
            ← Database/API (数据源)
```

---

## 📋 文件树 - 改进后

```
lib/
├── config/
│   └── app_config.dart
├── models/
│   ├── hits_summary.dart
│   ├── recording_history_entry.dart
│   ├── statistics_response.dart
│   ├── user.dart
│   ├── recording.dart
│   └── video.dart
├── providers/                          ← NEW
│   ├── auth_provider.dart
│   ├── recording_provider.dart
│   ├── statistics_provider.dart
│   ├── app_state_provider.dart
│   ├── video_provider.dart
│   └── user_provider.dart
├── repositories/                       ← NEW
│   ├── auth_repository.dart
│   ├── recording_repository.dart
│   ├── statistics_repository.dart
│   ├── user_repository.dart
│   └── config_repository.dart
├── services/
│   ├── media/
│   │   ├── video_service.dart
│   │   └── audio_service.dart
│   ├── motion/
│   │   ├── pose_service.dart
│   │   ├── imu_service.dart
│   │   └── swing_service.dart
│   ├── user/
│   │   ├── auth_service.dart
│   │   └── profile_service.dart
│   ├── app/
│   │   ├── recording_service.dart
│   │   ├── ad_service.dart
│   │   ├── purchase_service.dart
│   │   └── statistics_service.dart
│   └── utilities/
│       └── screen_service.dart
├── utils/                              ← NEW
│   ├── logger.dart
│   ├── exceptions.dart
│   ├── error_handler.dart
│   ├── extensions.dart
│   └── constants.dart
├── pages/
│   ├── home_page.dart
│   ├── login_page.dart
│   ├── recording_session_page.dart
│   ├── recording_history_page.dart
│   ├── video_player_page.dart
│   ├── highlight_preview_page.dart
│   ├── profile_edit_page.dart
│   ├── today_info_page.dart
│   ├── learning_hub_page.dart
│   ├── upgrade_page.dart
│   ├── external_video_importer_local.dart
│   ├── local_slice_management_page.dart
│   ├── recorder_page.dart              ← MOVED from root
│   ├── simple_login_page.dart
│   └── imu_monitor_page.dart           ← MOVED & RENAMED from watch_imu.dart
├── widgets/
│   ├── ad_check_dialog.dart
│   ├── hits_summary_widget.dart
│   ├── pose_overlay_painter.dart
│   ├── purchase_test_panel.dart
│   ├── recording_history_sheet.dart
│   ├── recording_history_tabs.dart
│   ├── stance_guide_overlay.dart
│   └── swing_clip_upload_progress_panel.dart
├── l10n/                               ← NEW (国际化)
│   ├── intl_en.arb
│   ├── intl_zh.arb
│   └── l10n.yaml
├── main.dart
└── app.dart                            ← NEW (应用配置树)
```

---

## 🎓 架构优势总结

| 方面 | 改进前 | 改进后 |
|------|--------|--------|
| **分層級數** | 3層 (UI/Services/Models) | 6層 (清晰分離) |
| **耦合度** | 高 (Pages → Services直接) | 低 (Pages → Providers → Services) |
| **可測試性** | 困難 (複雜的服務耦合) | 容易 (interface隔離) |
| **代標可維護性** | 低 (24個services混亂) | 高 (服務模塊化分組) |
| **狀態管理** | 分散 (各自為政) | 統一 (Provider中央) |
| **重複代碼** | 多個根目錄文件重複 | 零重複 |
| **可擴展性** | 困難 (新功能難以整合) | 容易 (模塊化架構) |
| **開發者體驗** | 差 (難以理解數據流) | 好 (清晰的數據流向) |

