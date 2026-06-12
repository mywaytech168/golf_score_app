import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';
import 'package:video_player/video_player.dart';

import '../services/swing_impact_detector.dart';
import '../theme/app_theme.dart';

/// 剪輯邊界配色（與長影片播放頁一致）：綠=開始、紅=結束、橙=擊球。
const Color kClipStartColor = Color(0xFF22C55E);
const Color kClipEndColor = Color(0xFFEF4444);
const Color kClipImpactColor = Color(0xFFFF8F00);

/// 時間軸配色小圖例：綠=開始、紅=結束、橙=擊球。
/// 長影片播放頁與切片前確認 sheet 共用，讓使用者一眼看懂標記顏色。
class ClipBoundaryLegend extends StatelessWidget {
  const ClipBoundaryLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _item(kClipStartColor, l10n.clipLegendStart),
        const SizedBox(width: 14),
        _item(kClipImpactColor, l10n.playerPhaseImpact),
        const SizedBox(width: 14),
        _item(kClipEndColor, l10n.clipLegendEnd),
      ],
    );
  }

  Widget _item(Color c, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF9E9E9E)),
          ),
        ],
      );
}

/// 使用者在切片前確認的結果。
class ClipSelection {
  /// 勾選保留的自動候選（秒，相對原始影片）。
  final List<({double sec, bool fromAudio})> candidates;

  /// 手動新增的自由切片區段（秒，相對原始影片）。
  final List<({double startSec, double endSec})> manualRanges;

  const ClipSelection({required this.candidates, required this.manualRanges});

  bool get isEmpty => candidates.isEmpty && manualRanges.isEmpty;
}

/// 切片候選逐段預覽 sheet：
/// - 候選列表逐段播放確認（點列表 seek 到擊球前 2 秒自動播放）
/// - 勾選保留 / 取消誤判候選
/// - 自由切片：以播放位置設定起點/終點，手動加入任意區段
///
/// 回傳 null = 使用者取消整個偵測流程。
Future<ClipSelection?> showClipCandidatesSheet(
  BuildContext context, {
  required String videoPath,
  required double durationSeconds,
  required List<({double sec, bool fromAudio})> candidates,
}) {
  return showModalBottomSheet<ClipSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ClipCandidatesSheet(
      videoPath: videoPath,
      durationSeconds: durationSeconds,
      candidates: candidates,
    ),
  );
}

class _ClipCandidatesSheet extends StatefulWidget {
  final String videoPath;
  final double durationSeconds;
  final List<({double sec, bool fromAudio})> candidates;

  const _ClipCandidatesSheet({
    required this.videoPath,
    required this.durationSeconds,
    required this.candidates,
  });

  @override
  State<_ClipCandidatesSheet> createState() => _ClipCandidatesSheetState();
}

class _ClipCandidatesSheetState extends State<_ClipCandidatesSheet> {
  VideoPlayerController? _controller;
  late final List<bool> _kept;
  final List<({double startSec, double endSec})> _manualRanges = [];
  int? _previewingIndex;
  double? _manualStartSec;
  Timer? _stopTimer;

  @override
  void initState() {
    super.initState();
    _kept = List.filled(widget.candidates.length, true);
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    final c = VideoPlayerController.file(File(widget.videoPath));
    try {
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _controller = c);
      if (widget.candidates.isNotEmpty) _previewCandidate(0);
    } catch (e) {
      debugPrint('[ClipCandidates] 播放器初始化失敗: $e');
      await c.dispose();
    }
  }

  @override
  void dispose() {
    _stopTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  /// 跳到候選擊球前 2 秒並播放 4 秒（涵蓋上桿→送桿）
  void _previewCandidate(int index) {
    final c = _controller;
    if (c == null) return;
    final sec = widget.candidates[index].sec;
    final from = (sec - 2.0).clamp(0.0, widget.durationSeconds);
    setState(() => _previewingIndex = index);
    _playSegment(from, from + 4.0);
  }

  void _previewManualRange(({double startSec, double endSec}) r) {
    setState(() => _previewingIndex = null);
    _playSegment(r.startSec, r.endSec);
  }

  void _playSegment(double fromSec, double toSec) {
    final c = _controller;
    if (c == null) return;
    _stopTimer?.cancel();
    c.seekTo(Duration(milliseconds: (fromSec * 1000).round()));
    c.play();
    final ms = ((toSec - fromSec) * 1000).round().clamp(500, 600000);
    _stopTimer = Timer(Duration(milliseconds: ms), () {
      if (mounted) _controller?.pause();
    });
  }

  double get _playheadSec {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return 0.0;
    return c.value.position.inMilliseconds / 1000.0;
  }

  void _setManualStart() {
    _stopTimer?.cancel();
    setState(() => _manualStartSec = _playheadSec);
  }

  void _addManualRange() {
    final start = _manualStartSec;
    if (start == null) return;
    final end = _playheadSec;
    if (end - start < 0.5) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l10n.clipCandRangeTooShort),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() {
      _manualRanges.add((startSec: start, endSec: end));
      _manualStartSec = null;
    });
  }

  int get _selectedCount =>
      _kept.where((k) => k).length + _manualRanges.length;

  String _fmt(double sec) {
    final m = sec ~/ 60;
    final s = sec - m * 60;
    return '$m:${s.toStringAsFixed(1).padLeft(4, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = _controller;
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: context.bgPage,
          borderRadius:
              const BorderRadius.vertical(top: Radius.circular(kRadiusLG)),
        ),
        child: Column(
          children: [
            const SizedBox(height: kSpaceSM),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: context.textHint,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kSpaceMD, kSpaceSM, kSpaceMD, kSpaceSM),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.clipCandTitle(widget.candidates.length),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: context.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    l10n.clipCandTapToPreview,
                    style:
                        TextStyle(fontSize: 12, color: context.textSecondary),
                  ),
                ],
              ),
            ),
            // ── 影片預覽 ────────────────────────────────────────────
            Container(
              height: 220,
              width: double.infinity,
              color: Colors.black,
              child: (c != null && c.value.isInitialized)
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
                        Positioned(
                          left: 0, right: 0, bottom: 0,
                          child: _buildTimeline(c),
                        ),
                      ],
                    )
                  : const Center(
                      child: CircularProgressIndicator(color: kBrandPrimary)),
            ),
            // ── 剪輯邊界配色圖例 ─────────────────────────────────────
            const Padding(
              padding: EdgeInsets.symmetric(vertical: kSpaceXS),
              child: ClipBoundaryLegend(),
            ),
            // ── 自由切片工具列 ───────────────────────────────────────
            _buildManualToolbar(),
            // ── 候選 + 手動區段列表 ──────────────────────────────────
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: kSpaceMD),
                children: [
                  for (int i = 0; i < widget.candidates.length; i++)
                    _buildCandidateTile(i),
                  for (int i = 0; i < _manualRanges.length; i++)
                    _buildManualTile(i),
                  const SizedBox(height: kSpaceLG),
                ],
              ),
            ),
            // ── 底部按鈕 ────────────────────────────────────────────
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    kSpaceMD, kSpaceSM, kSpaceMD, kSpaceMD),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text(l10n.commonCancel),
                      ),
                    ),
                    const SizedBox(width: kSpaceMD),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        style:
                            FilledButton.styleFrom(backgroundColor: kBrandPrimary),
                        onPressed: _selectedCount == 0
                            ? null
                            : () {
                                Navigator.pop(
                                  context,
                                  ClipSelection(
                                    candidates: [
                                      for (int i = 0;
                                          i < widget.candidates.length;
                                          i++)
                                        if (_kept[i]) widget.candidates[i],
                                    ],
                                    manualRanges: List.of(_manualRanges),
                                  ),
                                );
                              },
                        child: Text(l10n.clipCandConfirmClip(_selectedCount)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline(VideoPlayerController c) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (_, v, __) {
        final dur = widget.durationSeconds;
        final pos = v.position.inMilliseconds / 1000.0;
        return Container(
          color: Colors.black45,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  v.isPlaying ? Icons.pause : Icons.play_arrow,
                  color: Colors.white, size: 20,
                ),
                onPressed: () {
                  _stopTimer?.cancel();
                  v.isPlaying ? c.pause() : c.play();
                },
              ),
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 候選位置 tick
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _CandidateTickPainter(
                          ticks: [
                            for (final cand in widget.candidates)
                              cand.sec / dur,
                          ],
                          ranges: [
                            // 自動候選：以擊球點推得 5 秒剪輯起迄
                            for (final cand in widget.candidates)
                              _normRange(
                                SwingImpactDetector.calculateClipBoundaries(
                                  hitSec: cand.sec, totalDurationSec: dur),
                                dur,
                              ),
                            // 手動自由切片區段
                            for (final r in _manualRanges)
                              (start: r.startSec / dur, end: r.endSec / dur),
                          ],
                        ),
                      ),
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6),
                      ),
                      child: Slider(
                        value: pos.clamp(0.0, dur),
                        max: dur,
                        activeColor: kPrimaryLight,
                        inactiveColor: Colors.white30,
                        onChanged: (s) {
                          _stopTimer?.cancel();
                          c.seekTo(Duration(milliseconds: (s * 1000).round()));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _fmt(pos),
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildManualToolbar() {
    final hasStart = _manualStartSec != null;
    final l10n = AppLocalizations.of(context);
    return Container(
      color: context.bgInset,
      padding:
          const EdgeInsets.symmetric(horizontal: kSpaceMD, vertical: kSpaceXS),
      child: Row(
        children: [
          Icon(Icons.content_cut, size: 16, color: context.textSecondary),
          const SizedBox(width: kSpaceSM),
          Expanded(
            child: Text(
              hasStart
                  ? l10n.clipCandManualHint(_fmt(_manualStartSec!))
                  : l10n.clipCandManualPrompt,
              style: TextStyle(fontSize: 12, color: context.textSecondary),
            ),
          ),
          if (!hasStart)
            TextButton(
              onPressed: _controller == null ? null : _setManualStart,
              child: Text(l10n.clipCandSetStart),
            )
          else ...[
            TextButton(
              onPressed: () => setState(() => _manualStartSec = null),
              child: Text(l10n.clipCandReset),
            ),
            FilledButton.tonal(
              onPressed: _addManualRange,
              child: Text(l10n.clipCandAddRange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCandidateTile(int i) {
    final cand = widget.candidates[i];
    final previewing = _previewingIndex == i;
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: kSpaceSM),
      color: previewing ? context.mintTint : context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSM),
        side: BorderSide(
            color: previewing ? kBrandPrimary : context.borderColor),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _previewCandidate(i),
        leading: Icon(
          cand.fromAudio ? Icons.graphic_eq : Icons.directions_run,
          color: _kept[i] ? kBrandPrimary : context.textHint,
        ),
        title: Text(
          l10n.clipCandCandidateLabel(i + 1, _fmt(cand.sec)),
          style: TextStyle(
            color: _kept[i] ? context.textPrimary : context.textHint,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          cand.fromAudio ? l10n.clipCandFromAudio : l10n.clipCandFromMotion,
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        trailing: Checkbox(
          value: _kept[i],
          activeColor: kBrandPrimary,
          onChanged: (v) => setState(() => _kept[i] = v ?? true),
        ),
      ),
    );
  }

  Widget _buildManualTile(int i) {
    final r = _manualRanges[i];
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: kSpaceSM),
      color: context.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kRadiusSM),
        side: BorderSide(color: kSpeedColor.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        dense: true,
        onTap: () => _previewManualRange(r),
        leading: const Icon(Icons.content_cut, color: kSpeedColor),
        title: Text(
          l10n.clipCandManualRangeLabel(_fmt(r.startSec), _fmt(r.endSec)),
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          l10n.clipCandRangeDuration((r.endSec - r.startSec).toStringAsFixed(1)),
          style: TextStyle(fontSize: 12, color: context.textSecondary),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: context.textHint),
          onPressed: () => setState(() => _manualRanges.removeAt(i)),
        ),
      ),
    );
  }
}

/// 將 (startSec, endSec) 換算成 0~1 normalized 區段。
({double start, double end}) _normRange((double, double) b, double dur) =>
    (start: b.$1 / dur, end: b.$2 / dur);

/// 時間軸上的候選位置刻度（青=擊球點）＋剪輯起迄邊界（綠=開始、紅=結束）。
class _CandidateTickPainter extends CustomPainter {
  final List<double> ticks; // 0~1 normalized：擊球/候選中心
  final List<({double start, double end})> ranges; // 0~1 normalized：剪輯起迄

  const _CandidateTickPainter({required this.ticks, this.ranges = const []});

  @override
  void paint(Canvas canvas, Size size) {
    // ── 剪輯起迄邊界（畫在中心 tick 下層）──
    for (final r in ranges) {
      _boundary(canvas, size, r.start, kClipStartColor);
      _boundary(canvas, size, r.end, kClipEndColor);
    }

    // ── 候選/擊球中心 tick ──
    final paint = Paint()
      ..color = kCrispColor
      ..strokeWidth = 2;
    for (final t in ticks) {
      final x = t.clamp(0.0, 1.0) * size.width;
      canvas.drawLine(
        Offset(x, size.height * 0.30),
        Offset(x, size.height * 0.70),
        paint,
      );
    }
  }

  void _boundary(Canvas canvas, Size size, double t, Color color) {
    final x = t.clamp(0.0, 1.0) * size.width;
    canvas.drawLine(
      Offset(x, size.height * 0.12),
      Offset(x, size.height * 0.88),
      Paint()
        ..color = color.withValues(alpha: 0.70)
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(_CandidateTickPainter old) =>
      old.ticks != ticks || old.ranges != ranges;
}
