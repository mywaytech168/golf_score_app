import 'dart:async';

import 'package:flutter/material.dart';

import '../models/swing_posture.dart';
import '../services/analysis_service.dart';
import '../services/plan_service.dart';
import '../theme/app_theme.dart';

/// AI Coach 分析頁面
/// 接收 analysisId（已完成步驟 1~3），輪詢結果並顯示教練評語
class AiCoachPage extends StatefulWidget {
  final String analysisId;
  final String? clipPath;
  /// 供「重新分析」按鈕使用
  final String? videoId;
  final String? csvPath;
  /// 分析完成後回呼
  /// - [geminiErrorType]：Gemini 分析的姿勢錯誤類型（'' = 完美）
  /// - [onnxErrorType]：ONNX 模型的姿勢錯誤類型（null = 無結果）
  /// - [analysisId]：本次分析 ID
  /// - [result]：完整教練分析結果（含 practiceSuggestions / nextTrainingGoal），可能為 null
  final void Function(String geminiErrorType, String? onnxErrorType, String analysisId, CoachResult? result)? onAnalysisComplete;

  const AiCoachPage({
    super.key,
    required this.analysisId,
    this.clipPath,
    this.videoId,
    this.csvPath,
    this.onAnalysisComplete,
  });

  /// 從 clip 路徑一次完成提交並導向本頁。
  ///
  /// - [forceReanalyze]=false（預設）：若已有 completed/進行中分析則直接導向，不重複提交
  /// - [forceReanalyze]=true：強制提交新分析（由「重新分析」按鈕觸發）
  /// - 若提供 [csvPath]，一併上傳骨架 CSV；ONNX 推論由後端 Worker 執行
  static Future<void> submitAndPush({
    required BuildContext context,
    required String videoId,
    required String clipPath,
    String? csvPath,
    /// V3 時傳入 audio.wav 的完整路徑（存在才上傳）
    String? audioPath,
    bool forceReanalyze = false,
    String promptVersion = 'v1',
    Map<String, double>? phaseTimestamps,
    /// V2：覆蓋 server FPS 設定（null = 使用 server 預設）
    int? v2Fps,
    /// V2："MEDIA_RESOLUTION_HIGH" | "MEDIA_RESOLUTION_MEDIUM"（null = 使用 server 預設）
    String? v2Resolution,
    String? audioAnalysisJson,
    void Function(String geminiErrorType, String? onnxErrorType, String analysisId, CoachResult? result)? onAnalysisComplete,
  }) async {
    // ── Cache Check ──────────────────────────────────────────
    // 已有 full 分析 → 直接開啟（避免重複上傳 / 消耗配額）
    // 已有 posture_only(idle) → 升級為 full（沿用 ONNX 結果，只補 Gemini）
    if (!forceReanalyze) {
      try {
        final existing =
            await AnalysisService.instance.getLatestAnalysisForVideo(videoId);
        if (existing != null && !existing.isFailed) {
          final isPostureOnly = existing.mode == 'posture_only';

          if (isPostureOnly && existing.isIdle && promptVersion != 'v3') {
            // posture_only 完成 → 升級至 full，沿用已有 ONNX 結果
            // V3 不走此路徑：posture_only 當初沒有 keyframes/audio，upgrade 後 Worker 會崩潰
            debugPrint('[AiCoach] posture_only(idle) ${existing.analysisId} → 升級為 full');
            await AnalysisService.instance.upgradeAnalysis(
              existing.analysisId,
              promptVersion: promptVersion,
            );
            if (context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AiCoachPage(
                  analysisId:         existing.analysisId,
                  clipPath:           clipPath,
                  videoId:            videoId,
                  csvPath:            csvPath,
                  onAnalysisComplete: onAnalysisComplete,
                ),
              ));
            }
            return;
          }

          if (!isPostureOnly) {
            // full 分析已存在（completed / idle / active）→ 直接開啟
            debugPrint('[AiCoach] 已有 full 分析 ${existing.analysisId} '
                '(${existing.status})，直接開啟');
            if (context.mounted) {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => AiCoachPage(
                  analysisId:         existing.analysisId,
                  clipPath:           clipPath,
                  videoId:            videoId,
                  csvPath:            csvPath,
                  onAnalysisComplete: onAnalysisComplete,
                ),
              ));
            }
            return;
          }
        }
      } catch (e) {
        debugPrint('[AiCoach] 快取查詢失敗（略過）: $e');
      }
    }

    // 提交新的 full 分析
    final analysisId = await AnalysisService.instance.submitForAnalysis(
      videoId:           videoId,
      clipPath:          clipPath,
      csvPath:           csvPath,
      audioPath:         audioPath,
      mode:              'full',
      promptVersion:     promptVersion,
      phaseTimestamps:   phaseTimestamps,
      v2Fps:             v2Fps,
      v2Resolution:      v2Resolution,
      audioAnalysisJson: audioAnalysisJson,
    );
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AiCoachPage(
          analysisId:          analysisId,
          clipPath:            clipPath,
          videoId:             videoId,
          csvPath:             csvPath,
          onAnalysisComplete:  onAnalysisComplete,
        ),
      ));
    }
  }

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  static const _pollInterval = Duration(seconds: 3);

  AnalysisStatus? _status;
  Timer? _timer;
  String? _error;
  bool _resultReported = false;
  bool _isUpgrading = false;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startPolling() {
    _poll(); // 立即查一次
    _timer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  Future<void> _upgrade() async {
    if (_isUpgrading) return;
    setState(() => _isUpgrading = true);
    try {
      await AnalysisService.instance.upgradeAnalysis(widget.analysisId);
      // 重啟輪詢等待 Gemini 完成
      _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() => _isUpgrading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('升級失敗: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // 重新分析入口暫時下架（appBar actions 已清空），流程保留供回復
  // ignore: unused_element
  Future<void> _reanalyze() async {
    _timer?.cancel();
    final vid  = widget.videoId;
    final clip = widget.clipPath;
    if (vid == null || clip == null) return;
    if (!mounted) return;

    // ── 重新分析前先檢查球數配額 ─────────────────────────────────
    try {
      final planStatus = await PlanService.getPlanStatus();
      if (!mounted) return;
      if (!planStatus.plan.isUnlimited && planStatus.remaining <= 0) {
        await showDialog<void>(
          context: context,
          builder: (_) => AlertDialog(
            icon: const Icon(Icons.sports_golf_rounded,
                color: Color(0xFF7C3AED), size: 32),
            title: const Text('今日球數已用完'),
            content: Text(
              '今日已使用 ${planStatus.todayUsed} 次，已達上限 ${planStatus.totalLimit} 次。\n\n'
              '明天可繼續使用，或升級方案取得更多次數。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('知道了'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      // 後端不可用時讓使用者繼續（後端會做最終驗證）
      debugPrint('[AiCoach] 重新分析配額檢查失敗（略過）: $e');
    }

    if (!mounted) return;

    // 以 forceReanalyze=true 取代目前頁面
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => _ReanalyzeLoader(
          videoId:  vid,
          clipPath: clip,
          csvPath:  widget.csvPath,
        ),
      ),
    );
  }

  Future<void> _poll() async {
    try {
      final status = await AnalysisService.instance.getStatus(widget.analysisId);
      if (mounted) {
        setState(() {
          _status = status;
          _error  = null;
        });
        if (status.isDone) {
          _timer?.cancel();
          // 分析完成時回呼一次，傳出 errorType 供上層寫入 swingPostureLabel
          if (status.isCompleted && !_resultReported) {
            _resultReported = true;
            // Gemini 結果
            final rawGemini = status.result?.primaryError.errorType ?? '';
            final geminiType = SwingPosture.allLabels.contains(rawGemini) ? rawGemini : '';
            if (rawGemini != geminiType) {
              debugPrint('[AiCoach] Gemini errorType 正規化: "$rawGemini" → "$geminiType"');
            }
            // ONNX 結果：優先取 officialErrors，次取 suspectErrors
            final rawOnnx = status.onnxResult?.officialErrors.firstOrNull
                ?? status.onnxResult?.suspectErrors.firstOrNull;
            final onnxType = rawOnnx != null && SwingPosture.allLabels.contains(rawOnnx)
                ? rawOnnx
                : null;
            widget.onAnalysisComplete?.call(geminiType, onnxType, widget.analysisId, status.result);
          }
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      appBar: AppBar(
        title: const Text('AI 教練分析'),
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: const [],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_error != null && _status == null) {
      return _ErrorView(error: _error!, onRetry: _startPolling);
    }

    final status = _status;
    if (status == null || !status.isDone) {
      return _LoadingView(status: status?.status);
    }

    if (status.isFailed) {
      return _ErrorView(
        error: '分析失敗，請重試',
        onRetry: () => Navigator.of(context).pop(),
      );
    }

    if (status.isIdle) {
      return _IdleView(
        status: status,
        isUpgrading: _isUpgrading,
        onUpgrade: _upgrade,
      );
    }

    return _ResultView(status: status);
  }
}

// ── Loading 狀態 ───────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  final String? status;
  const _LoadingView({this.status});

  String get _label => switch (status) {
    'pending'    => '準備中...',
    'queued'     => '等待分析佇列...',
    'processing' => 'AI 教練正在分析影片...',
    'idle'       => '等待 AI 教練分析...',
    _            => '連接中...',
  };

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 64, height: 64,
            child: CircularProgressIndicator(color: kPrimaryGreen, strokeWidth: 3),
          ),
          const SizedBox(height: kSpaceLG),
          Text(_label, style: TextStyle(fontSize: 16, color: context.textSecondary)),
          const SizedBox(height: kSpaceSM),
          Text('通常需要 10~30 秒', style: TextStyle(fontSize: 13, color: context.textHint)),
        ],
      ),
    );
  }
}

// ── Error 狀態 ────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(kSpaceLG),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 64, color: kBadColor),
            const SizedBox(height: kSpaceMD),
            Text(error, textAlign: TextAlign.center, style: TextStyle(color: context.textSecondary)),
            const SizedBox(height: kSpaceLG),
            FilledButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}

// ── Idle 狀態（ONNX 完成，等待 Gemini）────────────────────────

class _IdleView extends StatelessWidget {
  final AnalysisStatus status;
  final bool isUpgrading;
  final VoidCallback onUpgrade;

  const _IdleView({
    required this.status,
    required this.isUpgrading,
    required this.onUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(kSpaceMD),
      children: [
        // ── 狀態橫幅 ────────────────────────────────────────────
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kPrimaryGreen.withAlpha(20),
            borderRadius: BorderRadius.circular(kRadiusMD),
            border: Border.all(color: kPrimaryGreen.withAlpha(80)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: kPrimaryGreen, size: 20),
              const SizedBox(width: kSpaceSM),
              const Expanded(
                child: Text(
                  '已完成錯誤姿勢分析',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kPrimaryGreen,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: kSpaceMD),

        const SizedBox(height: kSpaceLG),
        // ── 升級按鈕 ────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: isUpgrading ? null : onUpgrade,
            icon: isUpgrading
                ? const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.smart_toy_outlined),
            label: Text(isUpgrading ? '送出中...' : '開始 AI 教練分析'),
            style: FilledButton.styleFrom(
              backgroundColor: kPrimaryDark,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: kSpaceSM),
        Text(
          '* AI 教練將依據姿勢分析結果，提供詳細教練評語與訓練建議',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11, color: context.textHint),
        ),
        const SizedBox(height: kSpaceLG),
      ],
    );
  }
}

// ── Result 主畫面 ─────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final AnalysisStatus status;
  const _ResultView({required this.status});

  @override
  Widget build(BuildContext context) {
    final result = status.result!;
    return ListView(
      padding: const EdgeInsets.all(kSpaceMD),
      children: [
        _SummaryCard(result: result),
        if (result.impactQuality != null) ...[
          const SizedBox(height: kSpaceMD),
          _ImpactQualityCard(iq: result.impactQuality!),
        ],
        const SizedBox(height: kSpaceMD),
        _FeedbackCard(feedbacks: result.coachFeedback),
        const SizedBox(height: kSpaceMD),
        _PracticeCard(suggestions: result.practiceSuggestions),
        const SizedBox(height: kSpaceMD),
        _NextGoalCard(goal: result.nextTrainingGoal),
        const SizedBox(height: kSpaceLG),
      ],
    );
  }
}

// ── 摘要卡片 ─────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final CoachResult result;
  const _SummaryCard({required this.result});

  Color _severityColor(String severity) => switch (severity) {
    'high'   => kBadColor,
    'medium' => kCrispColor,
    _        => kGoodColor,
  };

  String _severityLabel(String severity) => switch (severity) {
    'high'   => '嚴重',
    'medium' => '中等',
    _        => '輕微',
  };

  @override
  Widget build(BuildContext context) {
    final err      = result.primaryError;
    final sevColor = _severityColor(err.severity);
    // primary_error 為 null（完美）時，zhName 為空 → fallback 到「完美姿勢」
    final displayName = err.zhName.isNotEmpty
        ? err.zhName
        : SwingPosture.zhName(err.errorType); // '' → '完美姿勢'

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sevColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(kRadiusSM),
                    border: Border.all(color: sevColor.withAlpha(80)),
                  ),
                  child: Text(
                    displayName,
                    style: TextStyle(color: sevColor, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(width: kSpaceSM),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: sevColor,
                  borderRadius: BorderRadius.circular(kRadiusSM),
                ),
                child: Text(
                  _severityLabel(err.severity),
                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: kSpaceMD),
          Text(result.summary, style: TextStyle(fontSize: 16, height: 1.5, color: context.textPrimary)),
          if (err.evidence.isNotEmpty) ...[
            const SizedBox(height: kSpaceMD),
            Text('依據', style: TextStyle(fontSize: 12, color: context.textHint, fontWeight: FontWeight.bold)),
            const SizedBox(height: kSpaceXS),
            ...err.evidence.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• ', style: TextStyle(color: context.textSecondary)),
                  Expanded(child: Text(e, style: TextStyle(fontSize: 13, color: context.textSecondary))),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }
}

// ── 擊球品質（音訊甜蜜點）卡片 ────────────────────────────────

class _ImpactQualityCard extends StatelessWidget {
  final ImpactQuality iq;
  const _ImpactQualityCard({required this.iq});

  Color get _levelColor => switch (iq.qualityLevel) {
    'premium_sweet_spot' => const Color(0xFF7C3AED),
    'sweet_spot'         => kGoodColor,
    'near_sweet_spot'    => kCrispColor,
    'fair'               => const Color(0xFFEAB308),
    _                    => kBadColor,
  };

  String get _levelLabel => switch (iq.qualityLevel) {
    'premium_sweet_spot' => '高品質甜蜜點',
    'sweet_spot'         => '甜蜜點',
    'near_sweet_spot'    => '接近甜蜜點',
    'fair'               => '普通',
    _                    => '擊球偏虛',
  };

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 標題列
          Row(
            children: [
              Icon(Icons.graphic_eq_rounded, color: _levelColor, size: 20),
              const SizedBox(width: 8),
              Text('擊球品質（音訊）',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.textPrimary)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _levelColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _levelColor.withValues(alpha: 0.55)),
                ),
                child: Text(
                  _levelLabel,
                  style: TextStyle(color: _levelColor, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 進度條 + 分數
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    for (int i = 0; i < iq.totalFeatures; i++) ...[
                      Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          height: 8,
                          decoration: BoxDecoration(
                            color: i < iq.passCount ? _levelColor : context.bgInset,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      if (i < iq.totalFeatures - 1) const SizedBox(width: 5),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${iq.passCount}/${iq.totalFeatures}',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _levelColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${iq.passCount} / ${iq.totalFeatures} 項特徵符合甜蜜點範圍',
            style: TextStyle(color: context.textSecondary, fontSize: 11),
          ),
          // AI 音頻反饋
          if (iq.audioFeedback.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: _levelColor.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border(left: BorderSide(color: _levelColor, width: 3)),
              ),
              child: Text(
                iq.audioFeedback,
                style: TextStyle(color: context.textPrimary, fontSize: 13, height: 1.55),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── 教練評語卡片 ──────────────────────────────────────────────

class _FeedbackCard extends StatelessWidget {
  final List<String> feedbacks;
  const _FeedbackCard({required this.feedbacks});

  @override
  Widget build(BuildContext context) {
    if (feedbacks.isEmpty) return const SizedBox.shrink();
    return _Card(
      title: '教練評語',
      icon: Icons.chat_bubble_outline,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: feedbacks.map((f) => Padding(
          padding: const EdgeInsets.only(bottom: kSpaceSM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.arrow_right, size: 20, color: kPrimaryGreen),
              const SizedBox(width: kSpaceXS),
              Expanded(child: Text(f, style: TextStyle(fontSize: 14, height: 1.5, color: context.textPrimary))),
            ],
          ),
        )).toList(),
      ),
    );
  }
}

// ── 訓練建議卡片 ──────────────────────────────────────────────

class _PracticeCard extends StatelessWidget {
  final List<PracticeSuggestion> suggestions;
  const _PracticeCard({required this.suggestions});

  @override
  Widget build(BuildContext context) {
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return _Card(
      title: '訓練建議',
      icon: Icons.fitness_center,
      child: Column(
        children: suggestions.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (i > 0) const Divider(height: kSpaceLG),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: CircleAvatar(
                      radius: 12,
                      backgroundColor: kPrimaryGreen,
                      child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                    ),
                  ),
                  const SizedBox(width: kSpaceSM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.drill, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        if (s.reps.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(s.reps, style: TextStyle(fontSize: 12, color: context.textSecondary)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: kSpaceSM),
              Text(s.instruction, style: TextStyle(fontSize: 13, color: context.textSecondary, height: 1.5)),
            ],
          );
        }).toList(),
      ),
    );
  }
}

// ── 下次目標卡片 ──────────────────────────────────────────────

class _NextGoalCard extends StatelessWidget {
  final String goal;
  const _NextGoalCard({required this.goal});

  @override
  Widget build(BuildContext context) {
    if (goal.isEmpty) return const SizedBox.shrink();
    return _Card(
      child: Row(
        children: [
          const Icon(Icons.flag, color: kPrimaryGreen, size: 28),
          const SizedBox(width: kSpaceMD),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('下次練習目標', style: TextStyle(fontSize: 12, color: context.textHint, fontWeight: FontWeight.bold)),
                const SizedBox(height: kSpaceXS),
                Text(goal, style: TextStyle(fontSize: 14, height: 1.5, color: context.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── 通用卡片容器 ──────────────────────────────────────────────

class _Card extends StatelessWidget {
  final String? title;
  final IconData? icon;
  final Widget child;

  const _Card({this.title, this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(kSpaceMD),
      decoration: BoxDecoration(
        color: context.bgCard,
        borderRadius: BorderRadius.circular(kRadiusMD),
        boxShadow: context.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: kPrimaryGreen),
                  const SizedBox(width: kSpaceXS),
                ],
                Text(title!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary)),
              ],
            ),
            const SizedBox(height: kSpaceMD),
          ],
          child,
        ],
      ),
    );
  }
}

// ── 重新分析過渡頁 ────────────────────────────────────────────

/// 顯示「提交中...」，完成後自動替換為 AiCoachPage
class _ReanalyzeLoader extends StatefulWidget {
  final String videoId;
  final String clipPath;
  final String? csvPath;
  const _ReanalyzeLoader({
    required this.videoId,
    required this.clipPath,
    this.csvPath,
  });
  @override
  State<_ReanalyzeLoader> createState() => _ReanalyzeLoaderState();
}

class _ReanalyzeLoaderState extends State<_ReanalyzeLoader> {
  @override
  void initState() {
    super.initState();
    _submit();
  }

  Future<void> _submit() async {
    try {
      // 直接提交並取得 analysisId，再用 pushReplacement 取代自己
      // 不呼叫 submitAndPush（它用 push，會讓自己誤 pop 掉新頁面）
      final analysisId = await AnalysisService.instance.submitForAnalysis(
        videoId:  widget.videoId,
        clipPath: widget.clipPath,
        csvPath:  widget.csvPath,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => AiCoachPage(
            analysisId: analysisId,
            clipPath:   widget.clipPath,
            videoId:    widget.videoId,
            csvPath:    widget.csvPath,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[ReanalyzeLoader] 重新分析失敗: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('重新分析失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgPage,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: kPrimaryGreen, strokeWidth: 3),
            ),
            const SizedBox(height: 16),
            Text('提交重新分析中...', style: TextStyle(color: context.textSecondary, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
