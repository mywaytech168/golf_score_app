# 🎬 Flutter 實時影片穩定化：Gyro/IMU + Affine 變換方案

## 📋 執行摘要

本文檔設計在 Flutter 視頻錄制過程中，利用設備內置陀螺儀 (Gyroscope) 和 IMU 傳感器實時捕獲相機晃動數據，通過 **Affine 變換** 進行實時或後處理穩定化。

**核心優勢**：
- ✅ **實時補償**：邊錄邊穩定（可選）
- ✅ **高精度**：陀螺儀 + 加速度計 + 磁力計三軸融合
- ✅ **無幀率損失**：與現有 FFmpeg/MeshFlow 配合
- ✅ **支持多 IMU**：已有外置 BLE IMU 基礎
- ✅ **低延遲**：毫秒級時間戳同步

---

## 🏗️ 系統架構

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Recording UI                      │
└────────────┬────────────────────────────────────────────────┘
             │
   ┌─────────┴──────────────┬──────────────────┐
   │                        │                  │
   ▼                        ▼                  ▼
[Camera API]           [Phone Gyro]       [External BLE IMU]
   │                        │                  │
   └─────────────┬──────────┴──────────────────┘
                 │
                 ▼
        ┌─────────────────────┐
        │  IMU Data Logger    │  ← 現有系統：收集傳感器數據到 CSV
        │  (imu_data_logger.dart)
        └────────┬────────────┘
                 │
                 ▼
        ┌─────────────────────┐
        │   Gyro Fusion       │  ← 新增：融合陀螺儀和加速度
        │   (gyro_fusion.dart)|
        └────────┬────────────┘
                 │
                 ▼
        ┌─────────────────────┐
        │  Motion Tracker     │  ← 新增：跟蹤相機運動
        │  (motion_tracker.dart)
        └────────┬────────────┘
                 │
                 ▼
        ┌──────────────────────────┐
        │ Affine Compensator       │  ← 新增：計算補償變換
        │ (affine_compensator.dart)|
        └────────┬─────────────────┘
                 │
    ┌────────────┼────────────┐
    │            │            │
    ▼            ▼            ▼
[實時應用]  [後處理]  [參數輸出]
(GPU濾鏡)   (FFmpeg)   (JSON)
```

---

## 📊 數據流與時間戳同步

### 現狀 (已實現)
```
外置 IMU (BLE)
  ↓ (通過 Bluetooth)
ImuDataLogger.logLinearAcceleration()     ← 線性加速度 (m/s²)
ImuDataLogger.logGameRotationVector()     ← 四元數 (q) + 加速度
  ↓ (壁鐘時間同步，基於 DateTime.now())
CSV 寫入：ElapsedSec, QuatI, QuatJ, QuatK, QuatW, AccelX, AccelY, AccelZ
```

### 改進方案 (新增手機陀螺儀)
```
手機內置傳感器 (無延遲)
  ├─ Accelerometer: 線性加速度 (x, y, z)
  ├─ Gyroscope:    角速度 (roll, pitch, yaw)
  └─ Magnetometer: 磁場方向 (可選)
       ↓
  高頻采樣 (100-200 Hz) ← 比視頻幀率快 3-7 倍
       ↓
  ┌─────────────────────────────┐
  │  Gyro Fusion Module         │
  │  • IMU 參考幀設定           │
  │  • 四元數積分 (q_t)         │
  │  • 加速度計零點漂移補償     │
  │  • 磁力計地球磁場補償       │
  └────────┬────────────────────┘
           ↓
  相機運動估計: R(t) ← 從陀螺儀積分得到
           ↓
  ┌─────────────────────────────┐
  │  Motion Tracker             │
  │  • 逐幀追蹤相機姿態變化     │
  │  • 計算幀間運動 ΔR          │
  │  • 累積位移估計 (可選)      │
  └────────┬────────────────────┘
           ↓
  ┌─────────────────────────────┐
  │  Affine Compensator         │
  │  • 計算補償矩陣: A_comp      │
  │  • 插值參數 (平滑度)        │
  │  • 模式選擇：                │
  │    - 旋轉補償                │
  │    - 旋轉 + 縮放補償         │
  │    - 完整 Affine (旋轉+位移) │
  └────────┬────────────────────┘
           ↓
  ┌──────────┬──────────┬─────────────┐
  │          │          │             │
  ▼          ▼          ▼             ▼
[GPU實時]  [軟件濾鏡]  [參數輸出]  [驗證視頻]
```

---

## 💾 數據存儲格式擴展

### 新增 IMU 文件：`{session}_{device}_imu_phone.csv`

```csv
# Phone IMU Gyroscope + Accelerometer
Device:Phone Built-in
ElapsedSec,GyroX,GyroY,GyroZ,AccelX,AccelY,AccelZ,MagX,MagY,MagZ,Temp
0.000000,0.001,-0.005,0.003,0.02,-0.15,9.81,24.5,-3.2,-42.1,28.5
0.010000,0.002,-0.006,0.004,0.03,-0.16,9.80,24.3,-3.1,-42.3,28.5
...
```

### 融合結果文件：`{session}_motion_estimation.json`

```json
{
  "metadata": {
    "recordingStartTime": "2026-02-04T10:30:45.123Z",
    "totalFrames": 180,
    "frameRate": 30,
    "imuSampleRate": 100,
    "estimationMethod": "gyro_fusion_affine"
  },
  "frames": [
    {
      "frameId": 0,
      "timestampMs": 0,
      "cameraRotation": {
        "quaternion": [0.0, 0.0, 0.0, 1.0],
        "eulerDegrees": [0.0, 0.0, 0.0]
      },
      "affineCompensation": {
        "matrix": [
          [1.0, 0.0, 0.0],
          [0.0, 1.0, 0.0],
          [0.0, 0.0, 1.0]
        ],
        "confidence": 0.95
      }
    },
    {
      "frameId": 1,
      "timestampMs": 33.33,
      "cameraRotation": {
        "quaternion": [0.001, -0.002, 0.005, 0.9999],
        "eulerDegrees": [0.05, -0.1, 0.3]
      },
      "affineCompensation": {
        "matrix": [
          [0.9999, -0.003, 1.2],
          [0.003, 1.0001, -0.8],
          [0.0, 0.0, 1.0]
        ],
        "confidence": 0.93
      }
    }
  ]
}
```

---

## 🔧 模塊實現詳解

### 1️⃣ GyroFusion 模塊
**文件**：`lib/services/gyro_fusion.dart`

```dart
import 'dart:typed_data';
import 'dart:async';
import 'package:sensors_plus/sensors_plus.dart';

/// 陀螺儀融合：四元數積分 + 加速度計校準
class GyroFusion {
  // 狀態
  Quaternion _q = Quaternion.identity();      // 當前四元數
  Vector3 _accelBias = Vector3.zero();        // 加速度計零點偏差
  Vector3 _gyroBias = Vector3.zero();         // 陀螺儀零點偏差
  double _lastUpdateTimeMs = 0;
  
  // 參數
  final double _gyroNoise = 0.01;             // 陀螺儀噪聲 (rad/s)
  final double _accelNoise = 0.1;             // 加速度計噪聲 (m/s²)
  final double _fusionAlpha = 0.02;           // 加速度計融合權重 (0-1)
  
  // 流
  StreamSubscription? _gyroSub, _accelSub, _magnetoSub;
  final List<Vector3> _recentGyrReadings = [];
  final List<Vector3> _recentAccelReadings = [];
  
  /// 啟動融合：監聽設備傳感器流
  void start() {
    _lastUpdateTimeMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    
    // 陀螺儀：旋轉角速度 (rad/s)
    _gyroSub = gyroscopeEvents.listen((GyroscopeEvent event) {
      _handleGyroUpdate(Vector3(event.x, event.y, event.z));
    });
    
    // 加速度計：線性加速度 (m/s²)
    _accelSub = accelerometerEvents.listen((AccelerometerEvent event) {
      _handleAccelUpdate(Vector3(event.x, event.y, event.z));
    });
    
    // 磁力計：地球磁場 (μT)
    _magnetoSub = magnetometerEvents.listen((MagnetometerEvent event) {
      _handleMagnoUpdate(Vector3(event.x, event.y, event.z));
    });
  }
  
  /// 陀螺儀更新：四元數積分
  void _handleGyroUpdate(Vector3 omega) {
    final nowMs = DateTime.now().millisecondsSinceEpoch.toDouble();
    final dtSec = (nowMs - _lastUpdateTimeMs) / 1000.0;
    _lastUpdateTimeMs = nowMs;
    
    // 去偏
    omega = omega - _gyroBias;
    
    // 四元數微分: dq/dt = 0.5 * q * [0, ω]
    // q(t+dt) ≈ q(t) + dq/dt * dt (一階 RK)
    final dq = Quaternion(
      omega.x * dtSec / 2,
      omega.y * dtSec / 2,
      omega.z * dtSec / 2,
      1.0,
    );
    _q = _q.multiply(dq).normalized();
  }
  
  /// 加速度計更新：融合修正
  void _handleAccelUpdate(Vector3 accel) {
    _recentAccelReadings.add(accel - _accelBias);
    if (_recentAccelReadings.length > 20) {
      _recentAccelReadings.removeAt(0);
    }
    
    // 計算加速度計估計的陀螺儀傾角
    final accelNorm = accel.normalized();
    final measuredGravity = Quaternion(
      0, accelNorm.x, accelNorm.y, accelNorm.z,
    );
    
    // 期望重力方向：q^-1 * [0,0,0,g] * q = [0, 0, 0, 9.81]
    final expectedGravity = _q
      .inverse()
      .multiply(Quaternion(0, 0, 0, 9.81))
      .multiply(_q);
    
    // 融合：使用加速度計修正陀螺儀偏差
    final error = expectedGravity.crossWithVector(accelNorm);
    _q = _q.slerpWith(measuredGravity, _fusionAlpha);
  }
  
  /// 磁力計更新：方向修正（可選）
  void _handleMagnoUpdate(Vector3 mag) {
    // 地球磁場校準與方位修正
    // 復雜度較高，可先跳過
  }
  
  /// 獲取當前相機四元數
  Quaternion getQuaternion() => _q;
  
  /// 標定：收集靜止幀的偏差
  void calibrate() {
    // 平均最近 100 個樣本中的靜止幀
    if (_recentGyrReadings.length >= 100) {
      _gyroBias = Vector3.average(_recentGyrReadings.sublist(0, 100));
    }
    if (_recentAccelReadings.length >= 100) {
      _accelBias = Vector3.average(_recentAccelReadings.sublist(0, 100)) - Vector3(0, 0, 9.81);
    }
  }
  
  void dispose() {
    _gyroSub?.cancel();
    _accelSub?.cancel();
    _magnetoSub?.cancel();
  }
}

// ========== 簡單數學類 ==========

class Vector3 {
  double x, y, z;
  
  Vector3(this.x, this.y, this.z);
  
  static Vector3 get zero => Vector3(0, 0, 0);
  
  Vector3 operator +(Vector3 other) => Vector3(
    x + other.x, y + other.y, z + other.z,
  );
  
  Vector3 operator -(Vector3 other) => Vector3(
    x - other.x, y - other.y, z - other.z,
  );
  
  Vector3 operator *(double s) => Vector3(x * s, y * s, z * s);
  
  double dot(Vector3 other) => x * other.x + y * other.y + z * other.z;
  
  Vector3 cross(Vector3 other) => Vector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );
  
  double magnitude() => (x * x + y * y + z * z).sqrt();
  
  Vector3 normalized() {
    final mag = magnitude();
    return mag == 0 ? this : Vector3(x / mag, y / mag, z / mag);
  }
  
  static Vector3 average(List<Vector3> vectors) {
    if (vectors.isEmpty) return Vector3.zero;
    var sum = Vector3.zero;
    for (final v in vectors) sum = sum + v;
    return sum * (1.0 / vectors.length);
  }
}

class Quaternion {
  double i, j, k, real;  // [i, j, k, w] 或 [x, y, z, w]
  
  Quaternion(this.i, this.j, this.k, this.real);
  
  static Quaternion get identity => Quaternion(0, 0, 0, 1);
  
  Quaternion multiply(Quaternion other) => Quaternion(
    real * other.i + i * other.real + j * other.k - k * other.j,
    real * other.j - i * other.k + j * other.real + k * other.i,
    real * other.k + i * other.j - j * other.i + k * other.real,
    real * other.real - i * other.i - j * other.j - k * other.k,
  );
  
  Quaternion inverse() {
    final normSq = i * i + j * j + k * k + real * real;
    return Quaternion(-i / normSq, -j / normSq, -k / normSq, real / normSq);
  }
  
  Quaternion normalized() {
    final mag = (i * i + j * j + k * k + real * real).sqrt();
    return mag == 0 ? identity : Quaternion(
      i / mag, j / mag, k / mag, real / mag,
    );
  }
  
  Quaternion crossWithVector(Vector3 v) {
    return Quaternion(v.x, v.y, v.z, 0);
  }
  
  Quaternion slerpWith(Quaternion other, double t) {
    // Spherical Linear Interpolation
    var dot = i * other.i + j * other.j + k * other.k + real * other.real;
    
    if (dot < 0.0) {
      other = Quaternion(-other.i, -other.j, -other.k, -other.real);
      dot = -dot;
    }
    
    dot = dot.clamp(-1.0, 1.0);
    final theta0 = (dot).acos();
    final theta = theta0 * t;
    
    final q2 = Quaternion(
      other.i - i * dot,
      other.j - j * dot,
      other.k - k * dot,
      other.real - real * dot,
    ).normalized();
    
    return Quaternion(
      real * (theta.cos()) + q2.real * (theta.sin()),
      i * (theta.cos()) + q2.i * (theta.sin()),
      j * (theta.cos()) + q2.j * (theta.sin()),
      k * (theta.cos()) + q2.k * (theta.sin()),
    );
  }
}
```

### 2️⃣ MotionTracker 模塊
**文件**：`lib/services/motion_tracker.dart`

```dart
import 'dart:async';
import 'gyro_fusion.dart';

/// 跟蹤視頻幀的相機運動
class MotionTracker {
  final GyroFusion _gyroFusion;
  final int _frameRateFps;
  final int _imuSampleRateHz;
  
  final List<FrameMotion> _frameMotions = [];
  
  Quaternion _referenceQuaternion = Quaternion.identity();
  int _frameCounter = 0;
  double _nextFrameTimeMs = 0;
  
  MotionTracker({
    required GyroFusion gyroFusion,
    int frameRateFps = 30,
    int imuSampleRateHz = 100,
  })  : _gyroFusion = gyroFusion,
        _frameRateFps = frameRateFps,
        _imuSampleRateHz = imuSampleRateHz;
  
  /// 初始化：設定參考幀
  void initialize() {
    _referenceQuaternion = _gyroFusion.getQuaternion();
    _frameCounter = 0;
    _nextFrameTimeMs = 0;
    _frameMotions.clear();
  }
  
  /// 每個視頻幀調用一次：更新幀級運動信息
  void updateFrame(int frameId, double frameTimeMs) {
    final currentQ = _gyroFusion.getQuaternion();
    
    // 相對於參考幀的運動四元數
    final relativeQ = _referenceQuaternion.inverse().multiply(currentQ);
    
    // 轉換為歐拉角（度）
    final euler = _quaternionToEuler(relativeQ);
    
    // 計算幀間旋轉角（與前一幀的差）
    final frameDelta = _frameMotions.isEmpty
      ? Quaternion.identity
      : _frameMotions.last.quaternion.inverse().multiply(relativeQ);
    
    _frameMotions.add(FrameMotion(
      frameId: frameId,
      timestampMs: frameTimeMs,
      quaternion: currentQ,
      relativeQuaternion: relativeQ,
      eulerDegrees: euler,
      frameDeltaRotation: frameDelta,
    ));
  }
  
  /// 獲取所有幀的運動
  List<FrameMotion> getAllFrameMotions() => List.from(_frameMotions);
  
  static Vector3 _quaternionToEuler(Quaternion q) {
    // Roll (φ)
    final sinr_cosp = 2 * (q.real * q.i + q.j * q.k);
    final cosr_cosp = 1 - 2 * (q.i * q.i + q.j * q.j);
    final roll = (sinr_cosp).atan2(cosr_cosp) * 180 / 3.14159;
    
    // Pitch (θ)
    final sinp = 2 * (q.real * q.j - q.k * q.i);
    final pitch = sinp.abs() >= 1
      ? (sinp > 0 ? 90 : -90).toDouble()
      : (sinp).asin() * 180 / 3.14159;
    
    // Yaw (ψ)
    final siny_cosp = 2 * (q.real * q.k + q.i * q.j);
    final cosy_cosp = 1 - 2 * (q.j * q.j + q.k * q.k);
    final yaw = (siny_cosp).atan2(cosy_cosp) * 180 / 3.14159;
    
    return Vector3(roll, pitch, yaw);
  }
}

class FrameMotion {
  final int frameId;
  final double timestampMs;
  final Quaternion quaternion;           // 絕對旋轉
  final Quaternion relativeQuaternion;   // 相對於參考幀
  final Vector3 eulerDegrees;            // 歐拉角
  final Quaternion frameDeltaRotation;   // 幀間旋轉
  
  FrameMotion({
    required this.frameId,
    required this.timestampMs,
    required this.quaternion,
    required this.relativeQuaternion,
    required this.eulerDegrees,
    required this.frameDeltaRotation,
  });
  
  Map<String, dynamic> toJson() => {
    'frameId': frameId,
    'timestampMs': timestampMs,
    'quaternion': [quaternion.i, quaternion.j, quaternion.k, quaternion.real],
    'eulerDegrees': [eulerDegrees.x, eulerDegrees.y, eulerDegrees.z],
  };
}
```

### 3️⃣ AffineCompensator 模塊
**文件**：`lib/services/affine_compensator.dart`

```dart
import 'dart:typed_data';
import 'motion_tracker.dart';

/// Affine 變換補償：將運動逆變換應用於視頻幀
class AffineCompensator {
  final List<FrameMotion> _motions;
  final int _frameWidth;
  final int _frameHeight;
  
  // 補償模式
  final CompensationMode _mode;
  final double _smoothingFactor;  // 0.0-1.0，越高越平滑
  
  late List<Mat3> _affineMatrices;
  
  AffineCompensator({
    required List<FrameMotion> motions,
    required int frameWidth,
    required int frameHeight,
    CompensationMode mode = CompensationMode.rotationOnly,
    double smoothingFactor = 0.5,
  })  : _motions = motions,
        _frameWidth = frameWidth,
        _frameHeight = frameHeight,
        _mode = mode,
        _smoothingFactor = smoothingFactor {
    _computeAffineMatrices();
  }
  
  /// 計算每幀的 Affine 補償矩陣
  void _computeAffineMatrices() {
    _affineMatrices = [];
    
    final centerX = _frameWidth / 2.0;
    final centerY = _frameHeight / 2.0;
    
    for (final motion in _motions) {
      final matrix = _computeAffineForMotion(motion, centerX, centerY);
      _affineMatrices.add(matrix);
    }
    
    // 應用平滑濾波
    if (_smoothingFactor > 0) {
      _smoothMatrices();
    }
  }
  
  Mat3 _computeAffineForMotion(
    FrameMotion motion,
    double centerX,
    double centerY,
  ) {
    // 反轉運動：如果相機向右旋轉，我們向左旋轉幀來補償
    final inverseQ = motion.relativeQuaternion.inverse();
    
    // 轉換為旋轉矩陣 (3x3)
    final rotMat = _quaternionToRotationMatrix(inverseQ);
    
    if (_mode == CompensationMode.rotationOnly) {
      return rotMat;
    }
    
    if (_mode == CompensationMode.rotationWithZoom) {
      // 添加縮放補償：旋轉會導致邊界丟失，縮放補償
      final scale = _computeZoomCompensation(inverseQ);
      return rotMat.scale(scale, scale);
    }
    
    // 完整 Affine：旋轉 + 位移補償（需要光流或特征追蹤）
    // 簡化版：僅使用旋轉
    return rotMat;
  }
  
  Mat3 _quaternionToRotationMatrix(Quaternion q) {
    final i = q.i, j = q.j, k = q.k, w = q.real;
    
    return Mat3([
      [1 - 2*(j*j + k*k),     2*(i*j - k*w),     2*(i*k + j*w)],
      [    2*(i*j + k*w), 1 - 2*(i*i + k*k),     2*(j*k - i*w)],
      [    2*(i*k - j*w),     2*(j*k + i*w), 1 - 2*(i*i + j*j)],
    ]);
  }
  
  double _computeZoomCompensation(Quaternion q) {
    // 簡化計算：基於最大旋轉角
    final angle = 2 * (q.i * q.i + q.j * q.j + q.k * q.k).sqrt().acos();
    // 旋轉越大，縮放補償越多
    return 1.0 + (angle / 3.14159) * 0.1;  // 最多 10% 縮放
  }
  
  void _smoothMatrices() {
    // 應用簡單的移動平均濾波
    const window = 5;
    final smoothed = <Mat3>[];
    
    for (int i = 0; i < _affineMatrices.length; i++) {
      final start = (i - window ~/ 2).clamp(0, _affineMatrices.length - 1);
      final end = (i + window ~/ 2 + 1).clamp(0, _affineMatrices.length);
      
      var sum = Mat3.zeros();
      for (int j = start; j < end; j++) {
        sum = sum + _affineMatrices[j];
      }
      smoothed.add(sum * (1.0 / (end - start)));
    }
    
    _affineMatrices = smoothed;
  }
  
  /// 獲取指定幀的補償矩陣
  Mat3 getAffineMatrix(int frameId) {
    if (frameId < 0 || frameId >= _affineMatrices.length) {
      return Mat3.identity();
    }
    return _affineMatrices[frameId];
  }
  
  /// 獲取所有矩陣（用於導出）
  List<Map<String, dynamic>> exportMatrices() {
    return _affineMatrices.asMap().entries.map((e) {
      return {
        'frameId': e.key,
        'affineMatrix': e.value.toList(),
        'confidence': 0.95,  // 簡化版，實際應基於傳感器信噪比
      };
    }).toList();
  }
}

enum CompensationMode {
  rotationOnly,           // 僅旋轉補償
  rotationWithZoom,       // 旋轉 + 縮放補償
  fullAffine,            // 完整仿射（旋轉 + 位移 + 縮放）
}

class Mat3 {
  final List<List<double>> data;  // 3x3 矩陣
  
  Mat3(this.data);
  
  static Mat3 identity() => Mat3([
    [1, 0, 0],
    [0, 1, 0],
    [0, 0, 1],
  ]);
  
  static Mat3 zeros() => Mat3([
    [0, 0, 0],
    [0, 0, 0],
    [0, 0, 0],
  ]);
  
  Mat3 operator +(Mat3 other) => Mat3([
    [data[0][0] + other.data[0][0], data[0][1] + other.data[0][1], data[0][2] + other.data[0][2]],
    [data[1][0] + other.data[1][0], data[1][1] + other.data[1][1], data[1][2] + other.data[1][2]],
    [data[2][0] + other.data[2][0], data[2][1] + other.data[2][1], data[2][2] + other.data[2][2]],
  ]);
  
  Mat3 operator *(double s) => Mat3([
    [data[0][0] * s, data[0][1] * s, data[0][2] * s],
    [data[1][0] * s, data[1][1] * s, data[1][2] * s],
    [data[2][0] * s, data[2][1] * s, data[2][2] * s],
  ]);
  
  Mat3 scale(double sx, double sy) => Mat3([
    [data[0][0] * sx, data[0][1] * sx, data[0][2] * sx],
    [data[1][0] * sy, data[1][1] * sy, data[1][2] * sy],
    [data[2][0], data[2][1], data[2][2]],
  ]);
  
  List<List<double>> toList() => data;
}
```

---

## 🎯 集成方案

### 方案 A：後處理（推薦初期）
```
1. 錄制視頻 + 收集 IMU 數據（現有系統）
2. 錄制結束後：
   a. 運行 GyroFusion → 估計相機運動
   b. 運行 MotionTracker → 逐幀追蹤
   c. 運行 AffineCompensator → 計算補償矩陣
   d. 導出 JSON 參數
3. 使用 OpenCV 或 FFmpeg 應用變換
4. 可選：集成到 FFmpeg 濾鏡參數
```

### 方案 B：實時處理（高級）
```
1. 錄制時：
   a. 捕獲攝像頭幀 → GPU 紋理
   b. 實時運行 GyroFusion → Quaternion
   c. 實時計算 Affine 矩陣 → GPU uniform
   d. 應用 GPU 著色器進行變換
   e. 編碼修改後的幀 → 視頻編碼器
2. 優點：實時預覽 + 無後處理延遲
3. 缺點：較高計算負荷、需要 GPU 支援
```

### 方案 C：混合（最平衡）
```
1. 錄制時收集數據但不修改幀
2. 播放時應用軟件濾鏡（VideoPlayer + ShaderMask）
3. 最終導出時使用 FFmpeg 應用
4. 優點：靈活 + 可反覆調整 + 無額外延遲
```

---

## 📱 Flutter 集成示例

### 在 RecordingSessionPage 中添加

```dart
// 在 _RecordingSessionPageState 中

late GyroFusion _gyroFusion;
late MotionTracker _motionTracker;
late AffineCompensator? _affineCompensator;

@override
void initState() {
  super.initState();
  _gyroFusion = GyroFusion();
  _motionTracker = MotionTracker(
    gyroFusion: _gyroFusion,
    frameRateFps: 30,
    imuSampleRateHz: 100,
  );
}

Future<void> _triggerRecording() async {
  // 開始錄制
  await _cameraController!.startVideoRecording();
  
  // 啟動 Gyro 融合
  _gyroFusion.start();
  _gyroFusion.calibrate();  // 標定 1 秒
  
  _motionTracker.initialize();
  
  // 監聽視頻幀（假設有幀回調）
  // 實際應通過 camera 插件的幀流
  _frameStreamSubscription = _getCameraFrameStream().listen((frameInfo) {
    _motionTracker.updateFrame(
      frameInfo.frameId,
      frameInfo.timestampMs,
    );
  });
}

Future<void> _triggerStop() async {
  _gyroFusion.dispose();
  await _frameStreamSubscription.cancel();
  
  // 停止錄制
  final videoFile = await _cameraController!.stopVideoRecording();
  
  // 後處理：計算補償矩陣
  final motions = _motionTracker.getAllFrameMotions();
  _affineCompensator = AffineCompensator(
    motions: motions,
    frameWidth: 720,
    frameHeight: 1280,
    mode: CompensationMode.rotationWithZoom,
    smoothingFactor: 0.7,
  );
  
  // 導出參數
  final params = _affineCompensator!.exportMatrices();
  await _saveAffineParameters(videoFile.path, params);
}

Future<void> _saveAffineParameters(
  String videoPath,
  List<Map<String, dynamic>> matrices,
) async {
  final jsonData = {
    'metadata': {
      'recordingStartTime': DateTime.now().toIso8601String(),
      'frameRate': 30,
      'compensationMode': 'rotationWithZoom',
    },
    'frames': matrices,
  };
  
  final paramsFile = File(videoPath.replaceAll('.mp4', '_affine.json'));
  await paramsFile.writeAsString(jsonEncode(jsonData));
}
```

---

## 🔬 效能指標

| 指標 | 目標值 | 說明 |
|------|--------|------|
| **陀螺儀延遲** | < 20ms | 傳感器讀取到融合的延遲 |
| **運動估計精度** | ± 0.5° | 相對於光學追蹤的角誤差 |
| **矩陣平滑度** | SNR > 20dB | 濾波後的穩定性 |
| **計算負荷** | < 5% CPU | 後處理模式下 |
| **實時模式負荷** | < 15% GPU | GPU 著色器執行時間 |
| **時間戳同步** | ± 1ms | 視頻幀與 IMU 數據同步 |

---

## 🎓 參考文獻

1. **四元數積分**：Madgwick, S. O., et al. "An efficient orientation filter for inertial and inertial/magnetic sensor arrays." Report x-io and University of Bristol (2010).

2. **Affine 變換**：Hartley, R., & Zisserman, A. (2003). Multiple view geometry in computer vision.

3. **視頻穩定化**：Liu, S., et al. "Bundled camera paths for video stabilization." TOG 31.4 (2012).

4. **MeshFlow 對比**：Liu, S., et al. "MeshFlow: Minimum Latency Online Video Stabilization." ECCV 2016.

---

## ✅ 檢查清單

- [ ] 實現 GyroFusion 模塊（四元數積分）
- [ ] 實現 MotionTracker 模塊（幀級追蹤）
- [ ] 實現 AffineCompensator 模塊（矩陣計算）
- [ ] 在 RecordingSessionPage 集成
- [ ] 添加後處理管道（JSON 導出）
- [ ] 測試時間戳同步精度
- [ ] 與現有 FFmpeg 參數對比測試
- [ ] 性能分析與優化
- [ ] 編寫單元測試
- [ ] 文檔與使用說明

---

## 🚀 後續優化方向

1. **光學流 (Optical Flow)**：增強位移估計
2. **特征點追蹤**：改進邊界像素的穩定性
3. **機器學習**：自動標定陀螺儀參數
4. **多 IMU 融合**：結合外置 BLE IMU 與手機傳感器
5. **實時預覽**：在錄制時顯示穩定化效果

---

**版本**: 1.0  
**日期**: 2026-02-04  
**維護者**: AI Assistant  
