import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../services/biomechanics_service.dart';

/// P1-P10 動作分析結果（持久化為 clip session 的 `angles.json`）。
///
/// - [pSec]：P1..P10 的 clip 相對秒數（p1=address、p4=top、p7=impact、p10=finish
///   為強錨點，其餘為手臂/桿身代理偵測，標 beta）。
/// - [perP]：每個 P 位置取樣到的生物力學指標（[BiomechMetric]）。
/// - [viewpoint]：拍攝視角；非 face-on 時旋轉/X-factor 類指標不可信（已於計算時 gate）。
/// - [overallScore]：0-100 整體分（各 P 子分平均），無可評指標時為 null。
class PSystemMetrics {
  /// P 位置標準順序。
  static const List<String> order = [
    'p1', 'p2', 'p3', 'p4', 'p5', 'p6', 'p7', 'p8', 'p9', 'p10'
  ];

  final Map<String, double> pSec;
  final Map<String, List<BiomechMetric>> perP;
  final SwingViewpoint viewpoint;
  final double? overallScore;

  const PSystemMetrics({
    required this.pSec,
    required this.perP,
    required this.viewpoint,
    this.overallScore,
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
        'viewpoint': viewpoint.name,
        if (overallScore != null) 'overallScore': overallScore,
        'pSec': pSec,
        'perP': perP.map(
            (k, v) => MapEntry(k, v.map((m) => m.toJson()).toList())),
      };

  factory PSystemMetrics.fromJson(Map<String, dynamic> j) {
    final pSecRaw = (j['pSec'] as Map?) ?? const {};
    final perPRaw = (j['perP'] as Map?) ?? const {};
    return PSystemMetrics(
      pSec: pSecRaw.map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      perP: perPRaw.map((k, v) => MapEntry(
            k as String,
            (v as List)
                .whereType<Map>()
                .map((m) => BiomechMetric.fromJson(
                    Map<String, dynamic>.from(m)))
                .toList(),
          )),
      viewpoint: SwingViewpoint.values.firstWhere(
        (vp) => vp.name == j['viewpoint'],
        orElse: () => SwingViewpoint.unknown,
      ),
      overallScore: (j['overallScore'] as num?)?.toDouble(),
    );
  }

  /// 寫入 `<sessionDir>/angles.json`（失敗靜默略過）。
  Future<void> save(String sessionDir) async {
    try {
      await File(p.join(sessionDir, 'angles.json'))
          .writeAsString(jsonEncode(toJson()));
    } catch (_) {/* 持久化失敗不阻斷主流程 */}
  }

  /// 從 `<sessionDir>/angles.json` 載入；不存在或解析失敗回 null。
  static Future<PSystemMetrics?> load(String sessionDir) async {
    try {
      final f = File(p.join(sessionDir, 'angles.json'));
      if (!await f.exists()) return null;
      final raw = jsonDecode(await f.readAsString());
      if (raw is! Map) return null;
      return PSystemMetrics.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }
}
