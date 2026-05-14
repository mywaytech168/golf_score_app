# 🎬 三種視頻解碼方案對比

## 當前方案 vs 用戶提議

```
【當前】VideoThumbnail + ML Kit
VideoThumbnail.thumbnailFile()
  ├─ FFmpeg 解碼 → YUV
  ├─ libswscale 轉為 RGB
  ├─ libjpeg JPEG 編碼
  ├─ 寫磁盤
  └─ ~50ms per frame

InputImage.fromFilePath(jpeg)
  ├─ 讀磁盤
  ├─ libjpeg JPEG 解碼
  └─ ~10ms

Google ML Kit
  └─ ~30-50ms
─────────────
總計: ~90-110ms ❌ 太慢

【用戶提議】OpenCV + MediaPipe Native
Kotlin/C++: OpenCV 解碼
  ├─ Mat frame = cv2.imread() or VideoCapture
  ├─ cvtColor(BGR → RGB)
  └─ ~8-12ms per frame

Kotlin/C++: MediaPipe Native 推理
  ├─ mediapipe::framework::CalculatorGraph
  ├─ pose 推理
  └─ ~25-35ms

Dart 接收結果
─────────────
總計: ~35-50ms ✅ 快 2x!
```

---

## 三種完整方案評估

### 方案 1: OpenCV + MediaPipe Native ⭐ 最快

```
解碼: cv2.VideoCapture + Mat 操作
推理: MediaPipe C++ Graph
結果: MethodChannel 傳回 Dart

性能:
  ├─ 解碼: 8-12ms
  ├─ 轉換: 1-2ms
  ├─ 推理: 25-35ms
  └─ 總計: 35-50ms per frame

預期:
  單線性: 35-50ms × 450 幀 = 16-23 秒
  並行 3: 16-23 秒 ÷ 3 = 5-8 秒

優點:
  ✅ 最快 (2x vs 當前)
  ✅ 無磁盤 I/O
  ✅ 無 JPEG 開銷
  ✅ 原生控制力強

缺點:
  ❌ APK +70MB (OpenCV 30MB + MediaPipe 50MB)
  ❌ 複雜度高 (C++ JNI 綁定)
  ❌ 維護成本高 (2 個原生庫)

投入:
  ├─ OpenCV 集成: 2-3 小時
  ├─ MediaPipe NDK 綁定: 4-6 小時
  ├─ JNI 橋接: 2-3 小時
  └─ 總計: 8-12 小時
```

---

### 方案 2: MediaExtractor + ML Kit (推薦)

```
解碼: Kotlin MediaExtractor + MediaCodec
    (系統內建，無額外庫)
推理: Google ML Kit (已有)

性能:
  ├─ 解碼 NV21: 10-15ms
  ├─ 轉換: 2-3ms
  ├─ 推理: 30-50ms
  └─ 總計: 45-70ms per frame

預期:
  單線性: 45-70ms × 450 幀 = 20-32 秒
  並行 3: 20-32 秒 ÷ 3 = 7-11 秒

優點:
  ✅ 快速 (1.3x vs 當前)
  ✅ APK 無增加 (使用系統 API)
  ✅ 複雜度中等
  ✅ Google 維護 ML Kit
  ✅ 兼容性好

缺點:
  ⚠️ 比方案 1 慢一點
  ⚠️ 無 MediaPipe 原生控制

投入:
  ├─ MediaExtractor 實現: 3-4 小時
  ├─ NV21 → RGB 轉換: 1-2 小時
  └─ 總計: 4-6 小時
```

---

### 方案 3: OpenCV + ML Kit (折中)

```
解碼: cv2.VideoCapture + Mat
推理: Google ML Kit (Dart)

性能:
  ├─ 解碼 BGR: 8-12ms
  ├─ 轉換 BGR→RGB: 2-3ms
  ├─ Mat→Bitmap: 5-8ms
  ├─ InputImage.fromBitmap: 2-3ms
  ├─ 推理: 30-50ms
  └─ 總計: 50-80ms per frame

預期:
  單線性: 50-80ms × 450 幀 = 23-36 秒
  並行 3: 23-36 秒 ÷ 3 = 8-12 秒

優點:
  ✅ 快速 (1.5x vs 當前)
  ✅ 比方案 1 簡單 (只用 OpenCV)
  ✅ ML Kit 已驗證穩定
  ✅ APK +30MB (只需 OpenCV)

缺點:
  ⚠️ 仍需 OpenCV 整合
  ⚠️ Mat→Bitmap 轉換有開銷

投入:
  ├─ OpenCV 集成: 2-3 小時
  ├─ JNI Mat 操作: 2-3 小時
  └─ 總計: 4-6 小時
```

---

## 💡 詳細實現 (方案 1: OpenCV + MediaPipe Native)

### Step 1: build.gradle.kts 新增依賴

```kotlin
dependencies {
    // OpenCV
    implementation("org.opencv:opencv-android:4.8.0")
    
    // MediaPipe (預編譯 AAR)
    implementation("com.google.mediapipe:mediapipe_tasks_vision:0.20231211.3")
}
```

### Step 2: Kotlin 層 - 視頻解碼

```kotlin
// android/app/src/main/kotlin/.../PoseAnalyzerService.kt

import org.opencv.core.*
import org.opencv.imgproc.Imgproc
import org.opencv.videoio.VideoCapture

class PoseAnalyzerService {
    fun analyzeVideoFrames(
        videoPath: String,
        callback: (frame: Int, landmarks: DoubleArray) -> Unit
    ) {
        val video = VideoCapture(videoPath)
        
        if (!video.isOpened) {
            throw RuntimeException("Cannot open video: $videoPath")
        }
        
        val fps = video.get(VideoCapture.CAP_PROP_FPS).toInt()
        val frame = Mat()
        var frameIndex = 0
        
        // 時間軸 (每 67ms 取一幀，約 15fps)
        val stepFrames = (fps * 0.067).toInt().coerceAtLeast(1)
        
        while (true) {
            // 讀取幀 (BGR 格式)
            val ok = video.read(frame)
            if (!ok) break
            
            if (frameIndex % stepFrames == 0) {
                // 轉為 RGB
                val rgb = Mat()
                Imgproc.cvtColor(frame, rgb, Imgproc.COLOR_BGR2RGB)
                
                // 推理 (MediaPipe)
                val landmarks = inferPose(rgb)
                
                // 回調
                callback(frameIndex, landmarks)
                
                rgb.release()
            }
            
            frameIndex++
        }
        
        frame.release()
        video.release()
    }
    
    private fun inferPose(rgbMat: Mat): DoubleArray {
        // 1. Mat → Bitmap
        val bitmap = matToBitmap(rgbMat)
        
        // 2. MediaPipe 推理
        val results = mediaPipeDetector.detectPose(bitmap)
        
        // 3. 33 landmarks 序列化
        val landmarks = DoubleArray(33 * 3)  // x, y, z per landmark
        results.landmarks.forEachIndexed { i, landmark ->
            landmarks[i * 3] = landmark.x.toDouble()
            landmarks[i * 3 + 1] = landmark.y.toDouble()
            landmarks[i * 3 + 2] = landmark.z.toDouble()
        }
        
        return landmarks
    }
    
    private fun matToBitmap(mat: Mat): Bitmap {
        val bitmap = Bitmap.createBitmap(
            mat.cols(),
            mat.rows(),
            Bitmap.Config.ARGB_8888
        )
        Utils.matToBitmap(mat, bitmap)
        return bitmap
    }
}
```

### Step 3: MediaPipe 初始化 (C++ / JNI)

```cpp
// android/app/src/main/cpp/pose_detector.cc

#include <mediapipe/tasks/cc/vision/pose_landmarker/pose_landmarker.h>
#include <mediapipe/framework/port/status_macros.h>

using namespace mediapipe::tasks::vision::pose_landmarker;

PoseLandmarker* g_pose_landmarker = nullptr;

extern "C" {
    JNIEXPORT jint JNICALL
    Java_com_example_golf_score_app_PoseAnalyzerService_initMediaPipe(
        JNIEnv* env, jobject /* this */
    ) {
        auto options = std::make_unique<PoseLandmarkerOptions>();
        options->base_options.model_asset_path = 
            "/asset/pose_landmarker.task";  // MediaPipe 模型文件
        
        auto landmarker = PoseLandmarker::CreateFromOptions(*options);
        if (!landmarker.ok()) {
            return -1;
        }
        
        g_pose_landmarker = landmarker.value().release();
        return 0;  // 成功
    }
    
    JNIEXPORT jobjectArray JNICALL
    Java_com_example_golf_score_app_PoseAnalyzerService_detectPose(
        JNIEnv* env, jobject /* this */,
        jobject bitmap
    ) {
        // 1. Bitmap → OpenCV Mat
        cv::Mat mat = bitmapToMat(env, bitmap);
        
        // 2. Mat → MediaPipe Image
        auto image = std::make_unique<mediapipe::Image>(
            mediapipe::formats::MatToImage(mat)
        );
        
        // 3. 推理
        auto detection_result = 
            g_pose_landmarker->Detect(*image);
        
        // 4. 結果序列化 (返回 float array)
        jobfloatArray result = env->NewFloatArray(
            33 * 3  // 33 landmarks, x,y,z each
        );
        // ... 填充陣列 ...
        
        return result;
    }
}
```

### Step 4: Dart 層調用

```dart
// lib/services/native_pose_analyzer.dart

import 'package:flutter/services.dart';

class NativePoseAnalyzer {
  static const platform = MethodChannel('com.example.golf_score_app/pose_analyzer');
  
  Future<List<List<double>>> analyzeVideo({
    required String videoPath,
    void Function(int frame, double progress)? onProgress,
  }) async {
    try {
      // 初始化 MediaPipe
      await platform.invokeMethod('initMediaPipe');
      
      // 開始逐幀分析
      final subscription = platform.setMethodCallHandler((call) async {
        if (call.method == 'onPoseDetected') {
          final frame = call.arguments['frame'] as int;
          final landmarks = call.arguments['landmarks'] as List;
          
          onProgress?.call(frame, frame / totalFrames);
          
          return {'ack': true};
        }
      });
      
      // 啟動分析
      final result = await platform.invokeMethod(
        'analyzeVideoFrames',
        {'videoPath': videoPath},
      );
      
      subscription.cancel();
      
      return result as List<List<double>>;
    } on PlatformException catch (e) {
      debugPrint("Failed to analyze video: ${e.message}");
      return [];
    }
  }
}
```

### Step 5: 性能對比

```
【解碼性能】per frame

1. VideoThumbnail (當前)
   FFmpeg 解碼 + JPEG 編碼 + 磁盤 I/O
   → ~50ms

2. OpenCV VideoCapture
   直接 Mat 操作，無 JPEG
   → ~8-12ms (5x 快!)

3. Kotlin MediaExtractor
   MediaCodec 硬解碼
   → ~10-15ms (4x 快)

【總推理時間】

1. 當前 (VideoThumbnail + ML Kit)
   50ms (解碼) + 10ms (JPEG) + 30-50ms (推理)
   = 90-110ms
   × 450 幀 = 40-50 秒

2. OpenCV + MediaPipe Native
   8-12ms (解碼) + 25-35ms (推理)
   = 35-50ms
   × 450 幀 = 16-23 秒 (2.5x 快!)
   並行 3 = 5-8 秒 (10x 快!)

3. MediaExtractor + ML Kit
   10-15ms (解碼) + 30-50ms (推理)
   = 45-70ms
   × 450 幀 = 20-32 秒 (1.5x 快)
   並行 3 = 7-11 秒 (6x 快!)
```

---

## 🎯 建議決策

| 因素 | 方案 1 (OpenCV+MP) | 方案 2 (MediaExtractor+ML Kit) | 方案 3 (OpenCV+ML Kit) |
|------|-------------|------------------|----------|
| 速度 | 最快 (35-50ms) | 中等 (45-70ms) | 中等 (50-80ms) |
| APK 大小 | +70MB ❌ | +0MB ✅ | +30MB ⚠️ |
| 複雜度 | 高 (C++/JNI) | 中等 (Kotlin) | 中等 (C++) |
| 投入時間 | 8-12 小時 | 4-6 小時 | 4-6 小時 |
| 穩定性 | 中 (新整合) | 高 (官方 API) | 高 (官方 API) |
| 推薦度 | 🌟🌟 (如果能接受 APK +70MB) | 🌟🌟🌟 ⭐ 最推薦! | 🌟🌟 |

---

## 💡 我的建議

### 如果想要最好的性能 → 方案 2 (MediaExtractor + ML Kit)

✅ 理由:
- 投入 4-6 小時 vs 8-12 小時
- APK 無增加 (非常重要)
- 速度提升 1.5x (足夠)
- 系統 API，穩定性高
- 後續維護簡單

**預期結果:**
```
30 秒視頻分析
  當前: 45 秒
  優化後: 7-11 秒 (6x 加速!)
```

### 如果追求極致性能 + 預算充足 → 方案 1 (OpenCV + MediaPipe)

✅ 理由:
- 最快速度 (35-50ms per frame)
- 完全原生控制
- 可做後續深度優化

❌ 代價:
- APK +70MB (嚴重)
- 維護複雜
- 8-12 小時投入

---

## 🏁 最終建議

**採用方案 2: MediaExtractor + ML Kit**

1. **立即實施 (4-6 小時)**
   - Kotlin MediaExtractor 直接解碼
   - 替代 VideoThumbnail
   - 結果: 45秒 → 7-11秒

2. **後續優化 (1 小時)**
   - 加入並行處理 (3-5 幀同時)
   - 進一步加速

3. **選擇性優化 (可選)**
   - 若發現瓶頸在推理 → 考慮改用 MediaPipe Native
   - 若性能夠用 → 保持當前方案

---

## 我能幫什麼?

你想要:
- [ ] A. 實現方案 2 (MediaExtractor + ML Kit)?
- [ ] B. 實現方案 1 (OpenCV + MediaPipe Native)?
- [ ] C. 實現方案 3 (OpenCV + ML Kit)?
- [ ] D. 只想檢查可行性，暫不實施?
