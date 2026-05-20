import 'dart:async';

import 'package:flutter/material.dart';

import '../services/analysis_service.dart';
import '../theme/app_theme.dart';

/// AI Coach 分析頁面
/// 接收 analysisId（已完成步驟 1~3），輪詢結果並顯示教練評語
class AiCoachPage extends StatefulWidget {
  final String analysisId;
  final String? clipPath; // 可選，用於頁面頂部影片回放（如有 video_player）

  const AiCoachPage({
    super.key,
    required this.analysisId,
    this.clipPath,
  });

  /// 從 clip 路徑一次完成提交並導向本頁
  static Future<void> submitAndPush({
    required BuildContext context,
    required String videoId,
    required String clipPath,
    String? errorTypeHint,
  }) async {
    final analysisId = await AnalysisService.instance.submitForAnalysis(
      videoId:       videoId,
      clipPath:      clipPath,
      errorTypeHint: errorTypeHint,
    );
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => AiCoachPage(analysisId: analysisId, clipPath: clipPath),
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

  Future<void> _poll() async {
    try {
      final status = await AnalysisService.instance.getStatus(widget.analysisId);
      if (mounted) {
        setState(() {
          _status = status;
          _error  = null;
        });
        if (status.isDone) _timer?.cancel();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgPage,
      appBar: AppBar(
        title: const Text('AI 教練分析'),
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
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

    return _ResultView(result: status.result!);
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
          Text(_label, style: const TextStyle(fontSize: 16, color: kTextSecondary)),
          const SizedBox(height: kSpaceSM),
          const Text('通常需要 10~30 秒', style: TextStyle(fontSize: 13, color: kTextHint)),
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
            Text(error, textAlign: TextAlign.center, style: const TextStyle(color: kTextSecondary)),
            const SizedBox(height: kSpaceLG),
            FilledButton(onPressed: onRetry, child: const Text('重試')),
          ],
        ),
      ),
    );
  }
}

// ── Result 主畫面 ─────────────────────────────────────────────

class _ResultView extends StatelessWidget {
  final CoachResult result;
  const _ResultView({required this.result});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(kSpaceMD),
      children: [
        _SummaryCard(result: result),
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

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: sevColor.withAlpha(25),
                  borderRadius: BorderRadius.circular(kRadiusSM),
                  border: Border.all(color: sevColor.withAlpha(80)),
                ),
                child: Text(
                  err.zhName,
                  style: TextStyle(color: sevColor, fontWeight: FontWeight.bold, fontSize: 13),
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
          Text(result.summary, style: const TextStyle(fontSize: 16, height: 1.5, color: kTextPrimary)),
          if (err.evidence.isNotEmpty) ...[
            const SizedBox(height: kSpaceMD),
            const Text('依據', style: TextStyle(fontSize: 12, color: kTextHint, fontWeight: FontWeight.bold)),
            const SizedBox(height: kSpaceXS),
            ...err.evidence.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• ', style: TextStyle(color: kTextSecondary)),
                  Expanded(child: Text(e, style: const TextStyle(fontSize: 13, color: kTextSecondary))),
                ],
              ),
            )),
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
              Expanded(child: Text(f, style: const TextStyle(fontSize: 14, height: 1.5, color: kTextPrimary))),
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
                children: [
                  CircleAvatar(
                    radius: 12,
                    backgroundColor: kPrimaryGreen,
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                  const SizedBox(width: kSpaceSM),
                  Expanded(
                    child: Text(s.drill, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: kBgPage,
                      borderRadius: BorderRadius.circular(kRadiusSM),
                    ),
                    child: Text(s.reps, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
                  ),
                ],
              ),
              const SizedBox(height: kSpaceSM),
              Text(s.instruction, style: const TextStyle(fontSize: 13, color: kTextSecondary, height: 1.5)),
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
                const Text('下次練習目標', style: TextStyle(fontSize: 12, color: kTextHint, fontWeight: FontWeight.bold)),
                const SizedBox(height: kSpaceXS),
                Text(goal, style: const TextStyle(fontSize: 14, height: 1.5, color: kTextPrimary)),
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
        color: kBgCard,
        borderRadius: BorderRadius.circular(kRadiusMD),
        boxShadow: kCardShadow,
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
                Text(title!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kTextPrimary)),
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
