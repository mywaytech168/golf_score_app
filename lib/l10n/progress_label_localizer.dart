import 'package:golf_score_app/l10n/app_localizations.dart';

/// 把分析 / 偵測 service 與 native 層送來的進度文字（多為寫死中文）對應到當前語系。
///
/// 進度 label 由多個無 BuildContext 的 service 產生（VideoAnalysisService /
/// VideoAnalysisPipelineService / ClipPipelineService / native EventChannel），
/// 無法在來源直接取 l10n。改在「顯示端」統一轉譯：對得上就回當前語系，
/// 對不上原樣回傳（至少仍顯示，且已是 l10n 的 label 會走 default 原樣通過）。
String localizeProgressLabel(AppLocalizations l10n, String raw) {
  final t = raw.trim();

  // native「骨架分析中 N%」：抽出百分比以當前語系重組。
  if (t.contains('骨架分析')) {
    final m = RegExp(r'(\d+)\s*%').firstMatch(t);
    if (m != null) return l10n.analysisProgressPosePct(int.parse(m.group(1)!));
  }

  // native VideoTranscoder 轉檔/轉碼（含動態 %、MOV 轉換、重新封裝、完成）。
  if (t.contains('轉換完成') || t.contains('轉碼完成')) {
    return l10n.extImportProgressTranscodeDone;
  }
  if (t.contains('MOV 轉換中') || t.contains('轉換中') || t.contains('轉碼中') ||
      t.contains('轉碼準備中') || t.contains('重新封裝')) {
    final m = RegExp(r'(\d+)\s*%').firstMatch(t);
    return m != null
        ? l10n.extImportProgressTranscodingPct(int.parse(m.group(1)!))
        : l10n.extImportProgressTranscoding;
  }

  switch (t) {
    case '分析骨架中...':
    case '分析骨架中…':
    case 'V2 骨架分析中...':
    case 'V2 骨架分析中…':
      return l10n.analysisProgressPose;
    case '提取音訊中...':
    case '提取音訊中…':
      return l10n.analysisProgressAudio;
    case '骨架分析完成':
      return l10n.analysisProgressPoseDone;
    case '完成':
      return l10n.analysisProgressDone;
    case '使用既有分析資料...':
    case '使用既有分析資料…':
      return l10n.analysisProgressUsingExisting;
    case '球追蹤分析中...':
    case '球追蹤分析中…':
    case '追蹤球軌跡中...':
    case '追蹤球軌跡中…':
      return l10n.analysisProgressBallTrack;
    case 'P0 偵測中...':
    case 'P0 偵測中…':
      return l10n.analysisProgressP0;
    default:
      return raw; // 已是 l10n 字串或未知 → 原樣顯示
  }
}
