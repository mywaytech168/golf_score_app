/**
 * 錄影模組整合指南
 * 
 * 本文件說明如何在 golf_score_app 中整合新的骨架檢測錄影模組。
 */

// ── 1. 在頁面中使用 RecordScreen ──────────────────────────────

// 範例：在現有頁面中打开錄影 Screen
import 'package:golf_score_app/recording/record_screen.dart';

void _openRecordingScreen(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (context) => RecordScreen(
        onComplete: ({
          required String videoPath,
          required String csvPath,
          required String audioPath,
        }) {
          // 處理錄影完成回呼
          print('Video: $videoPath');
          print('Pose CSV: $csvPath');
          print('Audio: $audioPath');
          
          // 可在此上傳文件或進行下一步處理
          Navigator.pop(context, {
            'videoPath': videoPath,
            'csvPath': csvPath,
            'audioPath': audioPath,
          });
        },
      ),
    ),
  );
}


// ── 2. 獨立使用各個模組組件 ──────────────────────────────

// 2.1 使用 PoseDetectorService 進行骨架偵測
import 'package:golf_score_app/recording/pose_detector_service.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

final poseService = PoseDetectorService();

// 偵測影像中的骨架
final poses = await poseService.detect(inputImage);
// poses 是 List<Pose>，包含檢測到的所有身體姿態

poseService.dispose(); // 使用完畢後記得釋放


// 2.2 使用 PoseFrameModel 和 PoseCsvWriter 匯出骨架資料
import 'package:golf_score_app/recording/pose_frame_model.dart';
import 'package:golf_score_app/recording/pose_csv_writer.dart';

// 創建每一幀的骨架數據
final frame = PoseFrameModel.fromPose(
  frame: 0,
  timeSec: 0.0,
  pose: poses.first,
  imgWidth: 1920,
  imgHeight: 1080,
);

// 使用 CSV 寫入器
final csvWriter = PoseCsvWriter('/path/to/pose_landmarks.csv');
csvWriter.addFrame(frame);
await csvWriter.flush(); // 寫入文件


// 2.3 使用 SkeletonPainter 在 Canvas 上繪製骨架
import 'package:golf_score_app/recording/skeleton_painter.dart';

CustomPaint(
  painter: SkeletonPainter(
    poses: detectedPoses,
    imageSize: Size(1920, 1080),
  ),
  child: // ... 其他 widget
)


// ── 3. 輸出文件說明 ──────────────────────────────

/*
錄影完成後會在應用程序文檔目錄中生成：

{Documents}/session_{timestamp}/
├── raw.mp4               # 原始影片（無音軌，H.264 編碼）
├── pose_landmarks.csv    # 骨架資料（200 欄，與 Python 格式一致）
└── audio.aac             # 獨立音軌（AAC 編碼）

CSV 文件格式（每行一幀）：
- frame: 幀序號（0-based）
- time_sec: 時間戳（秒，6 位小數）
- lmN_x_norm: 正規化 x 座標（0~1）
- lmN_y_norm: 正規化 y 座標（0~1）
- lmN_z: 深度估算值
- lmN_visibility: 可見度置信度（0~1）
- lmN_x_px: 像素 x 座標
- lmN_y_px: 像素 y 座標

共 33 個關鍵點（lm0 ~ lm32）：
0=nose, 1=left_eye_inner, 2=left_eye, 3=left_eye_outer, 4=right_eye_inner,
5=right_eye, 6=right_eye_outer, 7=left_ear, 8=right_ear,
9=mouth_left, 10=mouth_right, 11=left_shoulder, 12=right_shoulder,
13=left_elbow, 14=right_elbow, 15=left_wrist, 16=right_wrist,
17=left_pinky, 18=right_pinky, 19=left_index, 20=right_index,
21=left_thumb, 22=right_thumb, 23=left_hip, 24=right_hip,
25=left_knee, 26=right_knee, 27=left_ankle, 28=right_ankle,
29=left_heel, 30=left_foot_index, 31=right_heel, 32=right_foot_index
*/


// ── 4. 與現有 RecordingSessionPage 的關係 ──────────────────

/*
新的 recording 模組是獨立的骨架檢測錄影實現，功能專注於：
- 即時骨架推論
- 精確的幀級別時間戳
- Python 格式相容的 CSV 輸出

現有的 RecordingSessionPage 用於完整的高爾夫揮桿分析（包含 IMU 等）。
兩者可並行存在，也可後續整合到同一個頁面中。

建議做法：
1. 먼저 新模組與現有流程並行測試
2. 確認 CSV 和文件格式後，決定是否整合或替換
*/


// ── 5. 常見使用場景 ──────────────────────────────

// 場景 A: 簡單的錄影 + 骨架輸出
// → 直接使用 RecordScreen

// 場景 B: 與其他服務整合（上傳、分析）
// → 在 onComplete 回呼中實現邏輯

// 場景 C: 自訂骨架預覽
// → 使用 PoseDetectorService + SkeletonPainter 自行組合

// 場景 D: 批量處理視頻
// → 使用 PoseDetectorService 逐幀處理已有視頻


// ── 6. 故障排除 ──────────────────────────────

/*
問題 1: iOS 模擬器無法運行
→ ML Kit 不支援模擬器，需真機測試

問題 2: 幀率不穩定
→ _fps = 30.0（預設），根據實際調整
→ 若推論速度跟不上，會自動跳幀（_isProcessing lock）

問題 3: 記憶體用量過高
→ _frameBuffer 全程記憶體暫存，建議錄影 < 60 秒
→ 需要更長錄影可改用流式寫入

問題 4: 音視頻不同步
→ 影片和音訊獨立錄製，後續需對齐時間戳
→ 使用 time_sec 列進行對齐

問題 5: Android 權限拒絕
→ 檢查 AndroidManifest.xml 已包含 CAMERA 和 RECORD_AUDIO
→ 運行時需向用戶請求權限（permission_handler）
*/


// ── 7. 后续集成路线图 ──────────────────────────────

/*
第一步：独立测试
- ✅ 创建 lib/recording/ 模块
- 测试 RecordScreen 基本功能
- 验证 CSV 格式

第二步：集成到现有流程
- 在 RecorderPage 中添加骨架录影选项
- 处理 onComplete 回调，存储文件路径
- 更新 RecordingHistoryEntry 模型以包含 CSV 路径

第三步：后端集成
- 将生成的三个文件上传到服务器
- 后端运行轨迹检测模块处理 CSV
- 返回检测结果给应用

第四步：UI/UX 优化
- 在锻炼记录中显示骨架检测结果
- 提供骨架预览回放
- 性能优化（根据设备能力调节幀率）
*/
