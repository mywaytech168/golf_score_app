from __future__ import annotations

import csv
import json
import subprocess
from pathlib import Path
from typing import Dict, Iterable, List

import cv2
import mediapipe as mp
import numpy as np

# =========================
# Standalone config (edit here)
# =========================
# MODE:
#   "extract" -> run pose model, export CSV + skeleton video
#   "render"  -> use existing CSV + raw video to rebuild skeleton video (no model)
MODE = "extract"

# Input raw video (relative to this .py directory or absolute path)
# VIDEO_PATH = "golf_data/test2.MOV"
VIDEO_PATH = r"D:\Projects\golf_score_app\python\hit_1.mp4"


# Extract outputs
OUTPUT_DIR = r"D:\Projects\golf_score_app\python\hit_catch\pose_export"
POSE_CSV_NAME = "pose_landmarks.csv"
SKELETON_VIDEO_NAME = "skeleton_overlay.mp4"

# Render-only inputs/outputs
# If left empty in render mode, it will fallback to OUTPUT_DIR/POSE_CSV_NAME.
RENDER_CSV_PATH = r"D:\Projects\golf_score_app\python\pose_export\hit_catch\pose_landmarks.csv"
RENDER_OUTPUT_VIDEO = r"D:\Projects\golf_score_app\python\pose_export\hit_catch\pose_export\skeleton_overlay_from_csv.mp4"

# Pose / draw params
DET_CONF = 0.5
TRACK_CONF = 0.5
MODEL_COMPLEXITY = 0
MAX_LONG_SIDE = 720
MIN_VISIBILITY = 0.2
DRAW_INDEX = False

LANDMARK_COUNT = 33
SKELETON_EDGES = [
    # upper body
    (11, 12),
    (11, 13),
    (13, 15),
    (12, 14),
    (14, 16),
    (11, 23),
    (12, 24),
    (23, 24),
    # legs
    (23, 25),
    (25, 27),
    (24, 26),
    (26, 28),
    # feet
    (27, 29),
    (29, 31),
    (27, 31),
    (28, 30),
    (30, 32),
    (28, 32),
]


def _probe_rotation(video_path: str) -> int:
    cmd = ["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", video_path]
    print(f"🔍 [DEBUG] Probing rotation for: {video_path}")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            print(f"⚠️  [DEBUG] ffprobe failed with return code {proc.returncode}")
            return 0
        data = json.loads(proc.stdout)
        streams = data.get("streams", [])
        print(f"📊 [DEBUG] Found {len(streams)} stream(s)")
        v = next((s for s in streams if s.get("codec_type") == "video"), None)
        if not v:
            print(f"⚠️  [DEBUG] No video stream found")
            return 0
        print(f"📹 [DEBUG] Video stream found: {v.get('width')}x{v.get('height')}")
        side_data = v.get("side_data_list", [])
        print(f"📋 [DEBUG] side_data_list: {side_data}")
        for sd in side_data:
            if "rotation" in sd:
                rot = int(round(float(sd["rotation"])))
                print(f"✅ [DEBUG] Found rotation in side_data: {rot}°")
                rot = ((rot + 360) % 360)
                if rot > 180:
                    rot -= 360
                print(f"✅ [DEBUG] Normalized rotation: {rot}°")
                return rot
        tags = v.get("tags", {})
        print(f"🏷️  [DEBUG] tags: {tags}")
        if "rotate" in tags:
            rot = int(round(float(tags["rotate"])))
            print(f"✅ [DEBUG] Found rotation in tags: {rot}°")
            rot = ((rot + 360) % 360)
            if rot > 180:
                rot -= 360
            print(f"✅ [DEBUG] Normalized rotation: {rot}°")
            return rot
        print(f"⚠️  [DEBUG] No rotation metadata found")
    except Exception as e:
        print(f"❌ [DEBUG] Exception in _probe_rotation: {e}")
        return 0
    return 0


def _rotate_frame(frame, rotation: int):
    if rotation == -90:
        print(f"🔄 [DEBUG] Applying cv2.ROTATE_90_CLOCKWISE to frame (shape: {frame.shape})")
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if rotation == 90:
        print(f"🔄 [DEBUG] Applying cv2.ROTATE_90_COUNTERCLOCKWISE to frame (shape: {frame.shape})")
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if abs(rotation) == 180:
        print(f"🔄 [DEBUG] Applying cv2.ROTATE_180 to frame (shape: {frame.shape})")
        return cv2.rotate(frame, cv2.ROTATE_180)
    if rotation != 0:
        print(f"⚠️  [DEBUG] Unsupported rotation: {rotation}°, returning frame as-is")
    return frame


def _csv_header() -> List[str]:
    header = ["frame", "time_sec"]
    for i in range(LANDMARK_COUNT):
        header.extend(
            [
                f"lm{i}_x_norm",
                f"lm{i}_y_norm",
                f"lm{i}_z",
                f"lm{i}_visibility",
                f"lm{i}_x_px",
                f"lm{i}_y_px",
            ]
        )
    return header


def _empty_landmarks_row(frame_idx: int, time_sec: float) -> Dict[str, float]:
    row: Dict[str, float] = {"frame": frame_idx, "time_sec": time_sec}
    for i in range(LANDMARK_COUNT):
        row[f"lm{i}_x_norm"] = np.nan
        row[f"lm{i}_y_norm"] = np.nan
        row[f"lm{i}_z"] = np.nan
        row[f"lm{i}_visibility"] = 0.0
        row[f"lm{i}_x_px"] = np.nan
        row[f"lm{i}_y_px"] = np.nan
    return row


def _row_from_landmarks(frame_idx: int, time_sec: float, lms, w: int, h: int) -> Dict[str, float]:
    row: Dict[str, float] = {"frame": frame_idx, "time_sec": time_sec}
    for i in range(LANDMARK_COUNT):
        lm = lms[i]
        x_px = float(lm.x * w)
        y_px = float(lm.y * h)
        row[f"lm{i}_x_norm"] = float(lm.x)
        row[f"lm{i}_y_norm"] = float(lm.y)
        row[f"lm{i}_z"] = float(lm.z)
        row[f"lm{i}_visibility"] = float(lm.visibility)
        row[f"lm{i}_x_px"] = x_px
        row[f"lm{i}_y_px"] = y_px
    return row


def _safe_float(v: object) -> float:
    try:
        return float(v)  # type: ignore[arg-type]
    except (TypeError, ValueError):
        return np.nan


def _get_points_from_row(row: Dict[str, object]) -> List[tuple[float, float, float]]:
    pts: List[tuple[float, float, float]] = []
    for i in range(LANDMARK_COUNT):
        x = _safe_float(row.get(f"lm{i}_x_px"))
        y = _safe_float(row.get(f"lm{i}_y_px"))
        v = _safe_float(row.get(f"lm{i}_visibility"))
        pts.append((x, y, v))
    return pts


def _draw_skeleton(frame, row: Dict[str, object], min_vis: float = 0.2, draw_index: bool = False) -> None:
    pts = _get_points_from_row(row)
    for a, b in SKELETON_EDGES:
        xa, ya, va = pts[a]
        xb, yb, vb = pts[b]
        if va < min_vis or vb < min_vis or not np.isfinite(xa + ya + xb + yb):
            continue
        cv2.line(frame, (int(round(xa)), int(round(ya))), (int(round(xb)), int(round(yb))), (0, 255, 255), 2)

    for i, (x, y, v) in enumerate(pts):
        if v < min_vis or not np.isfinite(x + y):
            continue
        center = (int(round(x)), int(round(y)))
        color = (0, 0, 255) if i == 16 else (0, 255, 0)
        radius = 6 if i == 16 else 4
        cv2.circle(frame, center, radius, color, -1)
        if draw_index:
            cv2.putText(frame, str(i), (center[0] + 5, center[1] - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)


def _iter_frames(video_path: str) -> Iterable[tuple[int, float, np.ndarray, float, int, int]]:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    if fps <= 1e-6:
        fps = 30.0
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    original_width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    original_height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"\n📽️  [DEBUG] _iter_frames START:")
    print(f"   Video: {video_path}")
    print(f"   FPS: {fps}")
    print(f"   Total frames: {total_frames}")
    print(f"   Original dimensions: {original_width}x{original_height}")
    rotation = _probe_rotation(video_path)
    print(f"   Final rotation value: {rotation}°")

    frame_idx = 0
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            if frame_idx == 0:
                print(f"   First frame shape before rotation: {frame.shape}")
            frame = _rotate_frame(frame, rotation)
            if frame_idx == 0:
                print(f"   First frame shape after rotation: {frame.shape}")
            h, w = frame.shape[:2]
            time_sec = frame_idx / fps
            yield frame_idx, time_sec, frame, fps, w, h
            frame_idx += 1
    finally:
        print(f"   Total frames read: {frame_idx}")
        cap.release()


def extract_pose_to_csv_and_video(
    video_path: str,
    csv_path: Path,
    out_video_path: Path,
    det_conf: float,
    track_conf: float,
    model_complexity: int,
    max_long_side: int,
    min_vis: float,
    draw_index: bool,
) -> None:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    out_video_path.parent.mkdir(parents=True, exist_ok=True)

    print(f"🎬 [DEBUG] extract_pose_to_csv_and_video START")
    print(f"   CSV output: {csv_path}")
    print(f"   Video output: {out_video_path}")

    frame_iter = _iter_frames(video_path)
    first = next(frame_iter, None)
    if first is None:
        raise RuntimeError(f"Empty video: {video_path}")

    first_idx, first_t, first_frame, fps, width, height = first
    print(f"   Output video dimensions: {width}x{height} @ {fps} fps")
    writer = cv2.VideoWriter(str(out_video_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))
    if not writer.isOpened():
        print(f"❌ [ERROR] Failed to open VideoWriter for {out_video_path}")
    else:
        print(f"✅ [DEBUG] VideoWriter opened successfully")

    with csv_path.open("w", newline="", encoding="utf-8") as fcsv:
        csv_writer = csv.DictWriter(fcsv, fieldnames=_csv_header())
        csv_writer.writeheader()

        with mp.solutions.pose.Pose(
            static_image_mode=False,
            model_complexity=int(model_complexity),
            min_detection_confidence=float(det_conf),
            min_tracking_confidence=float(track_conf),
        ) as pose:
            def process_one(frame_idx: int, time_sec: float, frame, w: int, h: int):
                if max(h, w) > max_long_side:
                    s = max_long_side / float(max(h, w))
                    small = cv2.resize(frame, (int(round(w * s)), int(round(h * s))), interpolation=cv2.INTER_AREA)
                else:
                    small = frame
                result = pose.process(cv2.cvtColor(small, cv2.COLOR_BGR2RGB))

                if result.pose_landmarks:
                    row = _row_from_landmarks(frame_idx, time_sec, result.pose_landmarks.landmark, w, h)
                else:
                    row = _empty_landmarks_row(frame_idx, time_sec)
                csv_writer.writerow(row)

                draw_frame = frame.copy()
                _draw_skeleton(draw_frame, row, min_vis=min_vis, draw_index=draw_index)
                cv2.putText(draw_frame, f"Frame {frame_idx}", (20, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
                cv2.putText(draw_frame, f"Time {time_sec:.3f}s", (20, 66), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 220, 0), 2)
                writer.write(draw_frame)
            process_one(first_idx, first_t, first_frame, width, height)
            for frame_idx, time_sec, frame, _, w, h in frame_iter:
                process_one(frame_idx, time_sec, frame, w, h)

    writer.release()


def render_video_from_pose_csv(
    video_path: str,
    csv_path: Path,
    out_video_path: Path,
    min_vis: float,
    draw_index: bool,
) -> None:
    rows_by_frame: Dict[int, Dict[str, object]] = {}
    with csv_path.open("r", newline="", encoding="utf-8") as fcsv:
        reader = csv.DictReader(fcsv)
        for row in reader:
            frame_idx = int(float(row["frame"]))
            rows_by_frame[frame_idx] = row

    frame_iter = _iter_frames(video_path)
    first = next(frame_iter, None)
    if first is None:
        raise RuntimeError(f"Empty video: {video_path}")
    _, _, first_frame, fps, width, height = first

    out_video_path.parent.mkdir(parents=True, exist_ok=True)
    writer = cv2.VideoWriter(str(out_video_path), cv2.VideoWriter_fourcc(*"mp4v"), fps, (width, height))

    first_idx, first_t, first_frame, _, _, _ = first
    first_row = rows_by_frame.get(first_idx, _empty_landmarks_row(first_idx, first_t))
    first_draw = first_frame.copy()
    _draw_skeleton(first_draw, first_row, min_vis=min_vis, draw_index=draw_index)
    cv2.putText(first_draw, f"Frame {first_idx}", (20, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
    cv2.putText(first_draw, f"Time {first_t:.3f}s", (20, 66), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 220, 0), 2)
    writer.write(first_draw)

    for frame_idx, time_sec, frame, _, _, _ in frame_iter:
        row = rows_by_frame.get(frame_idx, _empty_landmarks_row(frame_idx, time_sec))
        draw_frame = frame.copy()
        _draw_skeleton(draw_frame, row, min_vis=min_vis, draw_index=draw_index)
        cv2.putText(draw_frame, f"Frame {frame_idx}", (20, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
        cv2.putText(draw_frame, f"Time {time_sec:.3f}s", (20, 66), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 220, 0), 2)
        writer.write(draw_frame)

    writer.release()


def run() -> int:
    root = Path(__file__).resolve().parent
    video_path = Path(VIDEO_PATH)
    if not video_path.is_absolute():
        video_path = (root / video_path).resolve()

    if MODE == "extract":
        out_dir = Path(OUTPUT_DIR)
        if not out_dir.is_absolute():
            out_dir = (root / out_dir).resolve()
        csv_path = out_dir / POSE_CSV_NAME
        out_video_path = out_dir / SKELETON_VIDEO_NAME
        print("\n" + "="*60)
        print("🚀 EXTRACT MODE - Rotation Debug Session")
        print("="*60)
        extract_pose_to_csv_and_video(
            video_path=str(video_path),
            csv_path=csv_path,
            out_video_path=out_video_path,
            det_conf=DET_CONF,
            track_conf=TRACK_CONF,
            model_complexity=MODEL_COMPLEXITY,
            max_long_side=MAX_LONG_SIDE,
            min_vis=MIN_VISIBILITY,
            draw_index=DRAW_INDEX,
        )
        print("\n" + "="*60)
        print("✅ EXTRACTION COMPLETE")
        print("="*60)
        print("[OK] mode       : extract")
        print("[OK] input      :", video_path)
        print("[OK] csv        :", csv_path.resolve())
        print("[OK] skeleton   :", out_video_path.resolve())
        return 0

    if MODE == "render":
        render_csv = Path(RENDER_CSV_PATH) if RENDER_CSV_PATH else Path(OUTPUT_DIR) / POSE_CSV_NAME
        if not render_csv.is_absolute():
            render_csv = (root / render_csv).resolve()
        render_video = Path(RENDER_OUTPUT_VIDEO)
        if not render_video.is_absolute():
            render_video = (root / render_video).resolve()
        render_video_from_pose_csv(
            video_path=str(video_path),
            csv_path=render_csv,
            out_video_path=render_video,
            min_vis=MIN_VISIBILITY,
            draw_index=DRAW_INDEX,
        )
        print("[OK] mode       : render")
        print("[OK] input      :", video_path)
        print("[OK] csv        :", render_csv.resolve())
        print("[OK] skeleton   :", render_video.resolve())
        return 0

    raise RuntimeError(f"Unsupported MODE: {MODE}. Use 'extract' or 'render'.")


if __name__ == "__main__":
    raise SystemExit(run())
