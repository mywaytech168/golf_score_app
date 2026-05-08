import 'dart:convert';
import 'dart:io';

class SwingHit {
  final int hitIndex;
  final int hitFrame;
  final double hitSec;
  final double startSec;
  final double endSec;
  final double speedValue;
  final double audioValue;

  const SwingHit({
    required this.hitIndex,
    required this.hitFrame,
    required this.hitSec,
    required this.startSec,
    required this.endSec,
    required this.speedValue,
    required this.audioValue,
  });

  Map<String, dynamic> toJson() => {
        'hitIndex': hitIndex,
        'hitFrame': hitFrame,
        'hitSec': hitSec,
        'startSec': startSec,
        'endSec': endSec,
        'speedValue': speedValue,
        'audioValue': audioValue,
      };

  factory SwingHit.fromJson(Map<String, dynamic> j) => SwingHit(
        hitIndex: (j['hitIndex'] as num).toInt(),
        hitFrame: (j['hitFrame'] as num).toInt(),
        hitSec: (j['hitSec'] as num).toDouble(),
        startSec: (j['startSec'] as num).toDouble(),
        endSec: (j['endSec'] as num).toDouble(),
        speedValue: (j['speedValue'] as num).toDouble(),
        audioValue: (j['audioValue'] as num).toDouble(),
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
