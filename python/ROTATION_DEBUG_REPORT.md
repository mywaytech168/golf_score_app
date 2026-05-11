# 🎬 Rotation Parameter Debug Report

## 📋 Summary

Added comprehensive debug logging to `golf_pose_skeleton_pipeline.py` to trace rotation parameter handling throughout the video processing pipeline.

---

## 🔍 Debug Points Added

### 1. **_probe_rotation() Function** ✅
Tracks ffprobe metadata extraction:
```
📍 Input: Video file path
📍 Outputs:
   - ffprobe command execution status
   - Number of streams found
   - Video stream dimensions
   - side_data_list content (rotation metadata)
   - tags content
   - Normalized rotation value (-180 to 180°)
📍 Messages:
   🔍 [DEBUG] Probing rotation for: {video_path}
   ⚠️  [DEBUG] ffprobe failed with return code {rc}
   📊 [DEBUG] Found {n} stream(s)
   📹 [DEBUG] Video stream found: {w}x{h}
   📋 [DEBUG] side_data_list: {data}
   🏷️  [DEBUG] tags: {tags}
   ✅ [DEBUG] Found rotation in side_data: {rot}°
   ✅ [DEBUG] Found rotation in tags: {rot}°
   ⚠️  [DEBUG] No rotation metadata found
   ❌ [DEBUG] Exception in _probe_rotation: {e}
```

### 2. **_rotate_frame() Function** ✅
Tracks cv2 rotation operations:
```
📍 Input: Frame array + rotation degrees
📍 Output: Rotated frame
📍 Messages:
   🔄 [DEBUG] Applying cv2.ROTATE_90_CLOCKWISE to frame (shape: {shape})
   🔄 [DEBUG] Applying cv2.ROTATE_90_COUNTERCLOCKWISE to frame (shape: {shape})
   🔄 [DEBUG] Applying cv2.ROTATE_180 to frame (shape: {shape})
   ⚠️  [DEBUG] Unsupported rotation: {rot}°, returning frame as-is
```

### 3. **_iter_frames() Function** ✅
Comprehensive frame iteration debug:
```
📍 Input: Video path
📍 Outputs: Frame stream with rotation applied
📍 Messages:
   📹 [DEBUG] _iter_frames START:
      Video: {path}
      FPS: {fps}
      Total frames: {n}
      Original dimensions: {w}x{h}
      Final rotation value: {rot}°
      First frame shape before rotation: {shape}
      First frame shape after rotation: {shape}
      Total frames read: {n}
```

### 4. **extract_pose_to_csv_and_video() Function** ✅
Output configuration debug:
```
📍 Messages:
   🎬 [DEBUG] extract_pose_to_csv_and_video START
      CSV output: {path}
      Video output: {path}
      Output video dimensions: {w}x{h} @ {fps} fps
      ✅ [DEBUG] VideoWriter opened successfully
      ❌ [ERROR] Failed to open VideoWriter for {path}
```

### 5. **run() Function** ✅
Session-level headers:
```
════════════════════════════════════════════════════════════════
🚀 EXTRACT MODE - Rotation Debug Session
════════════════════════════════════════════════════════════════
```

---

## 📊 Test Results

### Video: hit_0016.mp4
```
✅ Rotation Detection
   Original: 1080x1920 (portrait)
   FPS: 30.002
   Total frames: 152
   Rotation detected: 0° (no rotation metadata found)
   
✅ Frame Processing  
   Frame shape: (1920, 1080, 3) - no change (rotation = 0°)
   Output dimensions: 1080x1920
   
✅ Pipeline Result
   ✅ CSV exported: pose_landmarks.csv
   ✅ Video exported: skeleton_overlay.mp4
```

### Video: hit_1.mp4
```
✅ Video Metadata
   Dimensions: 1280x720
   FPS: 30
   Total frames: 150
   Rotation: 0° (no rotation metadata found)
```

---

## 🔄 Rotation Transformation Logic

### Coordinate Transformation (When rotation ≠ 0°)

| Rotation | cv2 Function | Input (x,y) | Output (x',y') | Use Case |
|----------|---|-----------|---------|----------|
| **90°** | `cv2.ROTATE_90_COUNTERCLOCKWISE` | `(x, y)` | `(h - y, x)` | Portrait→Landscape CCW |
| **-90°** | `cv2.ROTATE_90_CLOCKWISE` | `(x, y)` | `(y, w - x)` | Landscape→Portrait CW |
| **180°** | `cv2.ROTATE_180` | `(x, y)` | `(w - x, h - y)` | Upside down |
| **0°** | None | `(x, y)` | `(x, y)` | No rotation |

### Frame Dimension Changes After Rotation

| Original | After ±90° | After 180° | After 0° |
|----------|-----------|-----------|---------|
| `(H, W)` | `(W, H)` | `(H, W)` | `(H, W)` |
| `(1920, 1080)` | `(1080, 1920)` | `(1920, 1080)` | `(1920, 1080)` |

---

## 📍 How to Read Debug Output

### Example 1: Video with 90° Rotation
```
🔍 [DEBUG] Probing rotation for: video.mp4
📊 [DEBUG] Found 1 stream(s)
📹 [DEBUG] Video stream found: 1080x1920
📋 [DEBUG] side_data_list: [{'rotation': 90}]  ← FOUND!
✅ [DEBUG] Found rotation in side_data: 90°
✅ [DEBUG] Normalized rotation: 90°
Final rotation value: 90°                       ← APPLIED!
   First frame shape before rotation: (1920, 1080, 3)
🔄 [DEBUG] Applying cv2.ROTATE_90_COUNTERCLOCKWISE to frame (shape: (1920, 1080, 3))
   First frame shape after rotation: (1080, 1920, 3)  ← DIMENSIONS SWAPPED!
   Output video dimensions: 1920x1080 @ 30 fps  ← NEW OUTPUT SIZE!
```

### Example 2: Video without Rotation (Current)
```
🔍 [DEBUG] Probing rotation for: hit_0016.mp4
📊 [DEBUG] Found 1 stream(s)
📹 [DEBUG] Video stream found: 1080x1920
📋 [DEBUG] side_data_list: []                   ← EMPTY!
🏷️  [DEBUG] tags: {...}
⚠️  [DEBUG] No rotation metadata found
Final rotation value: 0°                        ← NO ROTATION!
   First frame shape before rotation: (1920, 1080, 3)
   First frame shape after rotation: (1920, 1080, 3)  ← NO CHANGE!
   Output video dimensions: 1080x1920 @ 30 fps
```

---

## 🎯 Python vs Kotlin Rotation Implementation Comparison

| Aspect | Python | Kotlin |
|--------|--------|--------|
| **Rotation Detection** | `ffprobe` subprocess | `MediaFormat.KEY_ROTATION` |
| **Metadata Source** | side_data_list / tags | MediaFormat properties |
| **Application** | Frame-level via `cv2.rotate()` | Coordinate-level via `rotateCoord()` |
| **Timing** | During frame read in loop | During drawing operations |
| **Output Format** | MP4 with cv2.VideoWriter | MP4 with MediaMuxer |
| **Performance** | ~pixel rearrangement | ~coordinate math (faster) |

---

## 🧪 Creating Rotated Test Videos

To test rotation handling, create a 90° rotated video:

```bash
# Using ffmpeg (if needed for testing)
ffmpeg -i input.mp4 -vf "transpose=1" -c:a copy output_rotated_90.mp4
# transpose=1 → 90° clockwise
# transpose=2 → 90° counter-clockwise
# transpose=3 → 180°
```

Then modify `VIDEO_PATH` in the script and re-run to see rotation handling in action.

---

## 📝 Debug Checklist

- ✅ Rotation metadata extraction logged
- ✅ Frame rotation operations logged
- ✅ Frame dimension changes logged
- ✅ Output video dimensions logged
- ✅ Pipeline completion status logged
- ✅ All 4 rotation cases (0°, 90°, -90°, 180°) covered
- ✅ Error cases handled with messages

---

## 🚀 Next Steps

1. **Test with rotated video**: Use `ffmpeg -vf transpose` to create 90° rotated test video
2. **Verify coordinate transformation**: Check if landmarks follow rotation correctly
3. **Compare with Kotlin**: Ensure Python and Kotlin produce identical output for same input
4. **Performance baseline**: Measure frame processing time for rotated vs non-rotated
5. **Mobile testing**: Deploy to Android device and verify skeleton overlay matches rotation

---

**Generated**: 2026-05-11 | **Pipeline**: golf_pose_skeleton_pipeline.py | **Status**: ✅ Debug Logging Complete
