import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import 'ball_tuning_page.dart';
import '../models/swing_posture.dart';
import '../recording/pose_csv_loader.dart';
import '../recording/skeleton_painter.dart';
import '../recording/trajectory_painter.dart';
import '../services/analysis_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/chart_data_service.dart';
import '../services/skeleton_csv_locator.dart';
import '../theme/app_theme.dart';
import 'ai_coach_page.dart';

/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.startPosition,
    this.entry,
  });

  final String videoPath;
  final String? avatarPath;
  final Duration? startPosition;
  final RecordingHistoryEntry? entry;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _initialized = false;

  /// 是否為長影片（原始錄製 > 5 秒），長影片無骨架/分析 Tab 及 AI，但可顯示圖表
  bool get _isLongVideo =>
      widget.entry?.videoType == VideoType.original &&
      (widget.entry?.durationSeconds ?? 0) > 5;

  // Charts panel state
  bool _chartsExpanded = false;
  int _chartTabIndex = 0;  // 0=聲音峰值 1=手腕Y 2=速度 3=姿勢 4=音頻特徵
  ChartDataSet? _chartData;
  bool _chartsLoading = false;

  // AI analysis panel state
  bool _aiExpanded = false;
  AnalysisStatus? _aiStatus;
  bool _aiLoading = false;
  bool _aiSubmitting = false;

  // 揮桿 8 階段關鍵禎
  // key = phase key (e.g. 'address'), value = seconds in clip
  Map<String, double>? _phases;

  // 骨架疊圖（取代燒錄 skeleton.mp4）：CSV 為 clip 相對時間，offset=0 直接用 position 取樣
  PoseTrack? _skeletonTrack;
  bool _skeletonLoading = false;
  // ── 疊層開關（取代舊 Tab 切換）：骨架 / 軌跡各自獨立 checkbox ─────────────
  bool _showSkeleton   = false;
  bool _showTrajectory = false;
  bool _showImpactFx   = false;   // 擊球光圈 / Sweet Spot 徽章 / impact chip 金標
  late final bool _hasTrajectory;   // trajectory.json 是否存在
  bool get _hasImpactFx =>
      widget.entry?.hitSecond != null && widget.entry?.goodShot != null;

  TrajectoryTrack? _trajTrack;

  // 甜蜜點特效動畫（僅分析 Tab）
  late final AnimationController _impactAnim;
  bool _impactTriggered = false;
  static const _phaseOrder = [
    ('address',       '準備'),
    ('takeaway',      '起桿'),
    ('backswing',     '上桿'),
    ('top',           '頂點'),
    ('downswing',     '下桿'),
    ('impact',        '擊球'),
    ('followthrough', '送桿'),
    ('finish',        '收桿'),
  ];

  /// 骨架 CSV 是否存在（逐幀版或 live 版皆可；initState 檢查一次）
  late final bool _hasSkeletonCsv;

  static const _chartTabs = [
    (label: '聲音峰值', color: Color(0xFFE53935)),
    (label: '手腕 Y',   color: Color(0xFF1565C0)),
    (label: '速度',      color: Color(0xFF1AA87C)),
    (label: '姿勢',     color: Color(0xFF7C3AED)),
    (label: '音頻特徵', color: Color(0xFF7B1FA2)),
  ];

  String get _sessionDir => '${p.dirname(widget.videoPath)}${p.separator}';

  @override
  void initState() {
    super.initState();

    _hasSkeletonCsv = resolveSkeletonCsv(p.dirname(widget.videoPath)) != null;
    _hasTrajectory  = File('${_sessionDir}trajectory.json').existsSync();

    _impactAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // ── 單一影片 + checkbox 疊層（取代舊 原始/骨架/分析 Tab 切換）──────────
    // base 影片優先乾淨 clip.mp4（與 CSV/trajectory 時間軸對齊），
    // 否則 swing.mp4（原始/長影片），最後退回 widget.videoPath。
    final clipPath  = '${_sessionDir}clip.mp4';
    final swingPath = '${_sessionDir}swing.mp4';
    final basePath = File(clipPath).existsSync()
        ? clipPath
        : (File(swingPath).existsSync() ? swingPath : widget.videoPath);
    _initController(basePath, isOriginal: basePath != clipPath);

    // 預設：有資料的疊層直接開啟（對齊舊「分析 Tab」的開箱體驗）
    _showSkeleton   = _hasSkeletonCsv;
    _showTrajectory = _hasTrajectory;
    _showImpactFx   = _hasImpactFx;
    if (_showSkeleton) _ensureSkeletonTrack();
    if (_showTrajectory) _ensureTrajectoryTrack();

    // 讀取揮桿 8 階段時間點；並預載圖表資料（供波形使用）
    // localClip（切片）或 isAnalyzed（匯入後已完成分析）都載入
    final entry = widget.entry;
    if (entry != null &&
        (entry.videoType == VideoType.localClip || entry.isAnalyzed)) {
      _loadPhases();
      _loadCharts();
    }
  }

  Future<void> _loadPhases() async {
    final phasesFile = File(p.join(p.dirname(widget.videoPath), 'phases.json'));
    if (!phasesFile.existsSync()) return;
    try {
      final raw = jsonDecode(await phasesFile.readAsString());
      if (raw is Map) {
        if (mounted) {
          setState(() {
            _phases = raw.map((k, v) => MapEntry(k as String, (v as num).toDouble()));
          });
        }
      }
    } catch (e) {
      debugPrint('[VideoPlayer] phases.json 讀取失敗: $e');
    }
  }

  Future<void> _initController(String path, {bool isOriginal = false}) async {
    final file = File(path);
    if (!file.existsSync()) {
      _showSnack('找不到影片檔案');
      return;
    }

    final old = _controller;
    old?.removeListener(_onUpdate);

    final ctrl = VideoPlayerController.file(file);
    _controller = ctrl;
    if (mounted) setState(() => _initialized = false);

    try {
      await ctrl.initialize();
      ctrl.addListener(_onUpdate);
      ctrl.setLooping(true);

      if (isOriginal && widget.startPosition != null) {
        await ctrl.seekTo(widget.startPosition!);
      } else if (!isOriginal) {
        // localClip：Surface trim 後 clip 精確從 hitSec-2.5 開始，hitSecond≈2.5。
        // 若因 fallback（raw mux）導致 clip 較長，自動 seek 到 hitSecond-2.5。
        final hitSec = widget.entry?.hitSecond;
        if (hitSec != null && hitSec > 3.0) {
          // hitSecond > 3 表示 clip 有較多前置幀（fallback 路徑），需要 seek
          final seekMs = ((hitSec - 2.5).clamp(0.0, hitSec) * 1000).round();
          await ctrl.seekTo(Duration(milliseconds: seekMs));
        }
      }
      ctrl.play();

      if (mounted) setState(() => _initialized = true);
    } catch (e) {
      debugPrint('[VideoPlayer] 初始化失敗: $e');
      if (mounted) _showSnack('影片載入失敗');
    } finally {
      await old?.dispose();
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    _checkImpactTrigger();
    setState(() {});
  }

  void _checkImpactTrigger() {
    if (!_showImpactFx) return;
    final hitSec = widget.entry?.hitSecond;
    if (hitSec == null || widget.entry?.goodShot == null) return;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final posSec = ctrl.value.position.inMilliseconds / 1000.0;
    final inWindow = posSec >= hitSec && posSec < hitSec + 1.6;

    if (inWindow && !_impactTriggered) {
      _impactTriggered = true;
      _impactAnim.forward(from: 0);
    } else if (posSec < hitSec - 0.3 && _impactTriggered) {
      _impactTriggered = false;
      _impactAnim.reset();
    }
  }

  void _toggleCharts() {
    setState(() => _chartsExpanded = !_chartsExpanded);
    if (_chartsExpanded && _chartData == null && !_chartsLoading) {
      _loadCharts();
    }
  }

  void _toggleAi() {
    setState(() => _aiExpanded = !_aiExpanded);
    if (_aiExpanded && _aiStatus == null && !_aiLoading) {
      _loadAiStatus();
    }
  }

  Future<void> _loadAiStatus() async {
    if (widget.entry == null) return;
    setState(() => _aiLoading = true);
    try {
      final videoId = p.basename(p.dirname(widget.videoPath));
      final status = await AnalysisService.instance
          .getLatestAnalysisForVideo(videoId);
      if (mounted) setState(() => _aiStatus = status);
    } catch (_) {
      // 未登入或網路失敗 → 靜默，顯示「尚未分析」
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  Future<void> _openOrSubmitAi({bool forceReanalyze = false}) async {
    if (widget.entry == null) return;
    setState(() => _aiSubmitting = true);
    try {
      final sessionDir = p.dirname(widget.videoPath);
      final videoId    = p.basename(sessionDir);
      final csvPath    = p.join(sessionDir, 'pose_landmarks.csv');
      final hasCsv     = File(csvPath).existsSync();
      await AiCoachPage.submitAndPush(
        context:        context,
        videoId:        videoId,
        clipPath:       widget.videoPath,
        csvPath:        hasCsv ? csvPath : null,
        forceReanalyze: forceReanalyze,
      );
      // 回到此頁後刷新狀態
      if (mounted) {
        setState(() { _aiStatus = null; });
        _loadAiStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI 分析失敗: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _aiSubmitting = false);
    }
  }

  Future<void> _loadCharts() async {
    final entry = widget.entry;
    if (entry == null) return;
    setState(() => _chartsLoading = true);
    try {
      final data = await ChartDataService.loadFromEntry(entry);
      if (mounted) setState(() { _chartData = data; _chartsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chartsLoading = false);
    }
  }

  @override
  void dispose() {
    _impactAnim.dispose();
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    super.dispose();
  }

  void _showSnack(String text) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  // ── 疊層資料載入 ────────────────────────────────────────────

  Future<void> _ensureSkeletonTrack() async {
    if (_skeletonTrack != null || _skeletonLoading) return;
    // 逐幀 CSV 優先；剛錄完背景分析未完成時退回 live CSV 先顯示。
    // 載入一次即定：本頁生命週期內不偷換來源，避免使用者不知情下骨架變樣。
    final csvPath = resolveSkeletonCsv(p.dirname(widget.videoPath));
    if (csvPath == null) {
      _showSnack('骨架資料不存在');
      return;
    }
    setState(() => _skeletonLoading = true);
    try {
      final track = await PoseTrack.load(csvPath);
      if (mounted) setState(() => _skeletonTrack = track);
    } catch (e) {
      debugPrint('[VideoPlayer] 骨架 CSV 載入失敗: $e');
    } finally {
      if (mounted) setState(() => _skeletonLoading = false);
    }
  }

  Future<void> _ensureTrajectoryTrack() async {
    if (_trajTrack != null) return;
    final track = await TrajectoryTrack.load('${_sessionDir}trajectory.json');
    if (mounted && track != null) setState(() => _trajTrack = track);
  }

  // ── UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(child: _buildVideo()),
            if (_initialized) _buildOverlayToggles(),
            if (_initialized) _buildControls(),
            if (_initialized && _phases != null) _buildPhaseStrip(),
            _buildChartsPanel(),
            _buildAiPanel(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.entry?.displayTitle ?? '影片查看',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.avatarPath != null) ...[
            CircleAvatar(
              radius: 14,
              backgroundImage: FileImage(File(widget.avatarPath!)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  /// 疊層開關列：骨架 / 軌跡 checkbox + 軌跡調參入口（從頂列移下來）
  Widget _buildOverlayToggles() {
    Widget toggle({
      required String label,
      required IconData icon,
      required bool value,
      required ValueChanged<bool> onChanged,
    }) {
      return InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              width: 32, height: 32,
              child: Checkbox(
                value: value,
                onChanged: (v) => onChanged(v ?? false),
                activeColor: const Color(0xFF1AA87C),
                side: const BorderSide(color: Colors.white54),
              ),
            ),
            Icon(icon, color: value ? Colors.white : Colors.white54, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: value ? Colors.white : Colors.white54, fontSize: 13)),
          ]),
        ),
      );
    }

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          if (_hasSkeletonCsv)
            toggle(
              label: '骨架',
              icon: Icons.person,
              value: _showSkeleton,
              onChanged: (v) {
                setState(() => _showSkeleton = v);
                if (v) _ensureSkeletonTrack();
              },
            ),
          if (_hasTrajectory) ...[
            const SizedBox(width: 8),
            toggle(
              label: '軌跡',
              icon: Icons.sports_golf,
              value: _showTrajectory,
              onChanged: (v) {
                setState(() => _showTrajectory = v);
                if (v) _ensureTrajectoryTrack();
              },
            ),
          ],
          if (_hasImpactFx) ...[
            const SizedBox(width: 8),
            toggle(
              label: '特效',
              icon: Icons.auto_awesome,
              value: _showImpactFx,
              onChanged: (v) => setState(() => _showImpactFx = v),
            ),
          ],
          const Spacer(),
          // 球軌跡調參（排查用）：對本 clip 即時調參重跑
          TextButton.icon(
            onPressed: () {
              final clip = File('${_sessionDir}clip.mp4').existsSync()
                  ? '${_sessionDir}clip.mp4'
                  : widget.videoPath;
              Navigator.push(context, MaterialPageRoute(
                builder: (_) => BallTuningPage(
                  clipPath: clip,
                  hitSec: widget.entry?.hitSecond,
                ),
              ));
            },
            icon: const Icon(Icons.tune, color: Colors.white54, size: 16),
            label: const Text('軌跡調參',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _buildVideo() {
    final ctrl = _controller;
    if (ctrl == null || !_initialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.white54));
    }

    final entry = widget.entry;
    final showEffects = _showImpactFx && _hasImpactFx;

    return Center(
      child: AspectRatio(
        aspectRatio: 9 / 16,
        child: Stack(
          children: [
            VideoPlayer(ctrl),
            // 骨架疊圖：依播放位置即時取樣 CSV（offset=0，CSV 為 clip 相對時間）
            if (_showSkeleton && _skeletonTrack != null)
              Positioned.fill(
                child: Builder(builder: (_) {
                  final pose = _skeletonTrack!
                      .sampleAt(ctrl.value.position.inMilliseconds / 1000.0);
                  if (pose == null) return const SizedBox.shrink();
                  return CustomPaint(
                    painter: SkeletonPainter(
                      pose: pose,
                      // 線寬以影片像素為基準，對齊燒錄版視覺粗細
                      videoShortSide: ctrl.value.size.shortestSide,
                    ),
                  );
                }),
              ),
            // 球軌跡疊圖：只畫 pts ≤ 播放位置的軌跡
            if (_showTrajectory && _trajTrack != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: TrajectoryPainter(
                    track: _trajTrack!,
                    positionSec: ctrl.value.position.inMilliseconds / 1000.0,
                  ),
                ),
              ),
            if (_showSkeleton && _skeletonLoading)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(color: Colors.white54),
                ),
              ),
            if (showEffects) ...[
              // 擊球光圈
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _impactAnim,
                  builder: (_, __) => CustomPaint(
                    painter: _SweetSpotRingPainter(
                      progress: _impactAnim.value,
                      goodShot: entry!.goodShot,
                      passCount: entry.audioPassCount ?? 0,
                    ),
                  ),
                ),
              ),
              // Sweet Spot 徽章（右上角）
              Positioned(
                right: 10,
                top: 10,
                child: AnimatedBuilder(
                  animation: _impactAnim,
                  builder: (_, __) => _SweetSpotBadge(
                    progress: _impactAnim.value,
                    goodShot: entry!.goodShot,
                    passCount: entry.audioPassCount ?? 0,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildControls() {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return const SizedBox.shrink();

    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final durSec   = duration.inMilliseconds / 1000.0;
    final posSec   = position.inMilliseconds / 1000.0;
    final progress = durSec > 0 ? (posSec / durSec).clamp(0.0, 1.0) : 0.0;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 多模態時間軸（音訊 RMS + 速度曲線 + 階段 tick + impact 鑽石）
          SizedBox(
            height: 56,
            child: Stack(
              children: [
                // 層1：資料可視化背景
                Positioned.fill(
                  child: CustomPaint(
                    painter: _MultiModalTimelinePainter(
                      audioRms:      _chartData?.audioRms      ?? const [],
                      wristSpeed:    _chartData?.wristSpeed    ?? const [],
                      phases:        _phases                   ?? const {},
                      hitSecond:     widget.entry?.hitSecond,
                      currentSecond: posSec,
                      totalSeconds:  durSec,
                      goodShot:      widget.entry?.goodShot,
                    ),
                  ),
                ),
                // 層2：透明 track 的 Slider（保留 thumb 拖曳 seek）
                Positioned.fill(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 0,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      thumbColor: Colors.white,
                      activeTrackColor: Colors.transparent,
                      inactiveTrackColor: Colors.transparent,
                      overlayColor: Colors.white24,
                    ),
                    child: Slider(
                      value: progress,
                      onChanged: (v) => ctrl.seekTo(duration * v),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          // ── 播放控制 Row ─────────────────────────────────────────
          Row(
            children: [
              Text(_fmt(position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              _btn(Icons.skip_previous,
                  () => ctrl.seekTo(position - const Duration(milliseconds: 33))),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1AA87C),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _btn(Icons.skip_next,
                  () => ctrl.seekTo(position + const Duration(milliseconds: 33))),
              const Spacer(),
              Text(_fmt(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleCharts,
                child: AnimatedRotation(
                  turns: _chartsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: _chartsExpanded
                        ? const Color(0xFF1AA87C)
                        : Colors.white54,
                    size: 24,
                  ),
                ),
              ),
              if (!_isLongVideo) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _toggleAi,
                  child: Icon(
                    Icons.psychology_rounded,
                    color: _aiExpanded
                        ? const Color(0xFF7C3AED)
                        : Colors.white54,
                    size: 24,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // ── 揮桿 8 階段關鍵禎橫列 ─────────────────────────────────────

  Widget _buildPhaseStrip() {
    final phases = _phases!;
    final ctrl   = _controller;
    final posSec = ctrl != null && ctrl.value.isInitialized
        ? ctrl.value.position.inMilliseconds / 1000.0
        : 0.0;

    // 計算當前播放位置對應的階段（高亮）
    String? currentPhase;
    for (int i = _phaseOrder.length - 1; i >= 0; i--) {
      final key = _phaseOrder[i].$1;
      final t   = phases[key];
      if (t != null && posSec >= t - 0.05) {
        currentPhase = key;
        break;
      }
    }

    return Container(
      color: const Color(0xFF0A0A0A),
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        itemCount: _phaseOrder.length,
        itemBuilder: (context, index) {
          final (key, label) = _phaseOrder[index];
          final sec      = phases[key];
          final isActive = currentPhase == key;

          // Impact chip 在「擊球特效」開啟且有甜蜜點結果時顯示特殊顏色
          final isImpactMark = key == 'impact'
              && _showImpactFx
              && widget.entry?.goodShot != null;
          final impactColor = isImpactMark
              ? (widget.entry!.goodShot!
                  ? const Color(0xFFFFD700)
                  : const Color(0xFF9E9E9E))
              : null;

          final chipBg = impactColor != null
              ? impactColor.withValues(alpha: 0.14)
              : isActive ? kPrimaryGreen.withValues(alpha: 0.18) : const Color(0xFF1A1A1A);
          final chipBorderColor = impactColor != null
              ? impactColor.withValues(alpha: 0.75)
              : isActive ? kPrimaryGreen : Colors.white12;
          final chipBorderWidth = (impactColor != null || isActive) ? 1.5 : 1.0;
          final secColor = impactColor ?? (isActive ? kPrimaryGreen : Colors.white60);
          final labelColor = impactColor ?? (isActive ? Colors.white : Colors.white38);

          return GestureDetector(
            onTap: sec != null && ctrl != null
                ? () => ctrl.seekTo(Duration(milliseconds: (sec * 1000).round()))
                : null,
            child: Container(
              width: 58,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: chipBorderColor, width: chipBorderWidth),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isImpactMark)
                    Icon(
                      widget.entry!.goodShot! ? Icons.star_rounded : Icons.radio_button_unchecked_rounded,
                      color: impactColor,
                      size: 10,
                    ),
                  Text(
                    sec != null ? '${sec.toStringAsFixed(1)}s' : '--',
                    style: TextStyle(
                      color: secColor,
                      fontSize: isImpactMark ? 11 : 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    label,
                    style: TextStyle(
                      color: labelColor,
                      fontSize: 9,
                      fontWeight: (isActive || isImpactMark) ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── 圖表面板 ─────────────────────────────────────────────────

  Widget _buildChartsPanel() {
    // 姿勢/音頻特徵 tab 需要更多高度
    final contentHeight = _chartsExpanded
        ? (_chartTabIndex >= 3 ? 300.0 : 260.0)
        : 0.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: contentHeight,
      color: const Color(0xFF121212),
      child: ClipRect(child: _buildChartContent()),
    );
  }

  Widget _buildChartContent() {
    if (_chartsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1AA87C), strokeWidth: 2),
      );
    }
    final data = _chartData;
    if (data == null || data.isEmpty) {
      return const Center(
        child: Text('尚無圖表資料，請先完成分析',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    // ── 前 3 個 tab：時序折線圖資料 ────────────────────────
    List<ChartPoint>? activePoints;
    Color activeColor = _chartTabs[_chartTabIndex].color;
    bool invertY = false;
    String Function(double)? yLabel;
    String emptyLabel = '無資料';

    if (_chartTabIndex == 0) {
      activePoints = data.audioRms;
      invertY      = false;
      yLabel       = (v) => '${v.toStringAsFixed(0)}dB';
      emptyLabel   = '聲音峰值 無資料';
    } else if (_chartTabIndex == 1) {
      activePoints = data.wristY;
      invertY      = true;
      yLabel       = (v) => '${v.toStringAsFixed(0)}px';
      emptyLabel   = '手腕 Y 無資料';
    } else if (_chartTabIndex == 2) {
      activePoints = data.wristSpeed;
      invertY      = false;
      yLabel       = (v) => v.toStringAsFixed(0);
      emptyLabel   = '速度 無資料';
    }

    return Column(
      children: [
        // ── Tab 列（5 個）────────────────────────────────────
        Container(
          height: 36,
          color: const Color(0xFF1A1A1A),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_chartTabs.length, (i) {
                final t = _chartTabs[i];
                final selected = i == _chartTabIndex;
                return GestureDetector(
                  onTap: () {
                    setState(() => _chartTabIndex = i);
                    // 選到姿勢 tab 時自動載入 AI 狀態（取得 ONNX 分數）
                    if (i == 3 && _aiStatus == null && !_aiLoading) {
                      _loadAiStatus();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: selected ? t.color : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      t.label,
                      style: TextStyle(
                        color: selected ? t.color : Colors.white38,
                        fontSize: 12,
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
        // ── 內容區 ──────────────────────────────────────────
        Expanded(
          child: _chartTabIndex <= 2
              // 折線圖（聲音峰值 / 手腕 Y / 速度）
              ? (activePoints!.isEmpty
                  ? Center(
                      child: Text(emptyLabel,
                          style: const TextStyle(color: Colors.white24, fontSize: 12)),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
                      child: _PlayerChart(
                        key: ValueKey(_chartTabIndex),
                        points: activePoints,
                        color: activeColor,
                        invertY: invertY,
                        hitSecond: widget.entry?.hitSecond,
                        yLabel: yLabel!,
                      ),
                    ))
              // 靜態分析顯示（姿勢 / 音頻特徵）
              : _chartTabIndex == 3
                  ? _buildPostureContent()
                  : _buildAudioFeaturesContent(),
        ),
      ],
    );
  }

  // ── 姿勢 Tab（ONNX 分數橫向 bar chart）─────────────────────────

  Widget _buildPostureContent() {
    // 載入中
    if (_aiLoading) {
      return const Center(
        child: SizedBox(
          width: 22, height: 22,
          child: CircularProgressIndicator(
              color: Color(0xFF7C3AED), strokeWidth: 2),
        ),
      );
    }

    final onnxResult = _aiStatus?.onnxResult;

    // 有完整 ONNX 分數 → 橫條圖（與圖表頁 _OnnxPostureCard 一致）
    if (onnxResult != null && onnxResult.scores.isNotEmpty) {
      final sorted = onnxResult.scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: sorted.map((e) {
            final label     = SwingPosture.zhName(e.key);
            final score     = e.value.clamp(0.0, 1.0);
            final isOfficial = onnxResult.officialErrors.contains(e.key);
            final isSuspect  = onnxResult.suspectErrors.contains(e.key);
            final color = isOfficial
                ? const Color(0xFFEF4444)
                : isSuspect
                    ? const Color(0xFFF97316)
                    : const Color(0xFF22C55E);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white70)),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${(score * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: color),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: score,
                      minHeight: 7,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      );
    }

    // 只有頂層標籤（posture_only / fallback）
    final label = widget.entry?.swingPostureLabel;
    if (label != null) {
      final zhName = SwingPosture.zhName(label);
      final isGood = label.isEmpty;
      final color  = isGood ? const Color(0xFF22C55E) : const Color(0xFF7C3AED);

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(SwingPosture.icon(label), color: color, size: 32),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.4)),
              ),
              child: Text(zhName,
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _loadAiStatus,
              icon: const Icon(Icons.refresh_rounded, size: 13),
              label: const Text('載入詳細分數', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6)),
            ),
          ],
        ),
      );
    }

    return const Center(
      child: Text('尚無姿勢分析，請先完成分析',
          style: TextStyle(color: Colors.white38, fontSize: 12)),
    );
  }

  // ── 音頻特徵 Tab（量規 bar chart，與圖表頁 _AudioFeatureGaugeRow 一致）

  static const _kAudioDisplayRanges = <String, List<double>>{
    'rms_dbfs':          [-45.0, -5.0],
    'spectral_centroid': [1500.0, 7000.0],
    'sharpness_hfxloud': [0.0, 6.0],
    'highband_amp':      [0.0, 60.0],
    'peak_dbfs':         [-30.0, 0.0],
  };

  Widget _buildAudioFeaturesContent() {
    final entry         = widget.entry;
    final featureValues = entry?.audioFeatureValues ?? const <String, double>{};
    final passes        = entry?.audioPasses ?? const <String, bool>{};
    final hasData       = featureValues.isNotEmpty;
    final passCount     = passes.values.where((v) => v).length;
    final goodShot      = entry?.goodShot;
    const goodColor     = Color(0xFF22C55E);
    const badColor      = Color(0xFFEF4444);
    final scoreColor    = goodShot == true
        ? goodColor
        : goodShot == false
            ? badColor
            : Colors.white54;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 通過數 + 結果標籤 ──────────────────────────────────
          Row(
            children: [
              Text(
                hasData ? '$passCount / 5 項通過' : '尚無音頻分析',
                style: TextStyle(
                    color: hasData ? scoreColor : Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w700),
              ),
              if (hasData && entry?.audioLabel?.isNotEmpty == true) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scoreColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry!.audioLabel!,
                    style: TextStyle(
                        color: scoreColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // ── 5 個特徵量規行（仿圖表頁 _AudioFeatureGaugeRow）──────
          for (final feat in AudioAnalysisService.featureLabels.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _buildDarkGaugeRow(
                label:        feat.value,
                featureKey:   feat.key,
                value:        featureValues[feat.key],
                passed:       passes[feat.key] ?? false,
                hasData:      hasData,
                displayRange: _kAudioDisplayRanges[feat.key] ?? [0.0, 100.0],
                threshold:    AudioAnalysisService.ruleIntervals[feat.key] ??
                              [0.0, 1.0],
              ),
            ),
        ],
      ),
    );
  }

  /// 深色主題量規行（仿 recording_detail_page 的 _AudioFeatureGaugeRow）
  Widget _buildDarkGaugeRow({
    required String label,
    required String featureKey,
    required double? value,
    required bool passed,
    required bool hasData,
    required List<double> displayRange,
    required List<double> threshold,
  }) {
    const goodColor = Color(0xFF22C55E);
    const badColor  = Color(0xFFEF4444);
    final barColor  = !hasData
        ? Colors.white24
        : passed
            ? goodColor
            : badColor;

    double norm(double v) =>
        ((v - displayRange[0]) / (displayRange[1] - displayRange[0]))
            .clamp(0.0, 1.0);

    final tLowN  = norm(threshold[0]);
    final tHighN = norm(threshold[1]);
    final valN   = value != null ? norm(value) : null;

    return Row(
      children: [
        // 標籤
        SizedBox(
          width: 32,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.white70)),
        ),
        const SizedBox(width: 8),
        // 量規軌道
        Expanded(
          child: LayoutBuilder(builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: 16,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // 背景軌道
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: hasData ? 0.08 : 0.04),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  // 甜蜜點區間（綠色帶）
                  if (hasData)
                    Positioned(
                      left:  tLowN * width,
                      width: (tHighN - tLowN) * width,
                      top:   3,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: goodColor.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  // 實際值標記點
                  if (valN != null)
                    Positioned(
                      left:   (valN * width - 4).clamp(0.0, width - 8),
                      top:    2,
                      bottom: 2,
                      width:  8,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: [
                            BoxShadow(
                              color: barColor.withValues(alpha: 0.55),
                              blurRadius: 4,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
        const SizedBox(width: 8),
        // 數值 + 通過圖示
        SizedBox(
          width: 68,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                value != null
                    ? AudioAnalysisService.formatFeatureValue(featureKey, value)
                    : '—',
                style: TextStyle(
                    fontSize: 10,
                    color: barColor,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Icon(
                (hasData && passed)
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: barColor,
                size: 13,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _btn(IconData icon, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Icon(icon, color: Colors.white70, size: 26));

  // ── AI 分析面板 ──────────────────────────────────────────────

  Widget _buildAiPanel() {
    if (_isLongVideo) return const SizedBox.shrink();
    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: _aiExpanded
          ? Container(
              color: const Color(0xFF0D0D1A),
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(child: _buildAiContent()),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildAiContent() {
    if (_aiLoading) {
      return const Center(
        child: SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(
              color: Color(0xFF7C3AED), strokeWidth: 2.5),
        ),
      );
    }
    final status = _aiStatus;

    // 尚無分析
    if (status == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.psychology_rounded,
                color: Color(0xFF7C3AED), size: 22),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('尚未進行 AI 教練分析',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ),
            _aiSubmitting
                ? const SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        color: Color(0xFF7C3AED), strokeWidth: 2))
                : TextButton(
                    onPressed: () => _openOrSubmitAi(),
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF7C3AED),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                    ),
                    child: const Text('開始分析',
                        style: TextStyle(fontSize: 13)),
                  ),
          ],
        ),
      );
    }

    // 進行中
    if (status.isActive) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  color: Color(0xFF7C3AED), strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_aiStatusLabel(status.status),
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 13)),
            ),
            TextButton(
              onPressed: () => _openOrSubmitAi(),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF7C3AED),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
              ),
              child: const Text('查看進度',
                  style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      );
    }

    // 已完成
    final result = status.result;
    final sevColor = _severityColor(status.severity ?? 'low');

    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 標題列 ──────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.psychology_rounded,
                  color: Color(0xFF7C3AED), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('AI 教練分析',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              if (status.severity != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: sevColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(_severityLabel(status.severity!),
                      style: TextStyle(fontSize: 11, color: sevColor, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          // ── 摘要 ────────────────────────────────────────────
          if (status.summary != null) ...[
            const SizedBox(height: 8),
            Text(status.summary!,
                style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.5)),
          ],
          // ── 以下需要 result 物件 ─────────────────────────────
          if (result != null) ...[
            // 主要錯誤
            if (result.primaryError.zhName.isNotEmpty) ...[
              const SizedBox(height: 10),
              _aiSectionTitle('主要問題'),
              const SizedBox(height: 4),
              _aiTag(result.primaryError.zhName, sevColor),
              if (result.primaryError.evidence.isNotEmpty)
                ...result.primaryError.evidence.map((e) => _aiBullet(e)),
            ],
            // 教練評語
            if (result.coachFeedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              _aiSectionTitle('教練評語'),
              const SizedBox(height: 4),
              ...result.coachFeedback.map((f) => _aiBullet(f)),
            ],
            // 訓練建議
            if (result.practiceSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              _aiSectionTitle('訓練建議'),
              const SizedBox(height: 4),
              ...result.practiceSuggestions.asMap().entries.map((entry) {
                final i = entry.key;
                final s = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 18, height: 18,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: Color(0xFF7C3AED),
                              shape: BoxShape.circle,
                            ),
                            child: Text('${i + 1}',
                                style: const TextStyle(color: Colors.white, fontSize: 10)),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s.drill,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                if (s.reps.isNotEmpty)
                                  Text(s.reps,
                                      style: const TextStyle(color: Color(0xFF7C3AED), fontSize: 11)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (s.instruction.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 24, top: 3),
                          child: Text(s.instruction,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 11, height: 1.4)),
                        ),
                    ],
                  ),
                );
              }),
            ],
            // 下次目標
            if (result.nextTrainingGoal.isNotEmpty) ...[
              const SizedBox(height: 10),
              _aiSectionTitle('下次目標'),
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.flag_rounded, color: Color(0xFF4CAF50), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(result.nextTrainingGoal,
                        style: const TextStyle(color: Colors.white60, fontSize: 12, height: 1.4)),
                  ),
                ],
              ),
            ],
          ],
          // ── 按鈕列 ──────────────────────────────────────────
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => _openOrSubmitAi(forceReanalyze: true),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white38,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 12),
                ),
                child: const Text('重新分析'),
              ),
              const SizedBox(width: 4),
              ElevatedButton(
                onPressed: () => _openOrSubmitAi(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  textStyle: const TextStyle(fontSize: 13),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('查看詳細'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _aiSectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      color: Colors.white70,
      fontSize: 11,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.5,
    ),
  );

  Widget _aiTag(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    margin: const EdgeInsets.only(bottom: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withValues(alpha: 0.5)),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
  );

  Widget _aiBullet(String text) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 5),
          child: Icon(Icons.circle, color: Colors.white38, size: 5),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 12, height: 1.4)),
        ),
      ],
    ),
  );

  String _aiStatusLabel(String s) => switch (s) {
    'pending'    => '準備中...',
    'queued'     => '等待分析佇列...',
    'processing' => 'AI 教練分析中...',
    _            => '分析中...',
  };

  Color _severityColor(String s) => switch (s) {
    'high'   => kBadColor,
    'medium' => kCrispColor,
    _        => kGoodColor,
  };

  String _severityLabel(String s) => switch (s) {
    'high'   => '嚴重',
    'medium' => '中等',
    _        => '輕微',
  };
}

// ════════════════════════════════════════════════════════════════
// 播放器內用的深色主題圖表
// ════════════════════════════════════════════════════════════════

class _PlayerChart extends StatefulWidget {
  final List<ChartPoint> points;
  final Color color;
  final bool invertY;
  final double? hitSecond;
  final String Function(double) yLabel;

  const _PlayerChart({
    super.key,
    required this.points,
    required this.color,
    required this.invertY,
    required this.hitSecond,
    required this.yLabel,
  });

  @override
  State<_PlayerChart> createState() => _PlayerChartState();
}

class _PlayerChartState extends State<_PlayerChart> {
  late final double _rawMaxY = widget.invertY
      ? widget.points.map((e) => e.y).reduce((a, b) => a > b ? a : b)
      : 0;

  double _toRaw(double displayY) =>
      widget.invertY ? (_rawMaxY - displayY) : displayY;

  late final List<FlSpot> _spots = widget.invertY
      ? widget.points.map((p) => FlSpot(p.x, _rawMaxY - p.y)).toList()
      : widget.points.map((p) => FlSpot(p.x, p.y)).toList();

  late final double _minX = widget.points.first.x;
  late final double _maxX = widget.points.last.x;
  late final double _minY =
      _spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
  late final double _maxY =
      _spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
  double get _yPad => (_maxY - _minY) * 0.12 + 1;

  @override
  Widget build(BuildContext context) {
    return LineChart(
      LineChartData(
        minX: _minX,
        maxX: _maxX,
        minY: _minY - _yPad,
        maxY: _maxY + _yPad,
        clipData: const FlClipData.all(),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => Colors.black54,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.x.toStringAsFixed(2)}s\n${widget.yLabel(_toRaw(s.y))}',
                      const TextStyle(color: Colors.white, fontSize: 10),
                    ))
                .toList(),
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: (_maxY - _minY + 1) / 3,
          getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.white.withValues(alpha: 0.07),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
            left: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 38,
              interval: (_maxY - _minY + 1) / 3,
              getTitlesWidget: (val, _) => Text(
                widget.yLabel(_toRaw(val)),
                style: const TextStyle(fontSize: 8, color: Colors.white38),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 16,
              interval: (_maxX - _minX) / 4,
              getTitlesWidget: (val, _) => Text(
                '${val.toStringAsFixed(1)}s',
                style: const TextStyle(fontSize: 8, color: Colors.white38),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        extraLinesData: widget.hitSecond != null
            ? ExtraLinesData(verticalLines: [
                VerticalLine(
                  x: widget.hitSecond!,
                  color: const Color(0xFFFF6F00),
                  strokeWidth: 1.5,
                  dashArray: [5, 4],
                  label: VerticalLineLabel(
                    show: true,
                    alignment: Alignment.topRight,
                    labelResolver: (_) => 'Hit',
                    style: const TextStyle(
                      color: Color(0xFFFF6F00),
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ])
            : null,
        lineBarsData: [
          LineChartBarData(
            spots: _spots,
            isCurved: true,
            curveSmoothness: 0.25,
            color: widget.color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  widget.color.withValues(alpha: 0.25),
                  widget.color.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }

}

// ════════════════════════════════════════════════════════════════
// Simple preview page for a generated highlight clip.
// ════════════════════════════════════════════════════════════════

class HighlightPreviewPage extends StatefulWidget {
  const HighlightPreviewPage({super.key, required this.videoPath});
  final String videoPath;

  @override
  State<HighlightPreviewPage> createState() => _HighlightPreviewPageState();
}

class _HighlightPreviewPageState extends State<HighlightPreviewPage> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.file(File(widget.videoPath))
      ..initialize().then((_) {
        _ctrl?.addListener(_onUpdate);
        _ctrl?.setLooping(true);
        _ctrl?.play();
        if (mounted) setState(() => _initialized = true);
      });
  }

  void _onUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.removeListener(_onUpdate);
    _ctrl?.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _ctrl;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 48,
              color: Colors.black87,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 8),
                  const Text('精彩片段預覽',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                ],
              ),
            ),
            Expanded(
              child: ctrl == null || !_initialized
                  ? const Center(child: CircularProgressIndicator(color: Colors.white54))
                  : Center(
                      child: AspectRatio(
                        aspectRatio: ctrl.value.aspectRatio,
                        child: VideoPlayer(ctrl),
                      ),
                    ),
            ),
            if (_initialized && ctrl != null)
              _buildControls(ctrl),
          ],
        ),
      ),
    );
  }

  Widget _buildControls(VideoPlayerController ctrl) {
    final position = ctrl.value.position;
    final duration = ctrl.value.duration;
    final progress = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: const Color(0xFF1AA87C),
              thumbColor: Colors.white,
              inactiveTrackColor: Colors.white24,
              overlayColor: Colors.white24,
            ),
            child: Slider(
              value: progress,
              onChanged: (v) => ctrl.seekTo(duration * v),
            ),
          ),
          Row(
            children: [
              Text(_fmt(position),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
              const Spacer(),
              GestureDetector(
                onTap: () => ctrl.value.isPlaying ? ctrl.pause() : ctrl.play(),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFF1AA87C),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    ctrl.value.isPlaying ? Icons.pause : Icons.play_arrow,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
              ),
              const Spacer(),
              Text(_fmt(duration),
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 甜蜜點擊球光圈 Painter
// ════════════════════════════════════════════════════════════════

class _SweetSpotRingPainter extends CustomPainter {
  final double progress; // 0 → 1
  final bool? goodShot;
  final int passCount;

  const _SweetSpotRingPainter({
    required this.progress,
    required this.goodShot,
    required this.passCount,
  });

  Color get _baseColor {
    if (goodShot == true && passCount >= 4) return const Color(0xFFFFD700);
    if (goodShot == true) return const Color(0xFF90CAF9);
    return const Color(0xFF9E9E9E);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (goodShot == null || progress <= 0) return;

    final color  = _baseColor;
    final center = Offset(size.width * 0.5194, size.height * 0.8469);

    for (int i = 0; i < 3; i++) {
      final delay = i * 0.18;
      final t = ((progress - delay) / 0.65).clamp(0.0, 1.0);
      if (t <= 0) continue;

      final eased  = Curves.easeOut.transform(t);
      final radius = 18.0 + eased * 65.0;
      final opacity = (1.0 - eased).clamp(0.0, 1.0) * 0.85;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5 + (1.0 - eased) * 2.0,
      );
    }
  }

  @override
  bool shouldRepaint(_SweetSpotRingPainter old) =>
      old.progress != progress || old.goodShot != goodShot || old.passCount != passCount;
}

// ════════════════════════════════════════════════════════════════
// 甜蜜點徽章 Widget
// ════════════════════════════════════════════════════════════════

class _SweetSpotBadge extends StatelessWidget {
  final double progress;
  final bool? goodShot;
  final int passCount;

  const _SweetSpotBadge({
    required this.progress,
    required this.goodShot,
    required this.passCount,
  });

  @override
  Widget build(BuildContext context) {
    if (goodShot == null || progress <= 0) return const SizedBox.shrink();

    final opacity = progress < 0.12
        ? progress / 0.12
        : progress > 0.65
            ? ((1.0 - progress) / 0.35).clamp(0.0, 1.0)
            : 1.0;
    final slideY = (1.0 - (progress / 0.15).clamp(0.0, 1.0)) * 10.0;

    final Color color;
    final String title;
    final IconData icon;
    if (goodShot! && passCount >= 4) {
      color = const Color(0xFFFFD700);
      title = '甜蜜點命中';
      icon  = Icons.star_rounded;
    } else if (goodShot!) {
      color = const Color(0xFF90CAF9);
      title = '甜蜜點';
      icon  = Icons.check_circle_rounded;
    } else {
      color = const Color(0xFF9E9E9E);
      title = '偏虛球';
      icon  = Icons.radio_button_unchecked_rounded;
    }

    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, -slideY),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.75)),
            boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8)],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color, size: 13),
              const SizedBox(width: 5),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
                  Text('$passCount/5 特徵符合',
                      style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 多模態時間軸 Painter
// 合併：音訊 RMS 波形柱 + 手腕速度曲線 + 8 階段 tick + impact 鑽石 + 播放游標
// ════════════════════════════════════════════════════════════════

class _MultiModalTimelinePainter extends CustomPainter {
  final List<ChartPoint> audioRms;
  final List<ChartPoint> wristSpeed;
  final Map<String, double> phases;
  final double? hitSecond;
  final double currentSecond;
  final double totalSeconds;
  final bool? goodShot;

  // Flutter Slider 內部 track 兩側的 horizontal padding（固定 20px）
  static const double _hPad = 20.0;

  static const _phaseLabels = <String, String>{
    'address':       '準',
    'takeaway':      '起',
    'backswing':     '上',
    'top':           '頂',
    'downswing':     '下',
    'impact':        '擊',
    'followthrough': '送',
    'finish':        '收',
  };

  const _MultiModalTimelinePainter({
    required this.audioRms,
    required this.wristSpeed,
    required this.phases,
    this.hitSecond,
    required this.currentSecond,
    required this.totalSeconds,
    this.goodShot,
  });

  double _secToX(double sec, double trackW) =>
      _hPad + (sec / totalSeconds).clamp(0.0, 1.0) * trackW;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalSeconds <= 0) return;

    final trackW = size.width - _hPad * 2;

    // ── 層1：基礎軌道（細線，讓空白處仍有視覺參考）──────────────
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(_hPad, size.height / 2 - 1.0, trackW, 2.0),
        const Radius.circular(1.0),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.10),
    );

    // ── 層2：音訊 RMS 波形柱（底部 46% 高度空間）──────────────
    if (audioRms.isNotEmpty) {
      const numBars = 72;
      const barGap  = 1.2;
      final barW    = (trackW - (numBars - 1) * barGap) / numBars;
      final maxBarH = size.height * 0.44;
      final barBotY = size.height - 2.0;

      // 每根 bar 取對應時間區段的最大振幅
      final buckets = List<double>.filled(numBars, 0.0);
      for (final pt in audioRms) {
        final bi = ((pt.x / totalSeconds) * numBars).floor().clamp(0, numBars - 1);
        final h  = ((pt.y + 60.0) / 55.0).clamp(0.0, 1.0); // rms_dbfs: -60~0
        if (h > buckets[bi]) buckets[bi] = h;
      }

      final cursorFrac = (currentSecond / totalSeconds).clamp(0.0, 1.0);
      final hitBarIdx  = hitSecond != null
          ? ((hitSecond! / totalSeconds) * numBars).floor().clamp(0, numBars - 1)
          : -1;

      final paintPlayed = Paint()..color = const Color(0xFF1AA87C).withValues(alpha: 0.80);
      final paintFuture = Paint()..color = Colors.white.withValues(alpha: 0.18);
      final paintHit    = Paint()..color = const Color(0xFFFF8F00);
      final paintGlow   = Paint()
        ..color      = const Color(0xFFFF8F00).withValues(alpha: 0.28)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

      for (int i = 0; i < numBars; i++) {
        final bx = _hPad + i * (barW + barGap);
        final h  = max(buckets[i], 0.05) * maxBarH;
        final top = barBotY - h;
        final rr = RRect.fromRectAndRadius(
          Rect.fromLTWH(bx, top, barW, h),
          const Radius.circular(1.5),
        );
        final isHit    = i == hitBarIdx;
        final isPlayed = (i + 0.5) / numBars <= cursorFrac;

        if (isHit) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(bx - 2, barBotY - maxBarH - 2, barW + 4, maxBarH + 4),
              const Radius.circular(2),
            ),
            paintGlow,
          );
          canvas.drawRRect(rr, paintHit);
        } else {
          canvas.drawRRect(rr, isPlayed ? paintPlayed : paintFuture);
        }
      }
    }

    // ── 層3：手腕速度折線（上部 46% 高度空間）────────────────────
    if (wristSpeed.isNotEmpty) {
      final maxSpd = wristSpeed.map((p) => p.y).reduce(max);
      if (maxSpd > 0) {
        const topY  = 2.0;
        final botY  = size.height * 0.50;
        final zoneH = botY - topY;

        final path = Path();
        bool first = true;
        for (final pt in wristSpeed) {
          final x    = _secToX(pt.x, trackW);
          final norm = (pt.y / maxSpd).clamp(0.0, 1.0);
          final y    = botY - norm * zoneH;
          if (first) { path.moveTo(x, y); first = false; }
          else        { path.lineTo(x, y); }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color      = const Color(0xFFFF8F00).withValues(alpha: 0.60)
            ..style      = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..strokeCap  = StrokeCap.round
            ..strokeJoin = StrokeJoin.round,
        );
      }
    }

    // ── 層4：8 階段 tick 標記 + 底部文字 ──────────────────────────
    if (phases.isNotEmpty) {
      for (final e in phases.entries) {
        if (e.value < 0 || e.value > totalSeconds) continue;
        final isImpact = e.key == 'impact';
        final x = _secToX(e.value, trackW);

        // 垂直 tick 線
        canvas.drawLine(
          Offset(x, isImpact ? size.height * 0.08 : size.height * 0.28),
          Offset(x, size.height * 0.82),
          Paint()
            ..color      = isImpact
                ? const Color(0xFFFF8F00).withValues(alpha: 0.90)
                : Colors.white.withValues(alpha: 0.22)
            ..strokeWidth = isImpact ? 1.5 : 1.0,
        );

        // 底部單字 label
        final label = _phaseLabels[e.key] ?? '';
        if (label.isNotEmpty) {
          _drawText(
            canvas, label,
            Offset(x, size.height * 0.85),
            isImpact
                ? const Color(0xFFFF8F00)
                : Colors.white.withValues(alpha: 0.22),
            8.5,
          );
        }
      }
    }

    // ── 層5：Impact 鑽石標記 ────────────────────────────────────
    if (hitSecond != null) {
      final x  = _secToX(hitSecond!, trackW);
      final cy = size.height * 0.25;
      final Color dc = goodShot == true
          ? const Color(0xFFFFD700)
          : goodShot == false
              ? const Color(0xFF9E9E9E)
              : const Color(0xFFFF8F00);

      // 暈光
      canvas.drawCircle(
        Offset(x, cy), 7,
        Paint()
          ..color      = dc.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
      );
      // 鑽石形
      const r = 5.0;
      final diamond = Path()
        ..moveTo(x,           cy - r)
        ..lineTo(x + r * 0.7, cy)
        ..lineTo(x,           cy + r)
        ..lineTo(x - r * 0.7, cy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = dc);
    }

    // ── 層6：播放游標（白色細線 + 頂部小三角）───────────────────
    final cx = _hPad + (currentSecond / totalSeconds).clamp(0.0, 1.0) * trackW;
    canvas.drawRect(
      Rect.fromLTWH(cx - 0.75, 0, 1.5, size.height * 0.84),
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );
    final arrowPath = Path()
      ..moveTo(cx - 3.5, 0)
      ..lineTo(cx + 3.5, 0)
      ..lineTo(cx, 5.0)
      ..close();
    canvas.drawPath(arrowPath, Paint()..color = Colors.white);
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset anchor,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(anchor.dx - tp.width / 2, anchor.dy));
  }

  @override
  bool shouldRepaint(_MultiModalTimelinePainter old) =>
      old.currentSecond != currentSecond ||
      old.hitSecond     != hitSecond     ||
      old.totalSeconds  != totalSeconds  ||
      old.audioRms      != audioRms      ||
      old.wristSpeed    != wristSpeed    ||
      old.phases        != phases        ||
      old.goodShot      != goodShot;
}
