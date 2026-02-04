# 🔧 处理管道配置参数修复

## 问题

执行处理管道时发生错误：
```
"stabilization": {
  "status": "failed",
  "error": "output_path 不能為空"
}
```

## 根本原因

各处理函数的 Config 类需要特定的必需参数：
- **MeshFlowConfig**：需要 `input_path` 和 `output_path`
- **AudioAnalysisConfig**：需要 `video_path` 和 `output_dir`
- **AudioScoringConfig**：需要 `csv_folder`，可选 `output_csv`
- **MediaPoseConfig**：需要 `video_path`，可选 `output_dir`
- **BallTrackingConfig**：需要 `input_dir`，可选 `output_dir`

原始实现没有为所有这些参数提供值。

## 解决方案

已更新所有 5 个处理步骤，为每个 Config 类提供必要的参数。

### 修改详情

#### 步骤 1: Stabilization
```python
video_files = list(input_path.glob("*.mp4"))
if not video_files:
    raise ValueError("找不到 MP4 影片檔案")

output_stabilized = input_path / f"stabilized_{video_files[0].name}"
config = MeshFlowConfig(
    input_path=str(video_files[0]),
    output_path=str(output_stabilized)
)
```
- 查找输入视频文件
- 为稳定化输出创建输出路径
- 提供 input_path 和 output_path

#### 步骤 2: Audio Analysis
```python
config = AudioAnalysisConfig(
    video_path=str(video_files[0]),
    output_dir=str(input_path)
)
```
- 使用第一个找到的 MP4 文件作为 video_path
- 使用输入目录作为 output_dir

#### 步骤 3: Audio Scoring
```python
output_scoring_csv = input_path / "audio_scoring_results.csv"
config = AudioScoringConfig(
    csv_folder=str(input_path),
    video_root=str(input_path),
    output_csv=str(output_scoring_csv)
)
```
- csv_folder：存储 CSV 分析结果的目录
- video_root：视频根目录
- output_csv：评分结果输出路径

#### 步骤 4: OpenPose Analysis
```python
output_pose_dir = input_path / "pose_analysis"
config = MediaPoseConfig(
    video_path=str(video_files[0]),
    output_dir=str(output_pose_dir)
)
```
- video_path：输入视频
- output_dir：姿势分析结果输出目录

#### 步骤 5: Ball Tracking
```python
output_tracking_dir = input_path / "ball_tracking"
config = BallTrackingConfig(
    batch_mode=True,
    input_dir=str(input_path),
    output_dir=str(output_tracking_dir)
)
```
- batch_mode：启用批处理模式
- input_dir：输入视频目录
- output_dir：球追踪结果输出目录

## 输出目录结构

处理完成后，输入目录将包含以下结构：

```
input_dir/
├── original_video.mp4              # 原始视频
├── stabilized_original_video.mp4   # 稳定化视频 (步骤 1)
├── original_video_audio.wav        # 提取的音频 (步骤 2)
├── audio_scoring_results.csv       # 音频评分结果 (步骤 3)
├── pose_analysis/                  # 姿势分析输出 (步骤 4)
│   ├── pose_keypoints.csv
│   ├── pose_phases.csv
│   └── pose_video.mp4
├── ball_tracking/                  # 球追踪输出 (步骤 5)
│   └── ball_tracking.mp4
└── processing.log                  # 处理日志
```

## 验证步骤

✅ **已完成的验证**：
- Python 语法验证通过
- 所有必需参数已提供
- 所有 Config 对象可正确初始化
- 错误处理已实现

⏳ **待验证**：
- 实际执行时能否成功创建输出目录
- 能否正确读取输入文件
- 能否成功生成输出文件

## 预期结果

修改后，处理管道应该能够：
1. ✅ 正确初始化所有 Config 对象
2. ✅ 找到输入视频文件
3. ✅ 创建必要的输出目录
4. ✅ 执行每个处理步骤
5. ✅ 生成输出文件
6. ✅ 记录处理日志

## 修改文件

**文件**：`meshflow_stabilize_with_audio_V2/services/task_queue.py`

**修改行数**：
- 步骤 1 (Stabilization)：约 436-458
- 步骤 2 (Audio Analysis)：约 460-483
- 步骤 3 (Audio Scoring)：约 485-508
- 步骤 4 (OpenPose)：约 510-533
- 步骤 5 (Ball Tracking)：约 535-556

**修改内容**：
- 为每个 Config 类提供完整的必需参数
- 修复了缺失的 output_path 和 output_dir
- 改进了错误处理和验证

## 下一步

当处理管道再次运行时：
1. 第一个错误（output_path）应该被修复
2. 如果出现新的参数错误，更新相应的 Config 初始化
3. 监控处理.log 文件查看详细执行情况
4. 检查输出目录是否包含预期的文件

