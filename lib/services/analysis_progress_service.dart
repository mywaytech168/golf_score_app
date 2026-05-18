import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 從 Kotlin 端接收分析進度事件的單例服務。
///
/// Kotlin 透過 EventChannel 'com.example.golf_score_app/analysis_progress'
/// 送出 Map 事件：{ op, progress, label, current, total }
///
/// op 對應關係：
///   analyzePose   → 骨架姿勢分析（analyzeVideoNatively）
///   renderSkeleton → 骨架疊加渲染（SkeletonOverlayRenderer）
///   extractBlobs  → 球追蹤分析（BallBlobExtractor）
///   renderOverlay → 軌跡疊加渲染（TrajectoryOverlayRenderer）
class AnalysisProgressService {
  AnalysisProgressService._();
  static final AnalysisProgressService instance = AnalysisProgressService._();

  static const _channel = EventChannel('com.example.golf_score_app/analysis_progress');

  /// 目前進度：(progress 0.0~1.0, 顯示標籤)
  final ValueNotifier<(double, String)> progress = ValueNotifier((0.0, ''));

  /// 目前正在執行的 op 名稱（空字串表示閒置）
  String currentOp = '';

  bool _listening = false;

  /// 開始監聽 EventChannel（App 啟動時呼叫一次即可）
  void start() {
    if (_listening) return;
    _listening = true;
    _channel.receiveBroadcastStream().listen(
      (dynamic event) {
        if (event is! Map) return;
        final op       = event['op']       as String? ?? '';
        final pct      = (event['progress'] as num?)?.toDouble() ?? 0.0;
        final label    = event['label']    as String? ?? '';
        currentOp = op;
        progress.value = (pct, label);
      },
      onError: (dynamic err) {
        debugPrint('[AnalysisProgress] EventChannel 錯誤: $err');
      },
    );
  }

  /// 重置進度（每次分析開始前呼叫）
  void reset([String label = '']) {
    currentOp = '';
    progress.value = (0.0, label);
  }
}
