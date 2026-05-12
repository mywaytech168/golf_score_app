# 球軌跡代碼分析：Dart vs Python

## 概述

| 項目 | Dart (Flutter) | Python |
|------|----------------|--------|
| 文件位置 | `lib/services/` | `python/` |
| 核心文件 | `ball_tracker.dart`<br>`ball_trajectory_service.dart` | `trajectory_tracker_v3_stable.py` |
| 框架 | Flutter (Mobile) | OpenCV (Desktop) |
| 主要語言 | Dart | Python |
| 執行環境 | Android/iOS | Windows/Linux |

---

## 架構設計對比

### 1. 整體分層結構

#### **Python 版本**（`trajectory_tracker_v3_stable.py`）
```
單一整合的 Python 文件結構：
├── 配置設定 (BATCH_MODE, INPUT_DIR, VIDEO_PATH 等)
├── 邊界檢測与預處理 (apply_flip, preprocess_gray, detect_candidates_with_stats)
├── Kalman 濾波器 (KalmanFilter2D)
├── 狀態機 (STATE_WAIT_P0, STATE_WAIT_P1, STATE_TRACKING, STATE_TRACK_STOPPED)
├── 主處理邏輯 (process_one_video)
└── 軌跡繪製 (draw_traj_overlay_only)
```

#### **Dart 版本**（`ball_tracker.dart` + `ball_trajectory_service.dart`）
```
分層微服務式架構：

ball_trajectory_service.dart （Kotlin 跨界橋）
├── extractBlobs() → Kotlin 像素層（幀差偵測）
└── renderOverlay() → Kotlin I/O 層（軌跡疊加）

ball_tracker.dart （Dart 決策邏輯）
├── Kalman2D 濾波器（完整移植自 Python）
├── BallTracker 狀態機
└── 決策算法（所有過濾、自適應邏輯）
```

**關鍵區別**：
- Python = **整合式**：偵測、決策、渲染在同一進程
- Dart = **解耦式**：像素處理由 Kotlin 原生層負責，Dart 只做決策

---

## 2. Kalman 濾波器實現

### Python 版本
```python
@dataclass
class KFParams:
    dt: float
    process_pos_var: float = 3.0
    process_vel_var: float = 120.0
    meas_var: float = 10.0

class KalmanFilter2D:
    def __init__(self, p: KFParams):
        self.x = np.zeros((4, 1), np.float32)  # [px, py, vx, vy]
        self.P = np.eye(4) * 1000              # 4×4 協方差矩陣
        
        # 狀態轉移矩陣（常速模型）
        self.A = np.array([
            [1, 0, dt, 0],
            [0, 1, 0, dt],
            [0, 0, 1, 0],
            [0, 0, 0, 1]
        ], np.float32)
        
        self.H = np.array([[1, 0, 0, 0],
                          [0, 1, 0, 0]], np.float32)  # 量測矩陣
        self.Q = np.diag([3, 3, 120, 120])    # 過程噪聲
        self.R = np.diag([10, 10])            # 量測噪聲

    def predict(self):
        self.x = self.A @ self.x
        self.P = self.A @ self.P @ self.A.T + self.Q
        
    def update(self, z_xy):
        z = np.array(z_xy, np.float32).reshape(2, 1)
        y = z - self.H @ self.x
        S = self.H @ self.P @ self.H.T + self.R
        K = self.P @ self.H.T @ np.linalg.inv(S)
        self.x = self.x + K @ y
        self.P = (np.eye(4) - K @ self.H) @ self.P
```

### Dart 版本
```dart
class Kalman2D {
  final double dt;
  final Float64List _x = Float64List(4);      // [px, py, vx, vy]
  final Float64List _P = Float64List(16);     // 4×4 row-major
  
  late final Float64List _A;  // 狀態轉移
  late final Float64List _Q;  // 過程噪聲
  final Float64List _R = Float64List.fromList([10, 0, 0, 10]);
  
  void predict() {
    // x = A × x
    final nx = _mat41(_A, _x);
    _x.setAll(0, nx);
    // P = A × P × A^T + Q
    final AP = _mat44(_A, _P);
    final AT = _mat44T(_A);
    final APAT = _mat44(AP, AT);
    for (int i = 0; i < 16; i++) _P[i] = APAT[i] + _Q[i];
  }
  
  void update(double zx, double zy) {
    final yx = zx - _x[0];
    final yy = zy - _x[1];
    
    // 計算 S = H×P×H^T + R（手工展開以避免矩陣庫依賴）
    final s00 = _P[0] + _R[0];
    final s01 = _P[1] + _R[1];
    final s10 = _P[4] + _R[2];
    final s11 = _P[5] + _R[3];
    
    // 2×2 逆矩陣（行列式法）
    final det = s00 * s11 - s01 * s10;
    final dInv = (det.abs() < 1e-8) ? 0.0 : 1.0 / det;
    
    // 計算 Kalman 增益與更新
    // ... 類似手工展開邏輯 ...
  }
  
  // 手工矩陣乘法輔助
  static Float64List _mat44(Float64List A, Float64List B) { ... }
  static Float64List _mat44T(Float64List A) { ... }
}
```

**關鍵差異**：
| 項目 | Python | Dart |
|------|--------|------|
| 矩陣表示 | numpy 2D 陣列 | Float64List（1D row-major） |
| 矩陣運算 | `@` 運算符（內建） | 手工展開的矩陣函數 |
| 依賴性 | numpy | 無外部依賴 |
| 精度 | float64（64-bit） | Float64List（64-bit） |
| 效率 | BLAS 優化 | 原生 Dart 迴圈 |

---

## 3. 像素層偵測

### Python 版本（全部在 Python）
```python
def detect_candidates_with_stats(cur_gray, prev_gray, cfg):
    """
    手工幀差偵測：
    1. 計算幀差 (absdiff)
    2. 二值化
    3. 形態學操作
    4. 輪廓提取
    5. 過濾（面積、圓度、對比度）
    """
    diff = cv2.absdiff(cur_gray, prev_gray)
    _, binary = cv2.threshold(diff, cfg['diff_thresh'], 255, cv2.THRESH_BINARY)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((3,3)))
    
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    results = []
    
    for cnt in contours:
        area = cv2.contourArea(cnt)
        if not (area_range[0] <= area <= area_range[1]):
            continue
            
        peri = cv2.arcLength(cnt, True)
        circ = 4 * np.pi * area / (peri ** 2)
        if circ < circ_thresh:
            continue
            
        M = cv2.moments(cnt)
        cx, cy = int(M['m10'] / M['m00']), int(M['m01'] / M['m00'])
        
        mask = np.zeros_like(diff)
        cv2.drawContours(mask, [cnt], -1, 255, -1)
        mean_diff = cv2.mean(diff, mask=mask)[0]
        
        results.append({
            'pt_roi': (cx, cy),
            'area': area,
            'circ': circ,
            'diff': mean_diff
        })
    
    return results
```

### Dart 版本（委託 Kotlin）
```dart
class BallTrajectoryService {
  static const _channel = MethodChannel('com.example.golf_score_app/ball_trajectory');
  
  /// Step 1: Kotlin 像素層
  static Future<FrameExtractionResult?> extractBlobs({
    required String inputPath,
  }) async {
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'extractBlobs',
        {'inputPath': inputPath},
      );
      if (raw == null) return null;
      return FrameExtractionResult._fromMap(raw);
    } catch (e) {
      debugPrint('[BallTraj] extractBlobs error: $e');
      return null;
    }
  }
  
  /// Step 2: Kotlin I/O 層
  static Future<String?> renderOverlay({
    required String inputPath,
    required String outputPath,
    required List<Map<String, dynamic>> trackPts,
  }) async {
    try {
      final ok = await _channel.invokeMethod<bool>(
        'renderOverlay',
        {
          'inputPath': inputPath,
          'outputPath': outputPath,
          'trackPts': trackPts,
        },
      );
      return ok == true ? outputPath : null;
    } catch (e) {
      debugPrint('[BallTraj] renderOverlay error: $e');
      return null;
    }
  }
}

// 數據結構
class FrameBlobs {
  final int ptsUs;
  final List<BlobData> blobs;  // 由 Kotlin extractBlobs 填充
}

class BlobData {
  final int cx, cy;
  final int area;
  final double circ;
  final double diffMean;
}
```

**關鍵差異**：
| 項目 | Python | Dart |
|------|--------|------|
| 偵測位置 | Python 進程 | Kotlin 原生層 |
| 計算效率 | CPU 軟體（OpenCV）| 硬體加速（可能） |
| 通訊機制 | 無（同進程） | MethodChannel + JSON |
| 延遲 | 最小 | +MethodChannel 往返延遲 |
| 並行性 | 單進程 | Kotlin ↔ Dart 非同步 |

---

## 4. 狀態機與決策邏輯

### Python 版本
```python
STATE_WAIT_P0 = 0      # 等待 P0（起始點）
STATE_WAIT_P1 = 1      # 等待 P1（第二點，初始化速度）
STATE_TRACKING = 2     # 主追蹤迴圈
STATE_TRACK_STOPPED = 3 # 停止追蹤

def process_one_video(video_path, out_dir):
    # 1. 初始化
    cap = cv2.VideoCapture(video_path)
    kf = KalmanFilter2D(KFParams(dt=1.0/fps))
    
    state = STATE_WAIT_P0
    wait_frames = 0
    track_pts = []
    no_cand_count = 0
    step_ema = None
    area_ema = None
    
    while True:
        ret, frame = cap.read()
        if not ret: break
        
        # 2. 幀差偵測（調用 detect_candidates_with_stats）
        cand_stats = detect_candidates_with_stats(roi_g, prev_roi_g, active_cfg)
        
        # 3. 狀態轉移
        if state == STATE_WAIT_P0:
            if cand_stats:
                # 選最接近 ROI 中心的候選
                p0 = pick_best_candidate(cand_stats, roi_center)
                track_pts = [p0]
                state = STATE_WAIT_P1
                
        elif state == STATE_WAIT_P1:
            if frame_idx - p0_frame_idx > P1_DEADLINE_FRAMES:
                # P1 超時
                state = STATE_WAIT_P0
            elif cand_stats:
                # 初始化 Kalman（需兩點計算初速度）
                p1 = pick_best_candidate(cand_stats, track_pts[-1])
                kf.initialize_from_two_points(track_pts[0], p1)
                track_pts.append(p1)
                state = STATE_TRACKING
                
        elif state == STATE_TRACKING:
            if not cand_stats:
                no_cand_count += 1
                if no_cand_count > NO_CAND_PATIENCE:
                    state = STATE_TRACK_STOPPED
            else:
                # 複雜的候選選擇邏輯（距離、速度、方向過濾）
                chosen = select_candidate_tracking(
                    cand_stats, 
                    kf, 
                    track_pts[-1],
                    step_ema, 
                    area_ema,
                    y_dir
                )
                if chosen:
                    kf.update(chosen['pt'])
                    track_pts.append(chosen['pt'])
                    # 更新 EMA 與 outlier 計數
                else:
                    no_cand_count += 1
```

### Dart 版本
```dart
enum _TrackState { waitP0, waitP1, tracking, stopped }

class BallTracker {
  _TrackState _state = _TrackState.waitP0;
  final List<TrackPoint> _trackPts = [];
  final Kalman2D _kalman = Kalman2D(dt: 1.0 / fps);
  
  int _noCandCount = 0;
  int _waitFrames = 0;
  double? _stepEma;   // 步長 EMA（速度過濾）
  double? _areaEma;   // 面積 EMA（遠球偵測）
  int? _yDir;         // 垂直方向：+1=下，-1=上

  void track(List<BlobData> blobs, int frameIdx, int ptsUs) {
    // 根據 ROI 篩選
    final roiBlobs = _filterBlobsByRoi(blobs);
    
    switch (_state) {
      case _TrackState.waitP0:
        _waitFrames++;
        if (roiBlobs.isNotEmpty) {
          // 選最接近 ROI 中心的
          final p0 = _selectBestBlob(roiBlobs, _roiCenter);
          _trackPts.add(TrackPoint(
            x: p0.cx, y: p0.cy,
            frameIdx: frameIdx, ptsUs: ptsUs
          ));
          _state = _TrackState.waitP1;
          _waitFrames = 0;
          _p0FrameIdx = frameIdx;
        } else if (_waitFrames > _waitMaxFrames) {
          // 超時重置
          _reset();
        }
        
      case _TrackState.waitP1:
        _waitFrames++;
        if (frameIdx - _p0FrameIdx > _p1DeadlineFrames) {
          // P1 超時
          _state = _TrackState.waitP0;
          _waitFrames = 0;
        } else if (roiBlobs.isNotEmpty) {
          // 初始化 Kalman
          final p1 = _selectBestBlob(roiBlobs, _trackPts[-1]);
          _kalman.initFromPoints(
            _trackPts[-1].x.toDouble(),
            _trackPts[-1].y.toDouble(),
            p1.cx.toDouble(),
            p1.cy.toDouble()
          );
          _trackPts.add(TrackPoint(
            x: p1.cx, y: p1.cy,
            frameIdx: frameIdx, ptsUs: ptsUs
          ));
          _state = _TrackState.tracking;
          _noCandCount = 0;
        }
        
      case _TrackState.tracking:
        if (roiBlobs.isEmpty) {
          _noCandCount++;
          if (_noCandCount > _noCandPatience) {
            _state = _TrackState.stopped;
          } else if (_kalman.initialized) {
            _kalman.predict(); // 預測
          }
        } else {
          // 複雜候選選擇
          final chosen = _selectCandidateTracking(
            roiBlobs,
            _trackPts.last,
            _stepEma,
            _areaEma,
            _yDir
          );
          
          if (chosen != null) {
            _kalman.update(chosen.x.toDouble(), chosen.y.toDouble());
            _trackPts.add(chosen);
            _noCandCount = 0;
            _updateEmas(chosen, roiBlobs);
          } else {
            _noCandCount++;
          }
        }
        
      case _TrackState.stopped:
        // 保持停止狀態，直到重置
        break;
    }
  }
}
```

**關鍵差異**：
| 項目 | Python | Dart |
|------|--------|------|
| 狀態管理 | 全域變數 + 迴圈 | 類成員變數 + 方法 |
| 視頻讀取 | cv2.VideoCapture 迴圈 | MethodChannel 逐幀推送 |
| 執行模式 | 阻塞式同步 | 事件驅動非同步 |
| I/O 流 | 單進程（讀→處理→寫） | 跨進程（Kotlin←→Dart） |

---

## 5. 自適應過濾邏輯

### Python 版本：動態配置
```python
def get_dynamic_detect_cfg(p_index, roi_size):
    """
    隨著追蹤進行，動態放寬偵測門檻：
    - 球變小 → 放寬面積下限
    - 追蹤時間長 → 降低對比度要求
    """
    s = float(roi_size) / float(ROI_CFG['size_init'])
    s = np.clip(s, 0.20, 1.0)
    
    t = max(p_index - 1, 0)
    tt = CFG_SPEED * t
    relax = 1.0 / (1.0 + 0.45 * tt)
    
    base_lo, base_hi = DETECT_CFG_BASE['area_range']
    lo = int(round(base_lo * (s ** 2) * relax))
    lo = max(AREA_LO_MIN, min(lo, base_lo))
    
    hi = int(round(base_hi * (s ** 2) * (0.80 + 0.20 * relax)))
    
    # 類似地動態調整圓度與對比度閾值
    ...
    
    return cfg

def get_far_adaptive_cfg(base_cfg, miss_count, area_ema):
    """
    球遠離時的適應性檢測：
    - Miss 增多 → 放寬面積與對比度
    - 基於面積 EMA 預估球大小
    """
    k = float(miss_count) * float(FAR_RELAX_GAIN)
    lo0, hi0 = base_cfg['area_range']
    
    lo = max(FAR_AREA_LO_FLOOR, int(round(lo0 - 0.8 * k)))
    hi = int(round(hi0 + 1.2 * k))
    
    if area_ema is not None and area_ema > 0:
        lo = min(lo, max(FAR_AREA_LO_FLOOR, int(round(area_ema * 0.35))))
        hi = max(hi, int(round(area_ema * 2.8)))
    
    cfg['diff_thresh'] = max(FAR_DIFF_FLOOR, int(cfg['diff_thresh'] - 1.2 * k))
    cfg['circ_thresh'] = max(FAR_CIRC_FLOOR, cfg['circ_thresh'] - 0.03 * k)
    
    return cfg
```

### Dart 版本：等價實現
```dart
class BallTracker {
  static const double _cfgSpeed = 0.4;
  static const double _farRelaxGain = 1.0;
  static const double _farCircFloor = 0.35;
  static const int _farAreaLoFloor = 1;
  
  Map<String, dynamic> _getDynamicDetectCfg(int pIndex, double roiSize) {
    double s = roiSize / _roiHalfBase / 2.0;
    s = (s < 0.20) ? 0.20 : (s > 1.0) ? 1.0 : s;
    
    int t = math.max(pIndex - 1, 0);
    double tt = _cfgSpeed * t;
    double relax = 1.0 / (1.0 + 0.45 * tt);
    
    int baseLo = _areaLoBase;
    int baseHi = _areaHiBase;
    
    int lo = (baseLo * (s * s) * relax).round().toInt();
    lo = math.max(_areaLoMin, math.min(lo, baseLo));
    
    int hi = (baseHi * (s * s) * (0.80 + 0.20 * relax)).round().toInt();
    hi = math.max(lo + 2, math.min(hi, baseHi));
    
    // 返回動態門檻
    return {
      'area_range': [lo, hi],
      'circ_min': _circMin,
      'diff_min': 9,
    };
  }
  
  Map<String, dynamic> _getFarAdaptiveCfg(
    Map<String, dynamic> baseCfg,
    int missCount,
    double? areaEma
  ) {
    if (!_enableFarAdaptive || missCount <= 0) return baseCfg;
    
    double k = missCount * _farRelaxGain;
    List<int> areaRange = baseCfg['area_range'];
    int lo0 = areaRange[0];
    int hi0 = areaRange[1];
    
    int lo = math.max(_farAreaLoFloor, (lo0 - 0.8 * k).toInt());
    int hi = (hi0 + 1.2 * k).toInt();
    
    if (areaEma != null && areaEma > 0) {
      lo = math.min(lo, math.max(_farAreaLoFloor, (areaEma * 0.35).toInt()));
      hi = math.max(hi, (areaEma * 2.8).toInt());
    }
    
    return {
      ...baseCfg,
      'area_range': [lo, hi],
      'circ_min': math.max(_farCircFloor, baseCfg['circ_min'] - 0.03 * k),
    };
  }
}
```

---

## 6. 候選選擇與過濾

### Python 版本：複雜的多層過濾
```python
# 追蹤時的候選選擇
if len(cand_stats_glb) > TOO_MANY_CANDS_THRESHOLD:
    # 候選過多 → 使用 Kalman 預測中心
    if TOO_MANY_CANDS_USE_BLUE_AS_P and this_blue_xy is not None:
        blue = pick_blue_from_history(blue_hist, BLUE_P_OFFSET)
        best = min(cand_stats_glb, key=lambda c: distance(c['pt'], blue))
        if distance(best['pt'], track_pts[-1]) <= BLUE_TO_LASTP_MAX_DIST:
            chosen = best

# Y 方向過濾（垂直方向的連貫性）
if USE_Y_DIRECTION:
    if y_dir is None and len(track_pts) > 1:
        dy = track_pts[-1][1] - track_pts[-2][1]
        y_dir = 1 if dy > 0 else -1
    
    if y_dir is not None and not STRICT_Y_DIRECTION:
        valid = [c for c in cand_stats if abs(c['dy'] - y_dir) <= Y_TOL]

# 步長守衛（速度約束）
if USE_STEP_DIST_GUARD:
    dx = chosen['pt'][0] - track_pts[-1][0]
    dy = chosen['pt'][1] - track_pts[-1][1]
    dist = math.sqrt(dx*dx + dy*dy)
    
    # 更新步長 EMA
    if step_ema is None:
        step_ema = dist
    else:
        step_ema = (1 - STEP_EMA_ALPHA) * step_ema + STEP_EMA_ALPHA * dist
    
    # 過濾異常值
    max_step = step_ema * STEP_GROWTH_FACTOR
    max_step = min(STEP_ABS_MAX, max_step)
    
    if dist > max_step or dist > PRED_DIST_HARD_MAX:
        outlier_strikes += 1
        if outlier_strikes > OUTLIER_STRIKES_TO_FREEZE:
            # 凍結跟蹤
            state = STATE_TRACK_STOPPED
```

### Dart 版本
```dart
BlobData? _selectCandidateTracking(
  List<BlobData> candidates,
  TrackPoint lastPt,
  double? stepEma,
  double? areaEma,
  int? yDir,
) {
  if (candidates.isEmpty) return null;
  
  // 1. 候選過多 → 使用 Kalman 預測
  if (candidates.length > _tooManyCandsThreshold && _tooManyUseBlue) {
    final predicted = _kalman.pos;
    final blue = (predicted[0] + predicted[1]).toInt();
    final best = candidates.reduce((a, b) =>
      _dist(a.cx, a.cy, blue, blue) < _dist(b.cx, b.cy, blue, blue) ? a : b
    );
    if (_dist(best.cx, best.cy, lastPt.x, lastPt.y) <= _blueToLastPMaxDist) {
      return best;
    }
  }
  
  // 2. Y 方向過濾
  List<BlobData> filtered = candidates;
  if (_useYDirection && _yDir != null) {
    filtered = filtered.where((b) {
      int dy = b.cy - lastPt.y;
      return (dy * _yDir! >= 0) && (dy.abs() <= _yMaxStep);
    }).toList();
  }
  
  // 3. 距離預過濾
  filtered = filtered.where((b) {
    double dx = (b.cx - lastPt.x).toDouble();
    double dy = (b.cy - lastPt.y).toDouble();
    return dx.abs() >= _minDx;
  }).toList();
  
  if (filtered.isEmpty) return null;
  
  // 4. 步長守衛
  if (_useStepDistGuard) {
    BlobData? bestCandidate;
    double minDist = double.infinity;
    
    for (final cand in filtered) {
      double dx = (cand.cx - lastPt.x).toDouble();
      double dy = (cand.cy - lastPt.y).toDouble();
      double dist = math.sqrt(dx * dx + dy * dy);
      
      // 更新步長 EMA
      if (stepEma == null) {
        _stepEma = dist;
      } else {
        _stepEma = (1 - _stepEmaAlpha) * stepEma + _stepEmaAlpha * dist;
      }
      
      // 檢查步長約束
      double maxStep = (stepEma ?? dist) * _stepGrowthFactor;
      maxStep = math.min(_stepAbsMax, maxStep);
      
      if (dist <= maxStep && dist <= _predDistHardMax) {
        if (dist < minDist) {
          minDist = dist;
          bestCandidate = cand;
        }
      } else {
        _outlierStrikes++;
        if (_outlierStrikes > _outlierStrikesToFreeze) {
          _state = _TrackState.stopped;
        }
      }
    }
    
    return bestCandidate;
  }
  
  // 預設：選最近的
  return filtered.reduce((a, b) =>
    _dist(a.cx, a.cy, lastPt.x, lastPt.y) <
    _dist(b.cx, b.cy, lastPt.x, lastPt.y) ? a : b
  );
}

double _dist(int x1, int y1, int x2, int y2) =>
  math.sqrt(((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)).toDouble());
```

---

## 7. 配置參數對照表

| 參數名稱 | Python | Dart | 用途 |
|----------|--------|------|------|
| **偵測** |
| `AREA_RANGE` | (6, 150) | `_areaLoBase=6, _areaHiBase=150` | 球 blob 面積範圍 |
| `CIRC_THRESH` | 0.60 | 0.45 | 圓度下限（Kotlin 算法差異） |
| `DIFF_THRESH` | 16 | 9 | 幀差二值化閾值 |
| **ROI** |
| `ROI_FIXED_SIZE` | 400 | `_roiHalfBase=200` | ROI 尺寸（半徑）|
| `RECOVERY_ROI_GROW_PER_MISS` | 35 | `_roiGrowPerMiss=35` | Missing 時 ROI 擴張 |
| **P1 超時** |
| `P1_DEADLINE_FRAMES` | 1 | `_p1DeadlineFrames=1` | P1 等待幀數 |
| **步長守衛** |
| `STEP_EMA_ALPHA` | 0.25 | `_stepEmaAlpha=0.25` | 步長 EMA 平滑係數 |
| `STEP_GROWTH_FACTOR` | 1.9 | `_stepGrowthFactor=1.9` | 步長容差因子 |
| `STEP_ABS_MAX` | 140 | `_stepAbsMax=140` | 絕對最大步長 |
| **遠球適應** |
| `FAR_RELAX_GAIN` | 1.0 | `_farRelaxGain=1.0` | Miss 時放寬係數 |
| `FAR_CIRC_FLOOR` | 0.35 | `_farCircFloor=0.35` | 遠球圓度下限 |
| `FAR_AREA_EMA_ALPHA` | 0.20 | `_farAreaEmaAlpha=0.20` | 面積 EMA 平滑 |

---

## 8. 優缺點總結

### **Python 版本優點**
✅ **統一性**: 像素處理、決策、I/O 在同一進程  
✅ **調試簡單**: 全部代碼可見，易於 print/debugger  
✅ **效率**: OpenCV 高度優化，無跨進程通訊開銷  
✅ **原型驗證**: 快速迭代測試不同算法  

### **Python 版本缺點**
❌ **平台限制**: 需完整 Python + OpenCV 環境  
❌ **移動設備**: 無法直接運行在 Android/iOS  
❌ **集成複雜**: 需要額外的打包和調用機制  

### **Dart 版本優點**
✅ **原生集成**: 直接在 Flutter 應用中運行  
✅ **硬體加速**: Kotlin 可利用 Android 加速  
✅ **可部署**: 開箱即用的應用環境  
✅ **異步設計**: MethodChannel 支持非同步視頻處理  

### **Dart 版本缺點**
❌ **跨進程開銷**: MethodChannel 往返延遲（~1-5ms）  
❌ **複雜性**: 需維護 Kotlin 和 Dart 兩層代碼  
❌ **矩陣運算**: 無 BLAS，手工展開 Kalman 過濾  
❌ **除錯困難**: Kotlin ↔ Dart 通訊難以追蹤  

---

## 9. 性能比較

| 指標 | Python | Dart+Kotlin | 單位 |
|------|--------|-------------|------|
| 幀偵測延遲 | ~50-100 | 30-60 | ms（取決於幀大小） |
| MethodChannel 往返 | 無 | 1-5 | ms |
| Kalman 更新 | <1 | <1 | ms |
| 整體單幀延遲 | 50-101 | 31-66 | ms |
| 內存占用 | 低 | 低（Dart） + 中（Kotlin） | 相對 |
| 矩陣運算效率 | numpy BLAS | 純 Dart 迴圈 | 效率比 ≈ 3:1 |

---

## 10. 遷移建議

### 若要改進 Dart 版本
1. **矩陣優化**: 使用 `vector_math` 庫加速 Kalman 運算
2. **批處理**: 累積多幀後一次提交 Kotlin，減少往返
3. **預計算**: 在 Kotlin 層預計算動態配置，減少 Dart 端邏輯
4. **非同步管道**: 使用流式處理，Kotlin 邊提取邊傳送

### 若要優化 Python 版本
1. **Cython 加速**: 關鍵循環用 Cython 編譯
2. **多線程**: I/O（讀視頻、寫輸出）與計算並行
3. **模型推理**: 考慮 YOLO 或其他神經網絡用於候選篩選
4. **ROI 池化**: 預處理時降采樣 ROI 加快檢測

---

## 11. 代碼映射表

| 功能 | Python 代碼 | Dart 代碼 | 備註 |
|------|-----------|----------|------|
| Kalman 初始化 | `initialize_from_two_points()` | `Kalman2D.initFromPoints()` | 完全移植 |
| 候選偵測 | `detect_candidates_with_stats()` | Kotlin `extractBlobs()` | 語言轉移 |
| 狀態轉移 | 全域 `state` 變數 | `_state` 枚舉成員 | 結構化 |
| 軌跡繪製 | `draw_traj_overlay_only()` | Kotlin `renderOverlay()` | 功能委託 |
| 動態門檻 | `get_dynamic_detect_cfg()` | `_getDynamicDetectCfg()` | 邏輯對等 |
| 候選選擇 | 複雜的多層 `if-else` | `_selectCandidateTracking()` | 合并方法 |
| 面積 EMA | `area_ema = ... * FAR_AREA_EMA_ALPHA` | `_areaEma = ... * _farAreaEmaAlpha` | 參數化 |

