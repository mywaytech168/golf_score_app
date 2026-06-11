import 'dart:io';

import 'package:path/path.dart' as p;

/// 解析 session 目錄中可用的骨架 CSV 路徑。
///
/// 優先使用逐幀分析產出的 `pose_landmarks.csv`（與影片幀數一致）；
/// 尚未產出時（剛錄完、背景分析還在跑）退回錄影即時推論的
/// `pose_landmarks.live.csv`（~10-25fps 取樣，PoseTrack 取樣時會插值）。
///
/// 僅供「顯示用途」（骨架疊圖、圖表、預覽）——擊球偵測等精度需求
/// 必須走 `VideoAnalysisPipelineService.analyzeBasic` 取得逐幀版。
String? resolveSkeletonCsv(String sessionDir) {
  final full = p.join(sessionDir, 'pose_landmarks.csv');
  if (File(full).existsSync()) return full;
  final live = p.join(sessionDir, 'pose_landmarks.live.csv');
  if (File(live).existsSync()) return live;
  return null;
}
