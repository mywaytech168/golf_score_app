import 'package:flutter/foundation.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// ============================================================
// TFLite 球體候選分類器
//
// 對 BallBlobExtractor 輸出的每個 blob 進行評分（0.0 ~ 1.0），
// 越高越可能是真正的高爾夫球。
//
// 模型路徑：assets/models/ball_classifier.tflite
// 輸入 shape：[1, 3]  → [area_norm, circ, diffMean_norm]
// 輸出 shape：[1, 1]  → 置信度
//
// 當模型檔案不存在時，自動 fallback 到規則式評分（不影響功能）。
// ============================================================
class TfliteBallClassifier {
  static const _modelAsset = 'assets/models/golfballyolov8n_int8.tflite';
  static const _scoreThreshold = 0.45; // 保留 blob 的最低分數

  Interpreter? _interpreter;
  bool _tried = false;

  /// 是否已成功載入 TFLite 模型
  bool get isModelLoaded => _interpreter != null;

  // ──────────────────────────────────────────────────────────
  // 初始化
  // ──────────────────────────────────────────────────────────

  /// 嘗試從 assets 載入 TFLite 模型（只執行一次）。
  /// 若模型不存在則 fallback 到規則式評分，不拋例外。
  Future<void> tryLoad() async {
    if (_tried) return;
    _tried = true;
    try {
      _interpreter = await Interpreter.fromAsset(_modelAsset);
      debugPrint('[TfliteBallClassifier] ✅ 模型載入成功: $_modelAsset');
    } catch (e) {
      debugPrint('[TfliteBallClassifier] ⚠️ 模型未找到，使用規則式評分: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  // 評分
  // ──────────────────────────────────────────────────────────

  /// 對單個 blob 評分（0.0 ~ 1.0）。
  /// [area]      - blob 面積（像素數）
  /// [circ]      - blob 圓度（0 ~ 1）
  /// [diffMean]  - blob 內幀差均值
  double score({
    required int area,
    required double circ,
    required double diffMean,
  }) {
    if (_interpreter != null) {
      return _scoreWithModel(area: area, circ: circ, diffMean: diffMean);
    }
    return _scoreHeuristic(area: area, circ: circ, diffMean: diffMean);
  }

  /// 判斷 blob 是否應保留（score >= threshold）
  bool accept({
    required int area,
    required double circ,
    required double diffMean,
  }) =>
      score(area: area, circ: circ, diffMean: diffMean) >= _scoreThreshold;

  // ──────────────────────────────────────────────────────────
  // 內部：TFLite 推理
  // ──────────────────────────────────────────────────────────

  double _scoreWithModel({
    required int area,
    required double circ,
    required double diffMean,
  }) {
    try {
      // 特徵歸一化
      final input = [
        [area / 200.0, circ, diffMean / 50.0]
      ];
      final output = [
        [0.0]
      ];
      _interpreter!.run(input, output);
      final raw = output[0][0];
      return (raw as double).clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('[TfliteBallClassifier] 推理失敗，fallback: $e');
      return _scoreHeuristic(area: area, circ: circ, diffMean: diffMean);
    }
  }

  // ──────────────────────────────────────────────────────────
  // 內部：規則式評分（model 不存在時的 fallback）
  // 比原版算法更嚴格的圓度與面積要求，去除更多假陽性
  // ──────────────────────────────────────────────────────────

  double _scoreHeuristic({
    required int area,
    required double circ,
    required double diffMean,
  }) {
    // 嚴格圓度過濾（原版 circ >= 0.25，TFLite fallback >= 0.50）
    if (circ < 0.50) return 0.0;
    // 面積範圍（比原版更嚴格）
    if (area < 8 || area > 300) return 0.0;
    // 最低幀差（排除靜態背景雜訊）
    if (diffMean < 5.0) return 0.0;

    // 加權評分
    final circScore = ((circ - 0.50) / 0.50).clamp(0.0, 1.0);
    final areaScore = (area >= 12 && area <= 150) ? 1.0 : 0.55;
    final diffScore = (diffMean / 25.0).clamp(0.0, 1.0);

    return (circScore * 0.50 + areaScore * 0.30 + diffScore * 0.20);
  }

  // ──────────────────────────────────────────────────────────
  // 釋放資源
  // ──────────────────────────────────────────────────────────

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _tried = false;
  }
}
