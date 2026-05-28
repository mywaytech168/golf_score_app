import 'dart:convert';
import 'dart:io';

class SwingHit {
  final int hitIndex;
  final int hitFrame;   // Y-LOW 幀（手腕最低點 = 撞球瞬間）
  final double hitSec;
  final double startSec;
  final double endSec;
  final double speedValue;
  final double audioValue;
  // ── speed_y_low 算法附加欄位 ──────────────────────────────────────
  final int fastFrame;  // 速度峰值幀 (FAST)
  final int topFrame;   // 後擺頂點幀 (TOP)

  // ── 揮桿 8 階段關鍵禎（秒數，相對於原始影片）────────────────────
  final double addressSec;       // ① 準備姿勢（最靜止的設定位置）
  final double takeawaySec;      // ② 起桿（速度開始上升）
  final double backswingSec;     // ③ 上桿中段（takeaway 到頂點的中間）
  final double backswingTopSec;  // ④ 頂點（上桿最高點 = topFrame / fps）
  final double downswingSec;     // ⑤ 下桿中段（頂點到擊球的中間）
  // ⑥ 擊球 = hitSec（已有）
  final double followThroughSec; // ⑦ 送桿
  final double finishSec;        // ⑧ 收桿（速度歸零後的靜止位置）

  const SwingHit({
    required this.hitIndex,
    required this.hitFrame,
    required this.hitSec,
    required this.startSec,
    required this.endSec,
    required this.speedValue,
    required this.audioValue,
    this.fastFrame = 0,
    this.topFrame = 0,
    this.addressSec = 0.0,
    this.takeawaySec = 0.0,
    this.backswingSec = 0.0,
    this.backswingTopSec = 0.0,
    this.downswingSec = 0.0,
    this.followThroughSec = 0.0,
    this.finishSec = 0.0,
  });

  Map<String, dynamic> toJson() => {
        'hitIndex': hitIndex,
        'hitFrame': hitFrame,
        'hitSec': hitSec,
        'startSec': startSec,
        'endSec': endSec,
        'speedValue': speedValue,
        'audioValue': audioValue,
        'fastFrame': fastFrame,
        'topFrame': topFrame,
        'addressSec': addressSec,
        'takeawaySec': takeawaySec,
        'backswingSec': backswingSec,
        'backswingTopSec': backswingTopSec,
        'downswingSec': downswingSec,
        'followThroughSec': followThroughSec,
        'finishSec': finishSec,
      };

  factory SwingHit.fromJson(Map<String, dynamic> j) => SwingHit(
        hitIndex: (j['hitIndex'] as num).toInt(),
        hitFrame: (j['hitFrame'] as num).toInt(),
        hitSec: (j['hitSec'] as num).toDouble(),
        startSec: (j['startSec'] as num).toDouble(),
        endSec: (j['endSec'] as num).toDouble(),
        speedValue: (j['speedValue'] as num).toDouble(),
        audioValue: (j['audioValue'] as num).toDouble(),
        fastFrame: (j['fastFrame'] as num?)?.toInt() ?? (j['hitFrame'] as num).toInt(),
        topFrame: (j['topFrame'] as num?)?.toInt() ?? 0,
        addressSec:       (j['addressSec']       as num?)?.toDouble() ?? 0.0,
        takeawaySec:      (j['takeawaySec']      as num?)?.toDouble() ?? 0.0,
        backswingSec:     (j['backswingSec']      as num?)?.toDouble() ?? 0.0,
        backswingTopSec:  (j['backswingTopSec']  as num?)?.toDouble() ?? 0.0,
        downswingSec:     (j['downswingSec']      as num?)?.toDouble() ?? 0.0,
        followThroughSec: (j['followThroughSec'] as num?)?.toDouble() ?? 0.0,
        finishSec:        (j['finishSec']         as num?)?.toDouble() ?? 0.0,
      );

  Duration get startDuration => Duration(milliseconds: (startSec * 1000).round());
  Duration get endDuration => Duration(milliseconds: (endSec * 1000).round());
  Duration get hitDuration => Duration(milliseconds: (hitSec * 1000).round());

  /// 從 session 資料夾讀取 hits.json
  static Future<List<SwingHit>> loadFromSession(String sessionDir) async {
    try {
      final file = File('$sessionDir/hits.json');
      if (!await file.exists()) return [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return [];
      return raw
          .whereType<Map<String, dynamic>>()
          .map(SwingHit.fromJson)
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 將 hits 寫入 session 資料夾
  static Future<void> saveToSession(
      String sessionDir, List<SwingHit> hits) async {
    final file = File('$sessionDir/hits.json');
    await file.writeAsString(
        jsonEncode(hits.map((h) => h.toJson()).toList()));
  }
}
