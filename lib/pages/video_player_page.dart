import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;
import 'package:video_player/video_player.dart';

import '../models/recording_history_entry.dart';
import '../models/p_system_metrics.dart';
import 'ball_tuning_page.dart';
import '../models/swing_posture.dart';
import '../recording/pose_csv_loader.dart';
import '../recording/skeleton_painter.dart';
import '../recording/trajectory_painter.dart';
import '../recording/widgets/anchor_marker.dart';
import '../services/analysis_service.dart';
import '../services/audio_analysis_service.dart';
import '../services/chart_data_service.dart';
import '../services/recording_history_storage.dart';
import '../services/skeleton_csv_locator.dart';
import '../services/swing_auto_clip_service.dart';
import '../services/swing_detect_prefs.dart';
import '../services/swing_stats_service.dart';
import '../services/biomechanics_service.dart';
import '../theme/app_theme.dart';
import '../widgets/clip_candidates_sheet.dart';
import '../widgets/zoomable_timeline.dart';
import 'ai_coach_page.dart';
import 'p_system_help_page.dart';
import 'package:golf_score_app/l10n/app_localizations.dart';

/// Lightweight player for reviewing a recorded swing video.
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    required this.videoPath,
    this.avatarPath,
    this.startPosition,
    this.entry,
    this.onEntryUpdated,
  });

  final String videoPath;
  final String? avatarPath;
  final Duration? startPosition;
  final RecordingHistoryEntry? entry;

  /// 備註更新後通知上層列表刷新（與 recording_history_page 一致）。
  /// 為 null 時仍會直接寫入 DB，故獨立進入查看頁也可儲存。
  final void Function(RecordingHistoryEntry old, RecordingHistoryEntry updated)?
      onEntryUpdated;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage>
    with TickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _initialized = false;

  /// 目前備註（可即時編輯，與 widget.entry.note 脫鉤以便就地更新標題列圖示）
  String? _note;
  bool _noteExpanded = false; // 底部備註條是否展開

  // 60Hz 播放頭（骨架/軌跡疊圖專用，見 _onTick）
  final ValueNotifier<double> _playheadSec = ValueNotifier(0.0);

  /// 疊圖播放補償（秒）：video_player 回報的 position 與實際顯示的影片幀之間有
  /// 解碼/呈現延遲，直接用 position 取樣 CSV 會讓骨架落後顯示幀（即時錄製端無此
  /// 問題，因骨架直接畫在當下相機幀）。取樣時間提前此值，把疊圖往前拉對齊顯示幀。
  /// 實機觀察可調（查看影片設定）：骨架仍落後→調大、變超前→調小。
  double _overlayLeadSec = SwingDetectPrefs.defaultOverlayLeadMs / 1000.0;
  Ticker? _playheadTicker;
  Duration _lastReportedPos = Duration.zero;
  DateTime? _lastReportAt;

  /// 是否為長影片（原始錄製 > 5 秒），長影片無骨架/分析 Tab 及 AI，但可顯示圖表
  bool get _isLongVideo =>
      widget.entry?.videoType == VideoType.original &&
      (widget.entry?.durationSeconds ?? 0) > 5;

  // Charts panel state
  bool _chartsExpanded = false;
  bool _statsExpanded = false;
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

  // P1-P10 動作分析（angles.json）；null = 無（V2 音訊切片 / 舊片）
  PSystemMetrics? _pSystem;

  // P-System 標籤樣式：false=字母簡稱(P1…P10)、true=文字簡稱(預備/桿平上…)。可切換+持久化。
  bool _pSysTextLabel = false;

  // 長影片：已切出片段的擊球時間點（秒，相對原始影片），供時間軸標記與快速跳轉
  List<({double sec, int index})> _clipMarks = const [];

  // 長影片：已切出片段的剪輯起迄區間（秒，相對原始影片），供時間軸綠/紅邊界標記
  List<({double start, double end})> _clipRanges = const [];

  // 骨架疊圖（取代燒錄 skeleton.mp4）：CSV 為 clip 相對時間，offset=0 直接用 position 取樣
  PoseTrack? _skeletonTrack;
  bool _skeletonLoading = false;
  // ── 疊層開關（取代舊 Tab 切換）：骨架 / 軌跡各自獨立 checkbox ─────────────
  bool _showSkeleton   = false;
  bool _showTrajectory = false;
  bool _showImpactFx   = false;   // 擊球光圈 / Sweet Spot 徽章 / impact chip 金標
  bool _showAnchor     = false;   // 擊球錨點標記（anchor.json 存在才可開）
  (double, double)? _anchor;      // 歸一化錨點座標（display 空間，已對齊 base 影片）
  late final bool _hasTrajectory;   // trajectory.json 是否存在
  bool get _hasImpactFx =>
      widget.entry?.hitSecond != null && widget.entry?.goodShot != null;

  TrajectoryTrack? _trajTrack;

  // 甜蜜點特效動畫（僅分析 Tab）
  late final AnimationController _impactAnim;
  bool _impactTriggered = false;
  static const _phaseKeys = [
    'address',
    'takeaway',
    'backswing',
    'top',
    'downswing',
    'impact',
    'followthrough',
    'finish',
  ];

  /// 骨架 CSV 是否存在（逐幀版或 live 版皆可；initState 檢查一次）
  late final bool _hasSkeletonCsv;

  static const _chartTabColors = [
    Color(0xFFE53935),
    Color(0xFF1565C0),
    Color(0xFF1AA87C),
    Color(0xFF7C3AED),
    Color(0xFF7B1FA2),
  ];

  String get _sessionDir => '${p.dirname(widget.videoPath)}${p.separator}';

  @override
  void initState() {
    super.initState();

    _note = widget.entry?.note;
    _hasSkeletonCsv = resolveSkeletonCsv(p.dirname(widget.videoPath)) != null;
    _hasTrajectory  = File('${_sessionDir}trajectory.json').existsSync();

    _impactAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _playheadTicker = createTicker(_onTick)..start();
    SwingDetectPrefs.getOverlayLeadMs().then((v) {
      if (mounted) setState(() => _overlayLeadSec = v / 1000.0);
    });

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
      _loadPSystem();
      _loadCharts();
    }

    // 長影片：載入已切片段的擊球時間點（時間軸標記 + 快速跳轉）
    if (_isLongVideo) _loadClipMarks();

    // 擊球錨點：此 session 有 anchor.json 才顯示（切片切下時已連同錨點寫入）。
    // 座標為 display 歸一化、已對齊 base 影片（切片翻轉時 x 已於切片階段鏡像）。
    _loadAnchor();
  }

  Future<void> _loadAnchor() async {
    final a = await SwingAutoClipService.loadAnchor(p.dirname(widget.videoPath));
    if (!mounted || a == null) return;
    setState(() {
      _anchor = a;
      _showAnchor = true; // 有錨點預設顯示
    });
  }

  /// 查出此長影片切出的所有片段，換算擊球時刻回原始影片座標。
  /// clip 的 hitSecond 為 clip 內相對時間，startSecond 為 clip 在原片的起點。
  Future<void> _loadClipMarks() async {
    try {
      final all = await RecordingHistoryStorage.instance.loadHistory();
      final marks = <double>[];
      final ranges = <({double start, double end})>[];
      for (final e in all) {
        if (e.sourceVideoPath != widget.videoPath) continue;
        final hit = e.hitSecond;
        if (hit == null) continue;
        marks.add((e.startSecond ?? 0.0) + hit);
        final st = e.startSecond;
        final en = e.endSecond;
        if (st != null && en != null && en > st) {
          ranges.add((start: st, end: en));
        }
      }
      marks.sort();
      ranges.sort((a, b) => a.start.compareTo(b.start));
      if (mounted && marks.isNotEmpty) {
        setState(() {
          _clipMarks = [
            for (int i = 0; i < marks.length; i++) (sec: marks[i], index: i + 1),
          ];
          _clipRanges = ranges;
        });
      }
    } catch (e) {
      debugPrint('[VideoPlayer] 切片標記載入失敗: $e');
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

  Future<void> _loadPSystem() async {
    final ps = await PSystemMetrics.load(p.dirname(widget.videoPath));
    if (ps == null) return;
    final textLabel = await SwingDetectPrefs.getPSystemTextLabel();
    if (mounted) setState(() { _pSystem = ps; _pSysTextLabel = textLabel; });
  }

  Future<void> _initController(String path, {bool isOriginal = false}) async {
    final file = File(path);
    if (!file.existsSync()) {
      _showSnackKey((l) => l.playerVideoNotFound);
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
      if (mounted) _showSnackKey((l) => l.playerVideoLoadFailed);
    } finally {
      await old?.dispose();
    }
  }

  void _onUpdate() {
    if (!mounted) return;
    // 記錄最近一次平台回報的位置與時刻，供 ticker 在兩次回報之間插值
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      _lastReportedPos = ctrl.value.position;
      _lastReportAt = DateTime.now();
      _playheadSec.value = _lastReportedPos.inMilliseconds / 1000.0;
    }
    _checkImpactTrigger();
    setState(() {});
  }

  /// 60Hz 播放頭：video_player 的 position listener 僅 ~2Hz 回報，
  /// 直接用它驅動骨架/軌跡疊圖會階梯跳動且視覺落後。
  /// ticker 在兩次回報之間以 wall-clock 外插，疊圖以此 notifier 重繪。
  void _onTick(Duration _) {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (!ctrl.value.isPlaying) return;
    final reportAt = _lastReportAt;
    if (reportAt == null) return;
    final elapsed =
        DateTime.now().difference(reportAt).inMilliseconds *
            ctrl.value.playbackSpeed;
    final durMs = ctrl.value.duration.inMilliseconds;
    final est = (_lastReportedPos.inMilliseconds + elapsed)
        .clamp(0.0, durMs.toDouble());
    _playheadSec.value = est / 1000.0;
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

  void _toggleStats() {
    setState(() => _statsExpanded = !_statsExpanded);
    // 軌跡 lazy-load：未載入時補載，載完 setState 自動刷新面板
    if (_statsExpanded && _trajTrack == null) _ensureTrajectoryTrack();
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
          SnackBar(content: Text(AppLocalizations.of(context).playerAiAnalysisFailed(e.toString())), backgroundColor: Colors.red),
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
    _playheadTicker?.dispose();
    _playheadSec.dispose();
    _impactAnim.dispose();
    _controller?.removeListener(_onUpdate);
    _controller?.dispose();
    super.dispose();
  }

  /// Like _showSnackKey but resolves the l10n string lazily inside the post-frame
  /// callback, safe to call from [initState] or async methods before first build.
  void _showSnackKey(String Function(AppLocalizations) resolve) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(resolve(AppLocalizations.of(context)))));
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
      _showSnackKey((l) => l.playerSkeletonNotFound);
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

  /// 擊球光暈中心：取球軌跡起始點（球的靜止位置）的 display 正規化座標；
  /// 無軌跡時回傳 null → painter 退回預設比例。
  Offset? _impactBallNorm() {
    final t = _trajTrack;
    if (t == null || t.points.isEmpty) return null;
    return t.normalizedDisplay(t.points.first);
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
            // 合併：有 P-System(angles.json) → P1-P10 條（點=seek＋長按=角度＋播放高亮）；
            // 否則（舊片/V2 無角度）退回 8 階段條（純 seek）。
            if (_initialized && _pSystem != null)
              _buildPSystemPanel()
            else if (_initialized && _phases != null)
              _buildPhaseStrip(),
            _buildStatsPanel(),
            _buildChartsPanel(),
            _buildAiPanel(),
            // 最底部備註條（可展開/折疊）
            if (widget.entry != null) _buildNoteBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
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
              widget.entry?.displayTitle ?? l10n.playerTitle,
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

  /// 底部備註條：可展開/折疊。折疊只顯示圖示+標題(+片段)，展開顯示完整備註。
  Widget _buildNoteBar() {
    final l10n = AppLocalizations.of(context);
    final note = (_note ?? '').trim();
    final hasNote = note.isNotEmpty;
    return Material(
      color: Colors.black87,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 標題列（點擊展開/折疊）──
          InkWell(
            onTap: () => setState(() => _noteExpanded = !_noteExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    hasNote ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                    size: 18,
                    color: hasNote ? kBrandPrimary : Colors.white54,
                  ),
                  const SizedBox(width: 8),
                  Text(l10n.playerNote,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 8),
                  // 折疊時顯示片段
                  if (!_noteExpanded)
                    Expanded(
                      child: Text(
                        hasNote ? note : l10n.playerNoteAdd,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: hasNote ? Colors.white60 : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  // 編輯
                  InkResponse(
                    onTap: _editVideoNote,
                    radius: 18,
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit, size: 16, color: Colors.white54),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _noteExpanded ? Icons.expand_more_rounded : Icons.expand_less_rounded,
                    size: 20, color: Colors.white54,
                  ),
                ],
              ),
            ),
          ),
          // ── 展開內容 ──
          if (_noteExpanded)
            InkWell(
              onTap: _editVideoNote,
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxHeight: 140),
                padding: const EdgeInsets.fromLTRB(40, 0, 12, 12),
                child: SingleChildScrollView(
                  child: Text(
                    hasNote ? note : l10n.playerNoteAdd,
                    style: TextStyle(
                      color: hasNote ? Colors.white : Colors.white38,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 就地編輯影片備註：寫入 DB + 通知上層列表刷新。
  Future<void> _editVideoNote() async {
    final entry = widget.entry;
    if (entry == null) return;
    final newNote = await _showVideoNoteDialog(context, _note);
    if (newNote == null || !mounted) return;           // 取消
    if (newNote == (_note ?? '')) return;               // 未變更
    final updated = entry.copyWith(note: newNote);
    setState(() => _note = newNote);
    await RecordingHistoryStorage.instance.upsertEntry(updated);
    widget.onEntryUpdated?.call(entry, updated);
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(newNote.isEmpty ? l10n.playerNoteCleared : l10n.playerNoteSaved)),
      );
    }
  }

  /// 疊層開關列：骨架 / 軌跡 checkbox + 軌跡調參入口（從頂列移下來）
  Widget _buildOverlayToggles() {
    final l10n = AppLocalizations.of(context);
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
                activeColor: kBrandPrimary,
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
          // 左側 toggle 群在窄機橫向可捲，避免整列超寬溢出（黃黑條）；右側調參鈕固定。
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (_hasSkeletonCsv)
                    toggle(
                      label: l10n.playerOverlaySkeleton,
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
                      label: l10n.playerOverlayTrajectory,
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
                      label: l10n.playerOverlayEffect,
                      icon: Icons.auto_awesome,
                      value: _showImpactFx,
                      onChanged: (v) => setState(() => _showImpactFx = v),
                    ),
                  ],
                  if (_anchor != null) ...[
                    const SizedBox(width: 8),
                    toggle(
                      label: l10n.playerOverlayAnchor,
                      icon: Icons.gps_fixed,
                      value: _showAnchor,
                      onChanged: (v) => setState(() => _showAnchor = v),
                    ),
                  ],
                  // 骨架/影片時間差校正：疊圖落後→調大、超前→調小
                  if (_hasSkeletonCsv || _hasTrajectory)
                    IconButton(
                      tooltip: l10n.playerOverlaySync,
                      onPressed: _showOverlaySyncSheet,
                      icon: const Icon(Icons.sync_alt_rounded,
                          color: Colors.white54, size: 18),
                    ),
                ],
              ),
            ),
          ),
          // 球軌跡調參（排查用）：對本 clip 即時調參重跑（固定右側）
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
            label: Text(l10n.playerTrajectoryTuning,
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  /// 骨架/影片時間差校正：滑桿即時調整疊圖取樣補償（-200~600ms），存入偏好。
  void _showOverlaySyncSheet() {
    final l10n = AppLocalizations.of(context);
    int pending = (_overlayLeadSec * 1000).round();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: StatefulBuilder(builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
              child: Column(mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.sync_alt_rounded, color: kBrandPrimary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.playerOverlaySync,
                        style: const TextStyle(color: Colors.white, fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ),
                  Text('${pending}ms',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ]),
                const SizedBox(height: 4),
                Text(l10n.playerOverlaySyncDesc,
                    style: const TextStyle(color: Colors.white54, fontSize: 12)),
                Slider(
                  value: pending.toDouble().clamp(-200, 600),
                  min: -200, max: 600, divisions: 40,
                  activeColor: kBrandPrimary,
                  label: '${pending}ms',
                  onChanged: (v) {
                    setSheet(() => pending = v.round());
                    setState(() => _overlayLeadSec = pending / 1000.0);
                  },
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      setSheet(() => pending = SwingDetectPrefs.defaultOverlayLeadMs);
                      setState(() =>
                          _overlayLeadSec = SwingDetectPrefs.defaultOverlayLeadMs / 1000.0);
                    },
                    child: Text(l10n.clipCandReset,
                        style: const TextStyle(color: Colors.white54)),
                  ),
                ),
              ]),
            );
          }),
        );
      },
    ).whenComplete(() {
      unawaited(SwingDetectPrefs.setOverlayLeadMs((_overlayLeadSec * 1000).round()));
    });
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
            // 骨架疊圖：60Hz 播放頭取樣 CSV（offset=0，CSV 為 clip 相對時間）。
            // position listener 僅 ~2Hz，改用 _playheadSec 外插避免階梯跳動。
            if (_showSkeleton && _skeletonTrack != null)
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _playheadSec,
                  builder: (_, posSec, __) {
                    // 提前補償顯示延遲，對齊影片幀（見 _overlayLeadSec）
                    final pose = _skeletonTrack!.sampleAt(posSec + _overlayLeadSec);
                    if (pose == null) return const SizedBox.shrink();
                    return CustomPaint(
                      painter: SkeletonPainter(pose: pose),
                    );
                  },
                ),
              ),
            // 球軌跡疊圖：只畫 pts ≤ 播放位置的軌跡
            if (_showTrajectory && _trajTrack != null)
              Positioned.fill(
                child: ValueListenableBuilder<double>(
                  valueListenable: _playheadSec,
                  builder: (_, posSec, __) => CustomPaint(
                    painter: TrajectoryPainter(
                      track: _trajTrack!,
                      positionSec: posSec + _overlayLeadSec,
                    ),
                  ),
                ),
              ),
            // 擊球錨點標記（歸一化座標 → Align 對位，整段播放固定顯示）
            if (_showAnchor && _anchor != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: Alignment(_anchor!.$1 * 2 - 1, _anchor!.$2 * 2 - 1),
                    child: const AnchorMarker(),
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
                      centerNorm: _impactBallNorm(),
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

    final l10n = AppLocalizations.of(context);
    final timelinePhaseLabels = <String, String>{
      'address':       l10n.playerTimelineAbbrAddress,
      'takeaway':      l10n.playerTimelineAbbrTakeaway,
      'backswing':     l10n.playerTimelineAbbrBackswing,
      'top':           l10n.playerTimelineAbbrTop,
      'downswing':     l10n.playerTimelineAbbrDownswing,
      'impact':        l10n.playerTimelineAbbrImpact,
      'followthrough': l10n.playerTimelineAbbrFollowthrough,
      'finish':        l10n.playerTimelineAbbrFinish,
    };

    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 長影片：切片擊球時間點快速跳轉 ─────────────────────────
          if (_isLongVideo && _clipMarks.isNotEmpty)
            SizedBox(
              height: 30,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _clipMarks.length,
                itemBuilder: (_, i) {
                  final m = _clipMarks[i];
                  // 跳到擊球前 2 秒，方便看完整揮桿
                  final target = Duration(
                      milliseconds: ((m.sec - 2.0).clamp(0.0, durSec) * 1000).round());
                  final active = (posSec - m.sec).abs() < 2.5;
                  return GestureDetector(
                    onTap: () => ctrl.seekTo(target),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6, bottom: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFFFF8F00).withValues(alpha: 0.22)
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: active
                              ? const Color(0xFFFF8F00)
                              : Colors.white24,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        AppLocalizations.of(context).playerShotLabel(m.index, _fmt(Duration(milliseconds: (m.sec * 1000).round()))),
                        style: TextStyle(
                          color: active ? const Color(0xFFFF8F00) : Colors.white70,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          // ── 多模態時間軸（可雙指縮放 / 捲動 / 點擊 seek）─────────────
          // 切片擊球 tick 太密時可橫向拉寬分開（pinch 或 +/- 按鈕）
          ZoomableTimeline(
            height: 56,
            totalSeconds: durSec,
            currentSeconds: posSec,
            horizontalPadding: 20,
            onSeek: (sec) =>
                ctrl.seekTo(Duration(milliseconds: (sec * 1000).round())),
            painterBuilder: (w) => _MultiModalTimelinePainter(
              audioRms:      _chartData?.audioRms      ?? const [],
              wristSpeed:    _chartData?.wristSpeed    ?? const [],
              phases:        _phases                   ?? const {},
              hitSecond:     widget.entry?.hitSecond,
              clipMarks:     [for (final m in _clipMarks) m.sec],
              clipRanges:    _clipRanges,
              currentSecond: posSec,
              totalSeconds:  durSec,
              goodShot:      widget.entry?.goodShot,
              phaseLabels:   timelinePhaseLabels,
            ),
          ),
          // ── 剪輯邊界配色圖例（僅長影片有切片區間時顯示）──────────
          if (_isLongVideo && _clipRanges.isNotEmpty) ...[
            const SizedBox(height: 4),
            const ClipBoundaryLegend(),
          ],
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
                    color: kBrandPrimary,
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
                onTap: _toggleStats,
                child: Icon(
                  Icons.query_stats_rounded,
                  color: _statsExpanded
                      ? const Color(0xFFFFD21E)
                      : Colors.white54,
                  size: 24,
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _toggleCharts,
                child: AnimatedRotation(
                  turns: _chartsExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    Icons.bar_chart_rounded,
                    color: _chartsExpanded
                        ? kBrandPrimary
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
    final l10n = AppLocalizations.of(context);
    final phaseLabels = {
      'address':       l10n.playerPhaseAddress,
      'takeaway':      l10n.playerPhaseTakeaway,
      'backswing':     l10n.playerPhaseBackswing,
      'top':           l10n.playerPhaseTop,
      'downswing':     l10n.playerPhaseDownswing,
      'impact':        l10n.playerPhaseImpact,
      'followthrough': l10n.playerPhaseFollowthrough,
      'finish':        l10n.playerPhaseFinish,
    };
    final phases = _phases!;
    final ctrl   = _controller;
    final posSec = ctrl != null && ctrl.value.isInitialized
        ? ctrl.value.position.inMilliseconds / 1000.0
        : 0.0;

    // 計算當前播放位置對應的階段（高亮）
    String? currentPhase;
    for (int i = _phaseKeys.length - 1; i >= 0; i--) {
      final key = _phaseKeys[i];
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
        itemCount: _phaseKeys.length,
        itemBuilder: (context, index) {
          final key   = _phaseKeys[index];
          final label = phaseLabels[key] ?? key;
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
              : isActive ? kBrandPrimary.withValues(alpha: 0.18) : const Color(0xFF1A1A1A);
          final chipBorderColor = impactColor != null
              ? impactColor.withValues(alpha: 0.75)
              : isActive ? kBrandPrimary : Colors.white12;
          final chipBorderWidth = (impactColor != null || isActive) ? 1.5 : 1.0;
          final secColor = impactColor ?? (isActive ? kBrandPrimary : Colors.white60);
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

  // ── P1-P10 動作分析面板（讀 angles.json）────────────────────

  Widget _buildPSystemPanel() {
    final l10n = AppLocalizations.of(context);
    final ps = _pSystem!;
    return Container(
      color: const Color(0xFF101010),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(l10n.pSystemTitle,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              if (ps.overallScore != null)
                Text('${ps.overallScore!.round()}',
                    style: TextStyle(
                        color: _scoreColor(ps.overallScore),
                        fontSize: 12,
                        fontWeight: FontWeight.w800)),
              const Spacer(),
              if (ps.viewpoint != SwingViewpoint.faceOn)
                Flexible(
                  child: Text(l10n.pSystemViewpointWarn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white30, fontSize: 9)),
                ),
              // 切換：字母簡稱 P1…P10 ↔ 文字簡稱 預備/桿平上…
              GestureDetector(
                onTap: _togglePLabelStyle,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Icon(Icons.translate,
                      size: 16,
                      color: _pSysTextLabel ? kBrandPrimary : Colors.white38),
                ),
              ),
              // 說明頁入口
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PSystemHelpPage())),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8),
                  child: Icon(Icons.help_outline,
                      size: 16, color: Colors.white38),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildPSystemStrip(ps),
        ],
      ),
    );
  }

  /// 合併後的 P1-P10 條：點=seek（取代 8 階段條）、長按=開角度明細、播放位置高亮。
  Widget _buildPSystemStrip(PSystemMetrics ps) {
    final l10n = AppLocalizations.of(context);
    final ctrl = _controller;
    final posSec = ctrl != null && ctrl.value.isInitialized
        ? ctrl.value.position.inMilliseconds / 1000.0
        : 0.0;
    String? currentP;
    for (int i = PSystemMetrics.order.length - 1; i >= 0; i--) {
      final t = ps.pSec[PSystemMetrics.order[i]];
      if (t != null && posSec >= t - 0.05) {
        currentP = PSystemMetrics.order[i];
        break;
      }
    }
    return SizedBox(
      height: 42,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: PSystemMetrics.order.length,
        itemBuilder: (c, i) {
          final key = PSystemMetrics.order[i];
          final metrics = ps.perP[key] ?? const <BiomechMetric>[];
          final color = _scoreColor(_pScore(metrics));
          final sec = ps.pSec[key];
          final isActive = currentP == key;
          return GestureDetector(
            onTap: sec != null && ctrl != null
                ? () => ctrl.seekTo(Duration(milliseconds: (sec * 1000).round()))
                : null,
            onLongPress: () => _showPMetrics(key, metrics, sec),
            child: Container(
              width: _pSysTextLabel ? 48 : 40,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isActive ? 0.30 : 0.14),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: color.withValues(alpha: isActive ? 1.0 : 0.6),
                    width: isActive ? 1.5 : 1.0),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                      _pSysTextLabel ? _pLabel(l10n, key) : key.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: color,
                          fontSize: _pSysTextLabel ? 10 : 11,
                          fontWeight: FontWeight.w800)),
                  if (sec != null)
                    Text('${sec.toStringAsFixed(1)}s',
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 8)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPMetrics(String pKey, List<BiomechMetric> metrics, double? sec) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(pKey.toUpperCase(),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (sec != null)
                    TextButton.icon(
                      onPressed: () {
                        _controller?.seekTo(
                            Duration(milliseconds: (sec * 1000).round()));
                        Navigator.pop(c);
                      },
                      icon: const Icon(Icons.my_location, size: 16),
                      label: Text('${sec.toStringAsFixed(1)}s'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (metrics.isEmpty)
                Text(l10n.pSystemNoMetrics,
                    style: const TextStyle(color: Colors.white54))
              else
                ...metrics.map((m) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                                color: _gradeColor(m.grade),
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _metricName(l10n, m.key) +
                                  (m.beta ? ' (beta)' : ''),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 13),
                            ),
                          ),
                          Text(m.value != null ? _fmtVal(m) : '--',
                              style: TextStyle(
                                  color: _gradeColor(m.grade),
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  double? _pScore(List<BiomechMetric> metrics) {
    final v = <double>[];
    for (final m in metrics) {
      switch (m.grade) {
        case BiomechGrade.good:
          v.add(100);
          break;
        case BiomechGrade.warn:
          v.add(60);
          break;
        case BiomechGrade.bad:
          v.add(20);
          break;
        case BiomechGrade.unknown:
          break;
      }
    }
    return v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
  }

  Color _scoreColor(double? s) {
    if (s == null) return Colors.white30;
    if (s >= 80) return kGoodColor;
    if (s >= 50) return const Color(0xFFFFB74D);
    return const Color(0xFFE0584F);
  }

  Color _gradeColor(BiomechGrade g) {
    switch (g) {
      case BiomechGrade.good:
        return kGoodColor;
      case BiomechGrade.warn:
        return const Color(0xFFFFB74D);
      case BiomechGrade.bad:
        return const Color(0xFFE0584F);
      case BiomechGrade.unknown:
        return Colors.white30;
    }
  }

  void _togglePLabelStyle() {
    setState(() => _pSysTextLabel = !_pSysTextLabel);
    SwingDetectPrefs.setPSystemTextLabel(_pSysTextLabel);
  }

  String _pLabel(AppLocalizations l, String key) {
    switch (key) {
      case 'p1': return l.pLabelP1;
      case 'p2': return l.pLabelP2;
      case 'p3': return l.pLabelP3;
      case 'p4': return l.pLabelP4;
      case 'p5': return l.pLabelP5;
      case 'p6': return l.pLabelP6;
      case 'p7': return l.pLabelP7;
      case 'p8': return l.pLabelP8;
      case 'p9': return l.pLabelP9;
      case 'p10': return l.pLabelP10;
      default: return key.toUpperCase();
    }
  }

  String _metricName(AppLocalizations l, String key) {
    switch (key) {
      case 'spine_tilt':
        return l.metricSpineTilt;
      case 'head_move':
        return l.metricHeadMove;
      case 'x_factor':
        return l.metricXFactor;
      case 'weight_shift':
        return l.metricWeightShift;
      default:
        return key;
    }
  }

  String _fmtVal(BiomechMetric m) {
    final v = m.value!;
    if (m.unit == 'deg') return '${v.toStringAsFixed(0)}°';
    if (m.unit == 'norm') return v.toStringAsFixed(3);
    return v.toStringAsFixed(2);
  }

  // ── 揮桿統計面板（發射角 / 節奏 / 飛行時間）────────────────────

  Widget _buildStatsPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      height: _statsExpanded ? 96 : 0,
      color: const Color(0xFF121212),
      child: ClipRect(child: _buildStatsContent()),
    );
  }

  Widget _buildStatsContent() {
    final l10n = AppLocalizations.of(context);
    final stats = SwingStats.compute(track: _trajTrack, phases: _phases);
    if (stats.isEmpty) {
      return Center(
        child: Text(l10n.playerStatsEmpty,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    Widget stat(String label, String value, {Color? color}) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(value,
                style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
      );
    }

    // 節奏比顯著偏離 3:1 時提示色（職業選手約 3.0，2.5-3.5 視為理想區間）
    Color? tempoColor;
    if (stats.tempoRatio != null) {
      final t = stats.tempoRatio!;
      tempoColor = (t >= 2.5 && t <= 3.5)
          ? kGoodColor
          : const Color(0xFFFFB74D);
    }

    return Row(
      children: [
        stat(
          l10n.playerStatLaunchAngle,
          stats.launchAngleDeg != null
              ? '${stats.launchAngleDeg!.toStringAsFixed(1)}°'
              : '--',
          color: const Color(0xFFFFD21E),
        ),
        stat(
          l10n.playerStatTempo,
          stats.tempoRatio != null
              ? '${stats.tempoRatio!.toStringAsFixed(1)} : 1${stats.tempoConfident ? '' : ' ?'}'
              : '--',
          color: tempoColor,
        ),
        stat(
          l10n.playerStatBackDownswing,
          (stats.backswingSec != null && stats.downswingSec != null)
              ? '${stats.backswingSec!.toStringAsFixed(2)}s / ${stats.downswingSec!.toStringAsFixed(2)}s'
              : '--',
        ),
        stat(
          l10n.playerStatFlightTime,
          stats.flightTimeSec != null
              ? '${stats.flightTimeSec!.toStringAsFixed(2)}s'
              : '--',
        ),
      ],
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
        child: CircularProgressIndicator(color: kBrandPrimary, strokeWidth: 2),
      );
    }
    final data = _chartData;
    if (data == null || data.isEmpty) {
      return Center(
        child: Text(AppLocalizations.of(context).playerChartEmpty,
            style: const TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }

    final l10n = AppLocalizations.of(context);

    // ── 前 3 個 tab：時序折線圖資料 ────────────────────────
    List<ChartPoint>? activePoints;
    final chartTabLabels = [
      l10n.playerChartTabAudio,
      l10n.playerChartTabWristY,
      l10n.playerChartTabSpeed,
      l10n.playerChartTabPosture,
      l10n.playerChartTabAudioFeature,
    ];
    Color activeColor = _chartTabColors[_chartTabIndex];
    bool invertY = false;
    String Function(double)? yLabel;
    String emptyLabel = l10n.playerChartNoData;

    if (_chartTabIndex == 0) {
      activePoints = data.audioRms;
      invertY      = false;
      yLabel       = (v) => '${v.toStringAsFixed(0)}dB';
      emptyLabel   = l10n.playerChartAudioEmpty;
    } else if (_chartTabIndex == 1) {
      activePoints = data.wristY;
      invertY      = true;
      yLabel       = (v) => '${v.toStringAsFixed(0)}px';
      emptyLabel   = l10n.playerChartWristYEmpty;
    } else if (_chartTabIndex == 2) {
      activePoints = data.wristSpeed;
      invertY      = false;
      yLabel       = (v) => v.toStringAsFixed(0);
      emptyLabel   = l10n.playerChartSpeedEmpty;
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
              children: List.generate(_chartTabColors.length, (i) {
                final tabColor = _chartTabColors[i];
                final tabLabel = chartTabLabels[i];
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
                          color: selected ? tabColor : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                    child: Text(
                      tabLabel,
                      style: TextStyle(
                        color: selected ? tabColor : Colors.white38,
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
              label: Text(AppLocalizations.of(context).playerLoadDetailScore, style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6)),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Text(AppLocalizations.of(context).playerPostureEmpty,
          style: const TextStyle(color: Colors.white38, fontSize: 12)),
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
                hasData ? AppLocalizations.of(context).playerAudioPassCount(passCount) : AppLocalizations.of(context).playerAudioEmpty,
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

    final l10n = AppLocalizations.of(context);

    // 尚無分析
    if (status == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.psychology_rounded,
                color: Color(0xFF7C3AED), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l10n.playerAiNotStarted,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
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
                    child: Text(l10n.playerAiStartAnalysis,
                        style: const TextStyle(fontSize: 13)),
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
              child: Text(_aiStatusLabel(status.status, l10n),
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
              child: Text(l10n.playerAiViewProgress,
                  style: const TextStyle(fontSize: 13)),
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
              Expanded(
                child: Text(l10n.playerAiCoachTitle,
                    style: const TextStyle(
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
                  child: Text(_severityLabel(status.severity!, l10n),
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
              _aiSectionTitle(l10n.playerAiPrimaryIssue),
              const SizedBox(height: 4),
              _aiTag(result.primaryError.zhName, sevColor),
              if (result.primaryError.evidence.isNotEmpty)
                ...result.primaryError.evidence.map((e) => _aiBullet(e)),
            ],
            // 教練評語
            if (result.coachFeedback.isNotEmpty) ...[
              const SizedBox(height: 10),
              _aiSectionTitle(l10n.playerAiCoachFeedback),
              const SizedBox(height: 4),
              ...result.coachFeedback.map((f) => _aiBullet(f)),
            ],
            // 訓練建議
            if (result.practiceSuggestions.isNotEmpty) ...[
              const SizedBox(height: 10),
              _aiSectionTitle(l10n.playerAiPracticeSuggestions),
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
              _aiSectionTitle(l10n.playerAiNextGoal),
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
                child: Text(l10n.playerAiReanalyze),
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
                child: Text(l10n.playerAiViewDetail),
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

  String _aiStatusLabel(String s, AppLocalizations l10n) => switch (s) {
    'pending'    => l10n.playerAiStatusPending,
    'queued'     => l10n.playerAiStatusQueued,
    'processing' => l10n.playerAiStatusProcessing,
    _            => l10n.playerAiStatusAnalyzing,
  };

  Color _severityColor(String s) => switch (s) {
    'high'   => kBadColor,
    'medium' => kCrispColor,
    _        => kGoodColor,
  };

  String _severityLabel(String s, AppLocalizations l10n) => switch (s) {
    'high'   => l10n.playerSeverityHigh,
    'medium' => l10n.playerSeverityMedium,
    _        => l10n.playerSeverityLow,
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
                  Text(AppLocalizations.of(context).playerHighlightPreview,
                      style: const TextStyle(color: Colors.white70, fontSize: 14)),
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
              activeTrackColor: kBrandPrimary,
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
                    color: kBrandPrimary,
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
  final Offset? centerNorm; // 球位（display 正規化 0~1）；null 時退預設比例

  const _SweetSpotRingPainter({
    required this.progress,
    required this.goodShot,
    required this.passCount,
    this.centerNorm,
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
    final center = centerNorm != null
        ? Offset(size.width * centerNorm!.dx, size.height * centerNorm!.dy)
        : Offset(size.width * 0.5194, size.height * 0.8469);

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
      old.progress != progress ||
      old.goodShot != goodShot ||
      old.passCount != passCount ||
      old.centerNorm != centerNorm;
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

    final l10n = AppLocalizations.of(context);

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
      title = l10n.playerSweetSpotHit;
      icon  = Icons.star_rounded;
    } else if (goodShot!) {
      color = const Color(0xFF90CAF9);
      title = l10n.playerSweetSpot;
      icon  = Icons.check_circle_rounded;
    } else {
      color = const Color(0xFF9E9E9E);
      title = l10n.playerThinShot;
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
                  Text(l10n.playerAudioPassCountBadge(passCount),
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
  /// 長影片：已切片段的擊球時刻（秒，原始影片座標）
  final List<double> clipMarks;
  /// 長影片：已切片段的剪輯起迄區間（秒，原始影片座標）—— 綠=開始、紅=結束
  final List<({double start, double end})> clipRanges;
  final double currentSecond;
  final double totalSeconds;
  final bool? goodShot;
  /// 階段單字縮寫標籤（由 build() 傳入，已本地化）。
  final Map<String, String> phaseLabels;

  // Flutter Slider 內部 track 兩側的 horizontal padding（固定 20px）
  static const double _hPad = 20.0;

  const _MultiModalTimelinePainter({
    required this.audioRms,
    required this.wristSpeed,
    required this.phases,
    this.hitSecond,
    this.clipMarks = const [],
    this.clipRanges = const [],
    required this.currentSecond,
    required this.totalSeconds,
    this.goodShot,
    this.phaseLabels = const {},
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

    // ── 層1b：每 30 秒時間刻度 + 標籤（縮放時定位參考）──────────
    if (totalSeconds > 30) {
      final markPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.16)
        ..strokeWidth = 1;
      for (var s = 30.0; s < totalSeconds; s += 30) {
        final x = _secToX(s, trackW);
        canvas.drawLine(Offset(x, 2), Offset(x, size.height - 2), markPaint);
        final mm = s ~/ 60, ss = (s % 60).toInt();
        final tp = TextPainter(
          text: TextSpan(
            text: '$mm:${ss.toString().padLeft(2, '0')}',
            style: const TextStyle(color: Colors.white38, fontSize: 8),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x + 2, 1));
      }
    }

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

      final paintPlayed = Paint()..color = kBrandPrimary.withValues(alpha: 0.80);
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
        final label = phaseLabels[e.key] ?? '';
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

    // ── 層5b：切片擊球時刻標記（長影片，橙色 tick + 小鑽石）──────
    for (final sec in clipMarks) {
      if (sec < 0 || sec > totalSeconds) continue;
      final x = _secToX(sec, trackW);
      canvas.drawLine(
        Offset(x, size.height * 0.16),
        Offset(x, size.height * 0.84),
        Paint()
          ..color       = const Color(0xFFFF8F00).withValues(alpha: 0.75)
          ..strokeWidth = 1.5,
      );
      const r = 3.5;
      final cy = size.height * 0.16;
      final diamond = Path()
        ..moveTo(x,           cy - r)
        ..lineTo(x + r * 0.7, cy)
        ..lineTo(x,           cy + r)
        ..lineTo(x - r * 0.7, cy)
        ..close();
      canvas.drawPath(diamond, Paint()..color = const Color(0xFFFF8F00));
    }

    // ── 層5c：切片剪輯起迄邊界（綠=開始、紅=結束）────────────────
    for (final r in clipRanges) {
      _drawBoundary(canvas, size, trackW, r.start, kClipStartColor, true);
      _drawBoundary(canvas, size, trackW, r.end,   kClipEndColor, false);
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

  /// 剪輯邊界標記：細色線 + 頂部朝內小三角（start 朝右、end 朝左）。
  void _drawBoundary(
    Canvas canvas, Size size, double trackW, double sec, Color color, bool isStart) {
    if (sec < 0 || sec > totalSeconds) return;
    final x = _secToX(sec, trackW);
    canvas.drawLine(
      Offset(x, size.height * 0.10),
      Offset(x, size.height * 0.90),
      Paint()
        ..color       = color.withValues(alpha: 0.65)
        ..strokeWidth = 1.2,
    );
    final ty  = size.height * 0.10;
    final dir = isStart ? 1.0 : -1.0;
    final tri = Path()
      ..moveTo(x, ty)
      ..lineTo(x + dir * 4, ty)
      ..lineTo(x, ty + 4)
      ..close();
    canvas.drawPath(tri, Paint()..color = color);
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
      old.clipMarks     != clipMarks     ||
      old.clipRanges    != clipRanges    ||
      old.goodShot      != goodShot      ||
      old.phaseLabels   != phaseLabels;
}

/// 影片查看頁的備註編輯對話框（與 recording_history_page 同款式）。
/// 回傳 null = 取消；'' = 清除備註；其餘為新備註內容。
Future<String?> _showVideoNoteDialog(BuildContext context, String? initial) {
  final l10n = AppLocalizations.of(context);
  String tempNote = initial ?? '';
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.playerNoteDialogTitle),
      content: TextField(
        controller: TextEditingController(text: initial ?? ''),
        maxLength: 200,
        maxLines: 4,
        minLines: 2,
        autofocus: true,
        decoration: InputDecoration(
          hintText: l10n.playerNoteHint,
          helperText: l10n.playerNoteHelper,
          border: const OutlineInputBorder(),
        ),
        onChanged: (v) => tempNote = v,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(tempNote.trim()),
          child: Text(l10n.commonSave),
        ),
      ],
    ),
  );
}
