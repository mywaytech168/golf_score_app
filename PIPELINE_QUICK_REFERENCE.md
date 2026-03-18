# ⚡ 处理管道快速参考

## 🔄 处理流程概览

```
视频上传完成
    ↓
C# 创建 ProcessQueueItem(status="queued")
    ↓
Python 接收处理请求
    ↓
执行 5 步处理管道
    │
    ├─→ 🎬 步骤 1: Stabilization (40-60s)
    ├─→ 🎵 步骤 2: Audio Analysis (10-15s)
    ├─→ 📊 步骤 3: Audio Scoring (3-5s)
    ├─→ 🤖 步骤 4: OpenPose (80-120s)
    └─→ ⚽ 步骤 5: Ball Tracking (20-40s)
    ↓
处理完成 / 失败
    ↓
发送状态回调给 C#
    ↓
更新数据库
```

## 📂 目录结构

### 输入目录结构
```
input_dir/
└── original_video.mp4
```

### 输出目录结构
```
input_dir/
├── original_video.mp4
├── clip_stabilized.mp4              ← 步骤 1
├── original_video_audio.wav          ← 步骤 2
├── *_denoised_summary.csv            ← 步骤 2
├── audio_scoring_results.csv         ← 步骤 3
├── pose_analysis/                    ← 步骤 4
│   ├── pose_keypoints.csv
│   ├── pose_phases.csv
│   └── pose_video.mp4
├── ball_tracking/                    ← 步骤 5
│   └── ball_tracking.mp4
└── processing.log                    ← 完整日志
```

## 🔧 配置参数速查

| 步骤 | 类名 | 必需参数 | 输出目录 |
|------|------|---------|--------|
| 1 | MeshFlowConfig | input_path, output_path | - |
| 2 | AudioAnalysisConfig | video_path, output_dir | 输入目录 |
| 3 | AudioScoringConfig | csv_folder, [output_csv] | audio_scoring_results.csv |
| 4 | MediaPoseConfig | video_path, [output_dir] | pose_analysis/ |
| 5 | BallTrackingConfig | input_dir, [output_dir] | ball_tracking/ |

## ✅ 修复清单

- [x] Stabilization: 添加了 output_path
- [x] Audio Analysis: 正确配置 video_path 和 output_dir
- [x] Audio Scoring: 添加了 output_csv
- [x] OpenPose Analysis: 添加了 output_dir
- [x] Ball Tracking: 添加了 output_dir
- [x] Python 语法验证通过

## 🚀 部署步骤

1. **启动服务**
   ```bash
   cd meshflow_stabilize_with_audio_V2
   python server.py
   ```

2. **验证服务**
   - 访问 http://localhost:5000
   - 检查 Redis 连接

3. **测试处理**
   - 上传测试视频
   - 监控 processing.log
   - 检查输出文件

4. **监控处理**
   - 查看详细日志
   - 检查执行时长
   - 验证输出质量

## 📊 性能指标

| 步骤 | CPU | 内存 | 时间 | 输出 |
|------|-----|------|------|------|
| Stabilization | 高 | 中 | 45s | 400MB MP4 |
| Audio Analysis | 中 | 低 | 12s | 100KB CSV |
| Audio Scoring | 低 | 低 | 4s | 50KB CSV |
| OpenPose | 极高 | 高 | 95s | 500MB MP4 |
| Ball Tracking | 高 | 中 | 30s | 400MB MP4 |
| **总计** | - | - | **3-5min** | **1.5GB** |

## 🔍 故障排查

### 错误："output_path 不能為空"
**原因**：MeshFlowConfig 缺少 output_path  
**解决**：已修复，为稳定化输出提供路径

### 错误："找不到 MP4 影片檔案"
**原因**：输入目录不包含 MP4 文件  
**解决**：确保上传了有效的视频文件

### 步骤显示 "failed"
**原因**：处理函数执行失败  
**解决**：查看详细的日志消息了解具体错误

### 输出文件未生成
**原因**：输出目录权限不足  
**解决**：检查文件权限和磁盘空间

## 📝 日志文件

**主日志**：`{input_dir}/processing.log`
```
================================================================================
處理結果報告
================================================================================

隊列項目 ID: 1
視頻 ID: 345049fc-e84b-42df-811c-859dea4dd0d5
處理時間: 2026-02-03T11:44:14.029346

流程步驟:
  stabilization: completed (48.3s)
  audio_analysis: completed (12.5s)
  audio_scoring: completed (3.8s)
  openpose_analysis: completed (92.1s)
  ball_tracking: completed (26.2s)
```

**任务日志**：`meshflow_stabilize_with_audio_V2/logs/task_*.log`
```
2026-02-03 11:32:39 INFO: 🔄 執行處理流程 (超時: 1800s)...
2026-02-03 11:32:39 INFO: 🎬 步驟 1/5: 執行 Stabilization...
2026-02-03 11:33:27 INFO: ✅ Stabilization 完成 (48.3s)
...
```

## 🔗 相关文档

- [处理管道执行修复](PIPELINE_EXECUTION_FIX.md)
- [配置参数修复](PIPELINE_CONFIG_FIX.md)
- [项目状态](PROJECT_STATUS_PIPELINE_FIX.md)
- [检查清单](PIPELINE_EXECUTION_CHECKLIST.md)

## 📞 支持

遇到问题？检查以下资源：
1. processing.log 中的详细错误消息
2. task_*.log 中的执行日志
3. 项目文档中的故障排查部分
4. Redis 连接状态

---

**最后更新**：2026-02-03  
**状态**：✅ 已修复并验证

