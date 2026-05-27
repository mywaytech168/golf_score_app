import 'dart:async';

import 'package:flutter/material.dart';

import '../models/swing_posture.dart';
import '../services/analysis_service.dart';
import '../theme/app_theme.dart';

/// AI Coach 分析頁面
/// 接收 analysisId（已完成步驟 1~3），輪詢結果並顯示教練評語
class AiCoachPage extends StatefulWidget {
  final String analysisId;
  final String? clipPath;
  /// 供「重新分析」按鈕使用
  final String? videoId;
  final String? csvPath;
  /// 分析完成後回呼，傳入 errorType（'' = 完美，其餘為錯誤類型）
  final void Function(String errorType)? onAnalysisComplete;

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
    bool forceReanalyze = false,
    void Function(String errorType)? onAnalysisComplete,
  }) async {
    // ── 快取判斷：若已有分析且不強制重新，直接導向 ──────────
    if (!forceReanalyze) {
      try {
        final existing =
            await AnalysisService.instance.getLatestAnalysisForVideo(videoId);
        if (existing != null && !existing.isFailed) {
          debugPrint('[AiCoach] 已有分析 ${existing.analysisId} '
              '(${existing.status})，直接開啟');
          if (context.mounted) {
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AiCoachPage(
                analysisId:          existing.analysisId,
                clipPath:            clipPath,
                videoId:             videoId,
                csvPath:             csvPath,
                onAnalysisComplete:  onAnalysisComplete,
              ),
            ));
          }
          return;
        }
      } catch (e) {
        debugPrint('[AiCoach] 快取查詢失敗（略過）: $e');
      }
    }

    // 使用者只需上傳 clip + CSV；ONNX 推論在後端 Worker 自動執行
    final analysisId = await AnalysisService.instance.submitForAnalysis(
      videoId:  videoId,
      clipPath: clipPath,
      csvPath:  csvPath,  // 有值時一併上傳，Worker 自行推論並存入 DB
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

  Future<void> _reanalyze() async {
    _timer?.cancel();
    final vid  = widget.videoId;
    final clip = widget.clipPath;
    if (vid == null || clip == null) return;
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
            final rawType = status.result?.primaryError.errorType ?? '';
            // 正規化：只接受已知 label；Gemini 有時回中文或混合字串，一律 fallback 到 ''
            final errorType = SwingPosture.allLabels.contains(rawType) ? rawType : '';
            if (rawType != errorType) {
              debugPrint('[AiCoach] errorType 正規化: "$rawType" → "$errorType"');
            }
            widget.onAnalysisComplete?.call(errorType);
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
      backgroundColor: kBgPage,
      appBar: AppBar(
        title: const Text('AI 教練分析'),
        backgroundColor: kPrimaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (widget.videoId != null && widget.clipPath != null)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: '重新分析',
              onPressed: _reanalyze,
            ),
        ],
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
  final AnalysisStatus status;
  const _ResultView({required this.status});

  @override
  Widget build(BuildContext context) {
    final result = status.result!;
    return ListView(
      padding: const EdgeInsets.all(kSpaceMD),
      children: [
        _SummaryCard(result: result),
        const SizedBox(height: kSpaceMD),
        _FeedbackCard(feedbacks: result.coachFeedback),
        if (status.onnxResult != null) ...[
          const SizedBox(height: kSpaceMD),
          _OnnxScoreCard(onnx: status.onnxResult!),
        ],
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
                          Text(s.reps, style: const TextStyle(fontSize: 12, color: kTextSecondary)),
                        ],
                      ],
                    ),
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

// ── ONNX 分數卡片 ─────────────────────────────────────────────

class _OnnxScoreCard extends StatelessWidget {
  final OnnxResult onnx;
  const _OnnxScoreCard({required this.onnx});

  Color _barColor(String label) {
    if (onnx.officialErrors.contains(label)) return kBadColor;
    if (onnx.suspectErrors.contains(label))  return kCrispColor;
    return kTextHint;
  }

  String _bandLabel(String band) => switch (band) {
    'high_confidence'      => '高信心',
    'acceptable_review'    => '可接受',
    'suspect_not_official' => '可疑',
    _                      => '忽略',
  };

  @override
  Widget build(BuildContext context) {
    // 依照 SwingPosture.errorLabels 固定順序顯示（完美不顯示，只顯示 5 種錯誤）
    final orderedLabels = SwingPosture.errorLabels;

    return _Card(
      title: '模型推論分數',
      icon: Icons.bar_chart_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 完美揮桿提示橫幅 ────────────────────────────────────
          if (onnx.isPerfect) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: kSpaceMD),
              decoration: BoxDecoration(
                color: kGoodColor.withAlpha(20),
                borderRadius: BorderRadius.circular(kRadiusSM),
                border: Border.all(color: kGoodColor.withAlpha(80)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.star_rounded, color: kGoodColor, size: 18),
                  const SizedBox(width: kSpaceXS),
                  const Text(
                    '完美揮桿 — 所有錯誤分數均低於門檻',
                    style: TextStyle(fontSize: 13, color: kGoodColor, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ],
          ...orderedLabels.map((label) {
            final score    = onnx.scores[label] ?? 0.0;
            final band     = onnx.bands[label]  ?? 'low_ignore';
            final barColor = _barColor(label);
            final isOfficial = onnx.officialErrors.contains(label);
            final isSuspect  = onnx.suspectErrors.contains(label);

            return Padding(
              padding: const EdgeInsets.only(bottom: kSpaceMD),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          SwingPosture.zhName(label),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: (isOfficial || isSuspect)
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: (isOfficial || isSuspect) ? barColor : kTextSecondary,
                          ),
                        ),
                      ),
                      Text(
                        '${(score * 100).toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: barColor,
                        ),
                      ),
                      const SizedBox(width: kSpaceXS),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: barColor.withAlpha(isOfficial ? 30 : 15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _bandLabel(band),
                          style: TextStyle(fontSize: 10, color: barColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: score.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: barColor.withAlpha(20),
                      valueColor: AlwaysStoppedAnimation<Color>(barColor),
                    ),
                  ),
                ],
              ),
            );
          }),
          // 門檻說明
          const Divider(height: kSpaceMD),
          DefaultTextStyle(
            style: const TextStyle(fontSize: 10, color: kTextHint),
            child: Row(
              children: [
                _dot(kBadColor),    const Text(' 確認錯誤 ≥75%   '),
                _dot(kCrispColor),  const Text(' 可疑 60–75%   '),
                _dot(kTextHint),    const Text(' 忽略 <60%'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 8, height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle),
  );
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
      backgroundColor: kBgPage,
      body: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(color: kPrimaryGreen, strokeWidth: 3),
            ),
            SizedBox(height: 16),
            Text('提交重新分析中...', style: TextStyle(color: kTextSecondary, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}
