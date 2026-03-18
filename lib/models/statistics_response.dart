/// 統計數據響應模型
class StatisticsResponse {
  final bool success;
  final String period;
  final String? date;
  final int totalCount;
  final int goodShot;
  final int badShot;
  final double sweetSpotPercentage;
  final PeakValueStats peakValue;
  final AudioCrispnessStats audioCrispness;

  StatisticsResponse({
    required this.success,
    required this.period,
    this.date,
    required this.totalCount,
    required this.goodShot,
    required this.badShot,
    required this.sweetSpotPercentage,
    required this.peakValue,
    required this.audioCrispness,
  });

  /// 從 JSON 解析統計數據
  factory StatisticsResponse.fromJson(Map<String, dynamic> json) {
    return StatisticsResponse(
      success: json['success'] as bool? ?? false,
      period: json['period'] as String? ?? 'all',
      date: json['date'] as String?,
      totalCount: json['totalCount'] as int? ?? 0,
      goodShot: json['goodShot'] as int? ?? 0,
      badShot: json['badShot'] as int? ?? 0,
      sweetSpotPercentage: (json['sweetSpotPercentage'] as num?)?.toDouble() ?? 0.0,
      peakValue: PeakValueStats.fromJson(json['peakValue'] as Map<String, dynamic>? ?? {}),
      audioCrispness: AudioCrispnessStats.fromJson(json['audioCrispness'] as Map<String, dynamic>? ?? {}),
    );
  }

  /// 轉換為 JSON
  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'period': period,
      'date': date,
      'totalCount': totalCount,
      'goodShot': goodShot,
      'badShot': badShot,
      'sweetSpotPercentage': sweetSpotPercentage,
      'peakValue': peakValue.toJson(),
      'audioCrispness': audioCrispness.toJson(),
    };
  }

  @override
  String toString() {
    return 'StatisticsResponse(period: $period, totalCount: $totalCount, '
        'goodShot: $goodShot, badShot: $badShot, sweetSpotPercentage: $sweetSpotPercentage%)';
  }
}

/// 峰值速度統計
class PeakValueStats {
  final double average;
  final double maximum;

  PeakValueStats({
    required this.average,
    required this.maximum,
  });

  factory PeakValueStats.fromJson(Map<String, dynamic> json) {
    return PeakValueStats(
      average: (json['average'] as num?)?.toDouble() ?? 0.0,
      maximum: (json['maximum'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'average': average,
      'maximum': maximum,
    };
  }
}

/// 音頻清脆度統計
class AudioCrispnessStats {
  final double average;
  final double minimum;

  AudioCrispnessStats({
    required this.average,
    required this.minimum,
  });

  factory AudioCrispnessStats.fromJson(Map<String, dynamic> json) {
    return AudioCrispnessStats(
      average: (json['average'] as num?)?.toDouble() ?? 0.0,
      minimum: (json['minimum'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'average': average,
      'minimum': minimum,
    };
  }
}
