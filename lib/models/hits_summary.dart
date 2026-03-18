import 'package:flutter/foundation.dart';

/// 單一摆球的信息，对应 hits_summary.csv 中的一行
@immutable
class HitsSummary {
  /// 摆球编号，例如 "hit_001"
  final String hit;

  /// 摆球的时间戳（秒），从视频开始
  final double tHit;

  /// 切片视频的开始时间（秒）
  final double startT;

  /// 切片视频的结束时间（秒）
  final double endT;

  /// 加速度峰值（G），用于表示摆球的强度
  final double peakSmooth;

  /// 检测来源，例如 "Codi2"（右手腕）
  final String? detectFrom;

  const HitsSummary({
    required this.hit,
    required this.tHit,
    required this.startT,
    required this.endT,
    required this.peakSmooth,
    this.detectFrom,
  });

  /// 获取摆球编号（纯数字）
  int get hitNumber {
    final match = RegExp(r'(\d+)').firstMatch(hit);
    if (match != null) {
      return int.tryParse(match.group(1)!) ?? 0;
    }
    return 0;
  }

  /// 获取摆球时长（秒）
  double get duration => endT - startT;

  /// 获取友好的时间显示（mm:ss.ms）
  String get formattedHitTime {
    final minutes = tHit ~/ 60;
    final seconds = tHit.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toStringAsFixed(2).padLeft(5, '0')}';
  }

  /// 将 HitsSummary 转换为 CSV 行
  String toCsvLine() {
    return '$hit,${tHit.toStringAsFixed(6)},${startT.toStringAsFixed(6)},${endT.toStringAsFixed(6)},${peakSmooth.toStringAsFixed(6)},${detectFrom ?? ''}';
  }

  /// 从 CSV 行解析 HitsSummary
  factory HitsSummary.fromCsvLine(String line) {
    final parts = line.split(',');
    if (parts.length < 5) {
      throw FormatException('Invalid CSV line format: $line');
    }

    return HitsSummary(
      hit: parts[0].trim(),
      tHit: double.parse(parts[1].trim()),
      startT: double.parse(parts[2].trim()),
      endT: double.parse(parts[3].trim()),
      peakSmooth: double.parse(parts[4].trim()),
      detectFrom: parts.length > 5 && parts[5].trim().isNotEmpty ? parts[5].trim() : null,
    );
  }

  /// 创建一个副本，支持部分字段更新
  HitsSummary copyWith({
    String? hit,
    double? tHit,
    double? startT,
    double? endT,
    double? peakSmooth,
    String? detectFrom,
  }) {
    return HitsSummary(
      hit: hit ?? this.hit,
      tHit: tHit ?? this.tHit,
      startT: startT ?? this.startT,
      endT: endT ?? this.endT,
      peakSmooth: peakSmooth ?? this.peakSmooth,
      detectFrom: detectFrom ?? this.detectFrom,
    );
  }

  @override
  String toString() =>
      'HitsSummary(hit=$hit, tHit=$tHit, startT=$startT, endT=$endT, peakSmooth=$peakSmooth, detectFrom=$detectFrom)';
}
