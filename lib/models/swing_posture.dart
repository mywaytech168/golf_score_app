import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// 揮桿姿勢分類 label 常數
/// 對應後端 模型 dataset.py 的 CLASS_TO_LABELS 定義：
///   Good → error_type = "" (完美，無錯誤)
///   其餘 5 種 → 對應 ERROR_LABELS
class SwingPosture {
  SwingPosture._();

  // ── Label 字串常數 ─────────────────────────────────────────────
  static const String good              = '';
  static const String earlyRelease      = 'early_release_casting';
  static const String impact            = 'impact';
  static const String overTheTop        = 'over_the_top';
  static const String spineAngle        = 'spine_angle';
  static const String weightShift       = 'weight_shift';

  /// 所有 5 種錯誤 label（順序固定，供 UI 排列）
  static const List<String> errorLabels = [
    earlyRelease,
    impact,
    overTheTop,
    spineAngle,
    weightShift,
  ];

  /// 全部 6 種 label（完美在前）
  static const List<String> allLabels = [
    good,
    earlyRelease,
    impact,
    overTheTop,
    spineAngle,
    weightShift,
  ];

  // ── 中文名稱 ──────────────────────────────────────────────────
  static String zhName(String label) => switch (label) {
    ''                       => '完美姿勢',
    'early_release_casting'  => '早放拋桿',
    'impact'                 => '撞擊失誤',
    'over_the_top'           => '外側切入',
    'spine_angle'            => '脊柱角度',
    'weight_shift'           => '重心轉移',
    _                        => label,
  };

  /// 多語系名稱（單一真相）。error_type 為 enum 值，固定英文，
  /// 顯示時用此方法翻成介面語言（不依賴 Gemini 回傳的 zh_name）。
  static String localizedName(AppLocalizations l, String label) => switch (label) {
    ''                       => l.aiCoachErrorPerfect,
    'early_release_casting'  => l.aiCoachErrorEarlyRelease,
    'impact'                 => l.aiCoachErrorImpact,
    'over_the_top'           => l.aiCoachErrorOverTheTop,
    'spine_angle'            => l.aiCoachErrorSpineAngle,
    'weight_shift'           => l.aiCoachErrorWeightShift,
    _                        => label,
  };

  // ── 圖示 ──────────────────────────────────────────────────────
  static IconData icon(String label) => switch (label) {
    ''                       => Icons.star_rounded,
    'early_release_casting'  => Icons.back_hand_outlined,
    'impact'                 => Icons.sports_golf_outlined,
    'over_the_top'           => Icons.rotate_right,
    'spine_angle'            => Icons.accessibility_new,
    'weight_shift'           => Icons.swap_horiz,
    _                        => Icons.warning_amber_rounded,
  };

  // ── 主色 ──────────────────────────────────────────────────────
  static Color color(String label) => switch (label) {
    ''   => const Color(0xFF4CAF50),   // 綠：完美
    _    => const Color(0xFFE57373),   // 紅：錯誤
  };

  /// 是否為完美揮桿（Good class）
  static bool isPerfect(String? label) => label == null || label.isEmpty;
}
