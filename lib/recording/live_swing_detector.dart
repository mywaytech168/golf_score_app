import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'pose_result.dart';

enum SwingDetectState {
  calibrating, // 前幾秒校準基線
  listening,   // 偵測中
  triggered,   // 速度峰值後等待確認
  fired,       // 已觸發，冷卻中
}

/// 即時腕點遙測（除錯 HUD 用）：左右腕的垂直位置與速度（歸一化）。
/// null = 該禎腕點不可見。
class SwingTelemetry {
  final double? leftY, rightY;     // 垂直位置（影像 y，0-1，越大越低）
  final double leftSpeed, rightSpeed; // 速度（歸一化位移/幀）
  const SwingTelemetry({
    this.leftY, this.rightY,
    this.leftSpeed = 0, this.rightSpeed = 0,
  });
  static const zero = SwingTelemetry();
}

/// 即時滾動視窗揮桿偵測器（使用 MediaPipe 歸一化座標）。
///
/// 每禎呼叫 [feed]，偵測到撞擊時呼叫 [onImpact]（傳入 impactTimeSec）。
///
/// 速度以歸一化單位計算（0-1 / frame），threshold 對應像素速度：
///   minThreshold = 0.005 ≈ 2px @ 400px 分析幀寬
class LiveSwingDetector {
  final double calibrationSec;
  final double cooldownSec;
  final double postImpactBufferSec;
  final void Function(double impactTimeSec)? onImpact;

  /// 雙手判斷（嚴格）：開啟時，本次揮桿須曾出現「一禎雙手都可見、且兩手都達揮桿
  /// 速度門檻、兩腕夠近」才記錄為揮桿；其中一手被遮擋的禎不計入，全程遮擋則不記錄
  /// （不再退回單手）。關閉時維持單手主導（取速度較大者）。可即時切換。
  bool bothHands;

  /// 擊球錨點（歸一化 0-1，使用者點選預覽畫面的球位置）。設定後，擊球判定改為
  /// 「下桿時主導腕回到此錨點最近的那一幀」（比手腕弧底更貼近桿頭觸球）；
  /// 未設定（null）則沿用手腕垂直位置最低點（弧底）。準備點＝擊球點＝同一點。
  double? anchorX, anchorY;
  bool get hasAnchor => anchorX != null && anchorY != null;

  /// V4：擊球「時刻」用錨點（手回到錨點最近那一幀）；false = V1 手腕弧底。可即時切換。
  bool useAnchorHit = false;

  /// 錨點偵測「閘門」：開啟時，揮桿過程中主導腕須曾進入錨點半徑內才算一桿；
  /// 沒經過（亂揮/錨點點歪）→ 不記錄。與 [useAnchorHit] 獨立。可即時切換。
  bool anchorGate = false;

  /// 擊球時刻是否採錨點（V4）：需同時開啟 useAnchorHit 且已設座標。
  bool get _anchorHit => useAnchorHit && hasAnchor;

  /// 錨點命中半徑（歸一化）：主導腕回歸需逼近到「距錨點 ≤ 此半徑」才認定為錨點擊球；
  /// 不夠近則不採錨點、退回手腕弧底/峰值。調小＝要求更貼近錨點（更嚴）、調大＝更寬鬆。
  /// 可即時切換。預設 0.50（寬鬆）：錨點多點在球上、偵測追手腕，觸球時手腕離球約
  /// 一個桿身，門檻太緊會把正常揮桿全擋掉。
  double anchorHitRadius = 0.50;

  /// 即時腕點遙測（左右腕 Y + 速度），供除錯 HUD 監看。每禎更新。
  final ValueNotifier<SwingTelemetry> telemetry =
      ValueNotifier<SwingTelemetry>(SwingTelemetry.zero);

  /// 雙手判斷時，兩腕「夠近＝握在同一支桿上」的最大歸一化距離。
  /// ADB 實錄真雙手揮桿擊球禎兩腕距離 p50=0.20、p90=0.30；單手揮桿另一手在身側則遠。
  /// 用來擋「單手揮但身體旋轉讓閒置手也達速度門檻」的誤判。
  static const double _maxWristGap = 0.35;

  /// 揮桿速度門檻（**絕對**歸一化位移/幀，可調）。動態 thr 安靜期會掉到地板 0.012，
  /// thr×1.5≈0.018 形同虛設，讓 waggle/走路擺臂/彎腰撿球等中速動作誤判成擊球。
  /// ADB 實錄 24 真桿峰值最小 0.209、p10 0.243 → 預設 0.15 留 ~28% 裕度（真桿 0 漏失）。
  /// 雙手判斷下快手須達此速度、慢手達 ×0.4。可即時切換（設定滑桿 0.05~0.30）。
  double swingSpeedFloor = 0.15;

  static const int _bufSize = 60;
  final _speedBuf = Queue<double>();

  SwingDetectState _state = SwingDetectState.calibrating;
  double _calibrationEndTime = 0;
  double _cooldownEndTime    = 0;

  double _peakSpeed    = 0;
  double _peakTimeSec  = 0;
  int    _fallFrames   = 0;
  // 速度 fallback 的回落確認幀數。調大讓「位置弧底」優先開火（弧底在峰值後幾幀，
  // 需先讓手腕真正到底+上升確認），避免速度跌得快時 fallback 搶在峰值時刻開火（偏早）。
  static const int _minFallFrames = 6;

  double? _prevRx, _prevRy;
  double? _prevLx, _prevLy;

  // 弧線底部（觸球）偵測：鎖定峰值當下的主導腕，找其垂直「位置」最低點（影像 y 最大）。
  // 改用位置 Y 最小值 + 窗確認（取代速度過零）：速度是逐幀差分、單幀雜訊會讓 dy 瞬間
  // 翻負而提早誤觸；改追「位置到底、且連續上升 N 幀才確認」較穩，回報的擊球時刻為
  // 真正最低點那一幀（_bottomTimeSec），而非偵測當下。
  bool    _peakDomLeft = false; // 峰值時主導腕是否為左腕
  bool    _sawDownward = false; // 本次揮桿是否已觀察到向下運動（弧底模式閘門）
  bool    _anchorDeparted = false; // 錨點模式：手是否已離開錨點（才接受回歸判定）
  bool    _anchorReturning = false; // 錨點模式：離開後是否已開始朝錨點逼近
  double? _prevAnchorDist;          // 上一幀到錨點距離（判斷逼近/遠離）
  static const double _anchorDepartDist = 0.15; // 視為「已離開錨點」的距離（歸一化）
  // depth = 越大越接近擊球：無錨點時 = 主導腕影像 y（最低點）；有錨點時 = −到錨點距離。
  double? _bottomDepth;         // 本次下桿觀察到的最大 depth（最接近擊球）
  double  _bottomTimeSec = 0;   // 最大 depth 那一幀的時刻 → 擊球時刻
  int     _riseFrames = 0;      // 從最大 depth 起連續「遠離」的幀數（窗確認）
  static const int    _bottomConfirmFrames = 2;     // 連續上升幾幀才確認過底（防單幀雜訊）
  static const double _riseEps = 0.003;             // 視為「上升」的最小幅度（歸一化）

  // 雙手確認（窗內 + 握桿模式）：以「兩腕曾經很近（握同桿）」為主訊號，因 ADB 實錄
  // 顯示真實雙手揮桿兩腕投影常貼在一起（最近腕距 0.01~0.14），而「兩手各自速度都達
  // 門檻」不可靠（後手腕被遮擋/抖動，速度算不到門檻 → 漏真桿）。判定＝兩腕曾近 +
  // 快手達門檻 + 慢手達門檻×factor（排除一手全靜止/遮擋＝maxSpeed≈0）。
  double _maxRSpeed = 0, _maxLSpeed = 0; // 本次揮桿左右腕各自最大速度（窗內）
  bool _bothCloseSeen     = false;
  double _minWristGap     = double.infinity; // 本次揮桿兩腕最近距離（診斷用）
  // 慢手相對門檻的最低比例：證明第二手「有跟著動」而非靜止/遮擋（非要求同樣快）。
  static const double _secondHandFactor = 0.4;

  // 錨點偵測閘門：本次揮桿主導腕是否曾進入錨點半徑內
  bool _anchorReachedRadius = false;

  /// 錨點閘門裁定：關閉/無錨點 → 永遠通過；開啟 → 須曾進入錨點半徑內。
  bool get _anchorGatePass => !anchorGate || !hasAnchor || _anchorReachedRadius;

  LiveSwingDetector({
    this.calibrationSec      = 3.0,
    this.cooldownSec         = 5.0,
    this.postImpactBufferSec = 2.5,
    this.bothHands           = false,
    this.onImpact,
  });

  SwingDetectState get state => _state;

  void reset() {
    _speedBuf.clear();
    _state             = SwingDetectState.calibrating;
    _calibrationEndTime = 0;
    _cooldownEndTime   = 0;
    _peakSpeed         = 0;
    _peakTimeSec       = 0;
    _fallFrames        = 0;
    _prevRx            = null;
    _prevRy            = null;
    _prevLx            = null;
    _prevLy            = null;
    _resetArc();
  }

  /// 清除弧線底部偵測狀態（每次開火 / 回到 listening 時呼叫）。
  void _resetArc() {
    _sawDownward = false;
    _anchorDeparted = false;
    _anchorReturning = false;
    _prevAnchorDist = null;
    _bottomDepth = null;
    _riseFrames  = 0;
    _maxRSpeed = 0;
    _maxLSpeed = 0;
    _bothCloseSeen     = false;
    _minWristGap       = double.infinity;
    _anchorReachedRadius = false;
  }

  /// 喂入一禎姿勢資料（MediaPipe NativePoseResult）。
  ///
  /// [pose]    MediaPipe 結果（歸一化座標 0-1）
  /// [timeSec] 相對錄製開始的秒數
  void feed(NativePoseResult pose, double timeSec) {
    // 雙腕都追蹤、取速度較大者：左打者主導腕為左腕，只看右腕會鈍化偵測
    double rSpeed = 0.0, lSpeed = 0.0;
    double? rDy, lDy; // 帶正負號的垂直速度（影像 y 向下為正），null = 該禎腕點無效
    double? rY, lY;   // 本禎腕點垂直位置（影像 y 向下為正），null = 不可見
    double? rX, lX;   // 本禎腕點水平位置（歸一化），錨點距離用
    bool rValid = false, lValid = false; // 本禎腕點是否有效（可見且有上一禎可算速度）
    final rw = pose.rightWrist;
    if (rw != null && rw.visibility >= 0.1) {
      rY = rw.y;
      rX = rw.x;
      if (_prevRx != null) {
        final dx = rw.x - _prevRx!;
        final dy = rw.y - _prevRy!;
        rSpeed = math.sqrt(dx * dx + dy * dy);
        rDy = dy;
        rValid = true;
      }
      _prevRx = rw.x;
      _prevRy = rw.y;
    }
    final lw = pose.leftWrist;
    if (lw != null && lw.visibility >= 0.1) {
      lY = lw.y;
      lX = lw.x;
      if (_prevLx != null) {
        final dx = lw.x - _prevLx!;
        final dy = lw.y - _prevLy!;
        lSpeed = math.sqrt(dx * dx + dy * dy);
        lDy = dy;
        lValid = true;
      }
      _prevLx = lw.x;
      _prevLy = lw.y;
    }
    final speed   = math.max(rSpeed, lSpeed);
    final domLeft = lSpeed > rSpeed;        // 本禎主導腕
    final domDy   = domLeft ? lDy : rDy;    // 主導腕垂直速度（可能 null）

    // 兩腕距離（歸一化）：雙手握在桿上時很近；單手揮桿另一手在身側則遠。
    // 雙手判斷用來擋「單手揮但身體旋轉讓閒置手也動」的誤判。null = 任一手不可見。
    double? wristGap;
    if (rw != null && rw.visibility >= 0.1 && lw != null && lw.visibility >= 0.1) {
      final dgx = rw.x - lw.x, dgy = rw.y - lw.y;
      wristGap = math.sqrt(dgx * dgx + dgy * dgy);
    }

    // 即時遙測（除錯 HUD）：每禎回報左右腕 Y + 速度
    telemetry.value = SwingTelemetry(
      leftY: lY, rightY: rY, leftSpeed: lSpeed, rightSpeed: rSpeed,
    );

    _speedBuf.addLast(speed);
    if (_speedBuf.length > _bufSize) _speedBuf.removeFirst();

    // 校準期
    if (_state == SwingDetectState.calibrating) {
      if (_calibrationEndTime == 0) _calibrationEndTime = timeSec + calibrationSec;
      if (timeSec < _calibrationEndTime) return;
      _state = SwingDetectState.listening;
      debugPrint('[LiveSwing] 校準完成 → 開始偵測');
    }

    // 冷卻期
    if (_state == SwingDetectState.fired) {
      if (timeSec < _cooldownEndTime) return;
      _state     = SwingDetectState.listening;
      _peakSpeed = 0;
      _fallFrames = 0;
    }

    if (_state != SwingDetectState.listening &&
        _state != SwingDetectState.triggered) {
      return;
    }

    final thr = _threshold();

    if (_state == SwingDetectState.listening) {
      if (speed > thr) {
        _state       = SwingDetectState.triggered;
        _peakSpeed   = speed;
        _peakTimeSec = timeSec;
        _fallFrames  = 0;
        _peakDomLeft = domLeft;
        // 起手禎即初始化弧線偵測狀態
        _sawDownward = domDy != null && domDy > 0;
        _anchorDeparted = false;
        _anchorReturning = false;
        _prevAnchorDist = null;
        // 雙手確認：起手禎即開始累計
        _trackBothHands(rValid, lValid, rSpeed, lSpeed, wristGap);
      }
    } else {
      // 雙手確認：累計本次揮桿期間各手是否曾出現 / 曾達門檻
      _trackBothHands(rValid, lValid, rSpeed, lSpeed, wristGap);

      // 錨點閘門：累計本禎主導腕是否曾進入錨點半徑內（與擊球時刻方法獨立）
      if (anchorGate && hasAnchor) {
        final cx = domLeft ? lX : rX, cy = domLeft ? lY : rY;
        if (cx != null && cy != null) {
          final gx = cx - anchorX!, gy = cy - anchorY!;
          if (math.sqrt(gx * gx + gy * gy) <= anchorHitRadius) {
            _anchorReachedRadius = true;
          }
        }
      }

      // --- 峰值追蹤（含 fallback 回落計數）---
      if (speed >= _peakSpeed) {
        _peakSpeed   = speed;
        _peakTimeSec = timeSec;
        _fallFrames  = 0;
        _peakDomLeft = domLeft;
      } else if (speed < _peakSpeed * 0.80) {
        _fallFrames++;
      } else if (speed < thr * 0.35) {
        _state     = SwingDetectState.listening;
        _peakSpeed = 0;
        _fallFrames = 0;
        _resetArc();
        return;
      }

      // --- 擊球瞬間偵測（depth 最大 + 窗確認）= 觸球瞬間 ---
      // depth 越大越接近擊球：有錨點 → −到錨點距離（手回到球位最近）；
      // 無錨點 → 主導腕影像 y（手腕弧線最低點）。追 max depth、連續遠離 N 幀才確認，
      // 回報 max depth 那一幀；比速度過零更不怕單幀雜訊提早誤觸。
      final dy   = _peakDomLeft ? lDy : rDy;
      final domY = _peakDomLeft ? lY  : rY;
      final domX = _peakDomLeft ? lX  : rX;
      if (dy != null && dy > 0) _sawDownward = true;
      double? depth;
      if (_anchorHit) {
        if (domX != null && domY != null) {
          final ex = domX - anchorX!, ey = domY - anchorY!;
          final dist = math.sqrt(ex * ex + ey * ey);
          // 手已離開錨點（上桿）後，開始朝錨點逼近（dist 縮小）即視為「回歸中」。
          // 這條路徑不依賴向下運動，涵蓋純水平/平揮——即原本被 _sawDownward 擋掉的邊際漏洞。
          if (dist > _anchorDepartDist) _anchorDeparted = true;
          if (_anchorDeparted && _prevAnchorDist != null &&
              dist < _prevAnchorDist! - _riseEps) {
            _anchorReturning = true;
          }
          _prevAnchorDist = dist;
          depth = -dist; // 越近錨點 → depth 越大（越接近 0）
        }
      } else {
        depth = domY;
      }
      // 弧底模式以「曾向下」為閘門；錨點模式另接受「離開後回歸中」（修平揮漏洞）。
      final gateOpen =
          _anchorHit ? (_sawDownward || _anchorReturning) : _sawDownward;
      if (gateOpen && depth != null) {
        if (_bottomDepth == null || depth > _bottomDepth!) {
          // 刷新「最接近擊球」（depth 更大）
          _bottomDepth   = depth;
          _bottomTimeSec = timeSec;
          _riseFrames    = 0;
        } else if (depth < _bottomDepth! - _riseEps) {
          // 開始遠離 → 累計確認幀
          _riseFrames++;
          final fireFloor = math.max(thr * 1.5, swingSpeedFloor);
          // 錨點時刻模式：最近距離（=−_bottomDepth）須在命中半徑內，否則不採此路徑開火
          final anchorClose =
              !_anchorHit || (_bottomDepth! >= -anchorHitRadius);
          if (_riseFrames >= _bottomConfirmFrames &&
              _peakSpeed >= fireFloor &&
              anchorClose &&
              _anchorGatePass &&
              _bothConfirmed()) {
            _state          = SwingDetectState.fired;
            _cooldownEndTime = timeSec + cooldownSec;
            debugPrint('[LiveSwing] ✅ 撞擊（${_anchorHit ? "錨點" : "位置弧底"}）t=${_bottomTimeSec.toStringAsFixed(2)}s '
                'peak=${_peakSpeed.toStringAsFixed(4)} thr=${thr.toStringAsFixed(4)}'
                '${_anchorHit ? " dist=${(-_bottomDepth!).toStringAsFixed(3)} r=${anchorHitRadius.toStringAsFixed(2)}" : ""}'
                '${anchorGate ? " gate=on" : ""}');
            final hitT = _bottomTimeSec;
            _resetArc();
            onImpact?.call(hitT);
            return;
          }
        }
      }

      // --- fallback：回落已確認但未抓到垂直反轉（純水平揮桿）→ 退回峰值時刻 ---
      if (_fallFrames >= _minFallFrames) {
        // 邊際峰值（< max(thr×1.5, 絕對下限)）或雙手判斷未確認（單手動作）→ 視為誤觸，不開火
        final fireFloor = math.max(thr * 1.5, swingSpeedFloor);
        // 速度不足／單手／錨點閘門未通過（揮桿未經過錨點）→ 視為誤觸，不開火
        if (_peakSpeed < fireFloor || !_bothConfirmed() || !_anchorGatePass) {
          debugPrint('[LiveSwing] 忽略（速度不足或單手或未過錨點）peak=${_peakSpeed.toStringAsFixed(4)} '
              'floor=${fireFloor.toStringAsFixed(4)} bothOK=${_bothConfirmed()} '
              'gateOK=$_anchorGatePass'
              '${bothHands ? " [R速=${_maxRSpeed.toStringAsFixed(3)} L速=${_maxLSpeed.toStringAsFixed(3)} floor=${swingSpeedFloor.toStringAsFixed(2)}(慢手須≥${(swingSpeedFloor * _secondHandFactor).toStringAsFixed(2)}) 兩腕曾近=$_bothCloseSeen 最近腕距=${_minWristGap == double.infinity ? "—" : _minWristGap.toStringAsFixed(2)}]" : ""}');
          _state      = SwingDetectState.listening;
          _peakSpeed  = 0;
          _fallFrames = 0;
          _resetArc();
          return;
        }
        _state          = SwingDetectState.fired;
        _cooldownEndTime = timeSec + cooldownSec;
        // 有追蹤到弧底（曾向下）→ 回報弧底時刻（晚於峰值、近觸球）；純水平揮桿無弧底→退回峰值。
        // 錨點模式若最近距離超出命中半徑（手沒真的回到錨點）→ 不採錨點時刻，退回峰值。
        final anchorClose =
            _bottomDepth != null && (!_anchorHit || _bottomDepth! >= -anchorHitRadius);
        final hitT = anchorClose ? _bottomTimeSec : _peakTimeSec;
        final src  = anchorClose ? (_anchorHit ? '錨點' : '弧底') : '峰值';
        debugPrint('[LiveSwing] ✅ 撞擊（fallback/$src）t=${hitT.toStringAsFixed(2)}s '
            'peak=${_peakSpeed.toStringAsFixed(4)} thr=${thr.toStringAsFixed(4)}'
            '${_anchorHit && _bottomDepth != null ? " dist=${(-_bottomDepth!).toStringAsFixed(3)} r=${anchorHitRadius.toStringAsFixed(2)}" : ""}'
            '${anchorGate ? " gate=on" : ""}');
        _resetArc();
        onImpact?.call(hitT);
      }
    }
  }

  /// 累計（窗內）：本次揮桿過程中——
  ///   ・左右手「各自」是否曾達揮桿速度門檻（swingSpeedFloor，不必同一禎）；
  ///   ・是否曾有一禎兩腕都可見且夠近（握在同一支桿上）。
  /// 其中一手被遮擋（不可見）的禎不計入該手達標 → 全程遮擋則該手永不達標 → 不記錄。
  void _trackBothHands(bool rValid, bool lValid, double rSpeed, double lSpeed,
      double? wristGap) {
    if (!bothHands) return;
    if (rValid && rSpeed > _maxRSpeed) _maxRSpeed = rSpeed;
    if (lValid && lSpeed > _maxLSpeed) _maxLSpeed = lSpeed;
    if (rValid && lValid && wristGap != null) {
      if (wristGap < _minWristGap) _minWristGap = wristGap; // 診斷：記最近腕距
      if (wristGap <= _maxWristGap) _bothCloseSeen = true;
    }
  }

  /// 雙手判斷裁定（開火前呼叫，窗內＋握桿模式）：
  ///   ・關閉 → 永遠通過（單手主導，維持舊行為）
  ///   ・開啟 → 兩腕曾近（握同桿）＋快手達門檻＋慢手達門檻×factor（證明跟著動，非靜止/遮擋）
  bool _bothConfirmed() {
    if (!bothHands) return true;
    final hi = math.max(_maxRSpeed, _maxLSpeed);
    final lo = math.min(_maxRSpeed, _maxLSpeed);
    return _bothCloseSeen &&
        hi >= swingSpeedFloor &&
        lo >= swingSpeedFloor * _secondHandFactor;
  }

  // 動態 threshold（歸一化速度）：80th percentile × 1.8，最低 0.012
  // （floor 0.005 時安靜期門檻過低，輕微手部移動即觸發 → 錄影 1-4 秒就被停掉）
  static const double _minThreshold = 0.012;

  double _threshold() {
    if (_speedBuf.length < 5) return _minThreshold;
    final sorted = _speedBuf.toList()..sort();
    final idx = (0.80 * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return math.max(_minThreshold, sorted[idx] * 1.8);
  }
}
