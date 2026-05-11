from __future__ import annotations

import csv
import json
import shutil
import time
from dataclasses import dataclass
from pathlib import Path
from typing import List, Tuple

import cv2
import mediapipe as mp
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.signal import find_peaks, medfilt

from golf_impact.audio import extract_audio_amplitude
from golf_impact.impact import _interp_nan, _moving_average as impact_moving_average
from golf_impact.long_cli import _draw_pose_skeleton, _probe_rotation, _rotate_frame

# =========================
# golf_impact_detection_v3_fast
# =========================
# New strategy:
# 1) Build denoised speed/audio signals.
# 2) find_peaks on each signal independently.
# 3) Intersect peaks by time-neighborhood.

VIDEO_PATH = r"D:\Projects\golf_score_app\python\Test_data\swing.mp4"
OUTPUT_DIR = r"D:\Projects\golf_score_app\python\Test_data\long_record\detectresult_v3_fast_peak_intersection"

DET_CONF = 0.5
TRACK_CONF = 0.5

# Signal processing
SPEED_MEDIAN_KERNEL = 7
SPEED_SMOOTH_WIN = 7
SPEED_BASELINE_KERNEL = 121

AUDIO_MEDIAN_KERNEL = 9
AUDIO_SMOOTH_WIN = 9
AUDIO_BASELINE_KERNEL = 151

# Peak detection
PEAK_DISTANCE_SEC = 0.45
INTERSECT_TOLERANCE_SEC = 0.33

SPEED_HEIGHT_PERCENTILE = 92.0
SPEED_MIN_HEIGHT = 0.8
SPEED_PROM_SCALE = 2.5

AUDIO_HEIGHT_PERCENTILE = 90.0
AUDIO_MIN_HEIGHT = 0.04
AUDIO_PROM_SCALE = 2.0

# Segment export
CLIP_PRE_SEC = 2.5
CLIP_POST_SEC = 2.5

ENABLE_GPU = True
FAST_POSE_LONG_SIDE = 720
FAST_POSE_MODEL_COMPLEXITY = 0
EXPORT_RAW_SEGMENT = False


@dataclass
class MatchPeak:
    hit_idx: int
    speed_frame: int
    audio_frame: int
    hit_frame: int
    delta_frames: int
    delta_sec: float
    speed_value: float
    audio_value: float


def _extract_right_wrist_series_fast(video_path: str, det_conf: float, track_conf: float) -> dict:
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 1e-6:
        fps = 30.0
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    rotation = _probe_rotation(video_path)
    out_w, out_h = (height, width) if abs(rotation) == 90 else (width, height)

    right_x: List[float] = []
    right_y: List[float] = []
    with mp.solutions.pose.Pose(
        static_image_mode=False,
        model_complexity=FAST_POSE_MODEL_COMPLEXITY,
        min_detection_confidence=det_conf,
        min_tracking_confidence=track_conf,
    ) as pose:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frame = _rotate_frame(frame, rotation)
            h, w = frame.shape[:2]
            if max(h, w) > FAST_POSE_LONG_SIDE:
                s = FAST_POSE_LONG_SIDE / float(max(h, w))
                frame_in = cv2.resize(frame, (int(round(w * s)), int(round(h * s))), interpolation=cv2.INTER_AREA)
            else:
                frame_in = frame
            rgb = cv2.cvtColor(frame_in, cv2.COLOR_BGR2RGB)
            r = pose.process(rgb)
            if r.pose_landmarks:
                rw = r.pose_landmarks.landmark[16]
                if rw.visibility >= 0.2:
                    right_x.append(float(rw.x * w))
                    right_y.append(float(rw.y * h))
                else:
                    right_x.append(np.nan)
                    right_y.append(np.nan)
            else:
                right_x.append(np.nan)
                right_y.append(np.nan)
    cap.release()

    x = impact_moving_average(_interp_nan(np.array(right_x, dtype=float)), 5)
    y = impact_moving_average(_interp_nan(np.array(right_y, dtype=float)), 5)
    speed = np.zeros_like(y)
    if len(y) > 1:
        dx = np.diff(x)
        dy = np.diff(y)
        speed[1:] = np.sqrt(dx * dx + dy * dy)
    speed = impact_moving_average(speed, 5)
    return {
        "right_y": y,
        "speed": speed,
        "fps": float(fps),
        "frame_count": frame_count,
        "width": out_w,
        "height": out_h,
        "rotation": rotation,
    }


def _odd(k: int) -> int:
    k = max(1, int(k))
    return k if (k % 2 == 1) else (k + 1)


def _moving_average(x: np.ndarray, window: int) -> np.ndarray:
    w = max(1, int(window))
    if w <= 1 or len(x) == 0:
        return x.copy()
    pad = w // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    ker = np.ones(w, dtype=float) / float(w)
    return np.convolve(xp, ker, mode="valid")


def _denoise_signal(raw: np.ndarray, median_kernel: int, smooth_win: int, baseline_kernel: int) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    med = medfilt(raw, kernel_size=_odd(median_kernel))
    smooth = _moving_average(med, smooth_win)
    baseline = medfilt(smooth, kernel_size=_odd(baseline_kernel))
    denoise = np.clip(smooth - baseline, 0.0, None)
    return smooth, baseline, denoise


def _detect_peaks(x: np.ndarray, fps: float, distance_sec: float, height_percentile: float, min_height: float, prom_scale: float) -> Tuple[np.ndarray, dict]:
    if len(x) < 3:
        return np.array([], dtype=int), {
            "height": 0.0,
            "prominence": 0.0,
            "distance_frames": 1,
        }
    med = float(np.median(x))
    mad = float(np.median(np.abs(x - med))) + 1e-6
    height = max(float(np.percentile(x, height_percentile)), float(min_height))
    prominence = max(float(prom_scale * mad), 0.05 * float(np.max(x)))
    distance = max(1, int(distance_sec * fps))
    peaks, props = find_peaks(x, height=height, prominence=prominence, distance=distance)
    return peaks.astype(int), {
        "height": float(height),
        "prominence": float(prominence),
        "distance_frames": int(distance),
        "num_peaks": int(len(peaks)),
        "peak_heights_mean": float(np.mean(props.get("peak_heights", [0.0])) if len(peaks) else 0.0),
    }


def _intersect_peaks(speed_peaks: np.ndarray, audio_peaks: np.ndarray, speed_sig: np.ndarray, audio_sig: np.ndarray, fps: float, tol_sec: float) -> List[MatchPeak]:
    tol = max(1, int(tol_sec * fps))
    audio_used: set[int] = set()
    matches: List[MatchPeak] = []

    for s in speed_peaks:
        candidates = [a for a in audio_peaks if abs(int(a) - int(s)) <= tol and int(a) not in audio_used]
        if not candidates:
            continue
        a = min(candidates, key=lambda t: abs(int(t) - int(s)))
        audio_used.add(int(a))
        hit = int(round((int(s) + int(a)) * 0.5))
        d = int(a) - int(s)
        matches.append(
            MatchPeak(
                hit_idx=0,
                speed_frame=int(s),
                audio_frame=int(a),
                hit_frame=int(hit),
                delta_frames=int(d),
                delta_sec=float(d / max(fps, 1e-6)),
                speed_value=float(speed_sig[int(s)]),
                audio_value=float(audio_sig[int(a)]),
            )
        )

    matches.sort(key=lambda m: m.hit_frame)
    for i, m in enumerate(matches, start=1):
        m.hit_idx = i
    return matches


def _save_signal_csv(path: Path, fps: float, speed_raw: np.ndarray, speed_smooth: np.ndarray, speed_base: np.ndarray, speed_dn: np.ndarray, audio_raw: np.ndarray, audio_smooth: np.ndarray, audio_base: np.ndarray, audio_dn: np.ndarray):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow([
            "frame",
            "time_sec",
            "speed_raw",
            "speed_smooth",
            "speed_baseline",
            "speed_denoised",
            "audio_raw",
            "audio_smooth",
            "audio_baseline",
            "audio_denoised",
        ])
        n = len(speed_raw)
        for i in range(n):
            w.writerow([
                i,
                i / max(fps, 1e-6),
                float(speed_raw[i]),
                float(speed_smooth[i]),
                float(speed_base[i]),
                float(speed_dn[i]),
                float(audio_raw[i]),
                float(audio_smooth[i]),
                float(audio_base[i]),
                float(audio_dn[i]),
            ])


def _save_peak_csv(path: Path, matches: List[MatchPeak]):
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["hit_idx", "speed_frame", "audio_frame", "hit_frame", "delta_frames", "delta_sec", "speed_value", "audio_value"])
        for m in matches:
            w.writerow([m.hit_idx, m.speed_frame, m.audio_frame, m.hit_frame, m.delta_frames, m.delta_sec, m.speed_value, m.audio_value])


def _plot_signal(path: Path, fps: float, raw: np.ndarray, smooth: np.ndarray, dn: np.ndarray, peaks: np.ndarray, matches: List[MatchPeak], title: str, ylabel: str):
    t = np.arange(len(raw), dtype=float) / max(fps, 1e-6)
    plt.figure(figsize=(18, 6))
    plt.plot(t, raw, color="#4f4f4f", linewidth=0.8, label=f"{ylabel}_raw")
    plt.plot(t, smooth, color="#5dade2", linewidth=1.2, label=f"{ylabel}_smooth")
    plt.plot(t, dn, color="#00ff66", linewidth=1.0, label=f"{ylabel}_denoised")
    if len(peaks) > 0:
        plt.scatter(t[peaks], dn[peaks], s=20, color="#ffd166", label=f"{ylabel}_peaks")
    hit_frames = np.array([m.hit_frame for m in matches], dtype=int)
    if len(hit_frames) > 0:
        plt.scatter(t[hit_frames], dn[hit_frames], s=30, color="#ff4d6d", label="intersection_hits")
    plt.title(title)
    plt.xlabel("Time (sec)")
    plt.ylabel(ylabel)
    plt.grid(alpha=0.25)
    plt.legend(loc="upper right")
    plt.tight_layout()
    plt.savefig(path, dpi=160)
    plt.close()


def _export_segments(video_path: str, out_root: Path, matches: List[MatchPeak], fps: float, width: int, height: int, rotation: int) -> Tuple[bool, float]:
    t0 = time.perf_counter()
    seg_root = out_root / "segments"
    seg_root.mkdir(parents=True, exist_ok=True)
    total_root = out_root / "total_hit"
    total_root.mkdir(parents=True, exist_ok=True)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    use_gpu = False
    if ENABLE_GPU and hasattr(cv2, "cuda"):
        try:
            use_gpu = int(cv2.cuda.getCudaEnabledDeviceCount()) > 0
        except Exception:
            use_gpu = False

    with mp.solutions.pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        for m in matches:
            start = max(0, int(m.hit_frame - CLIP_PRE_SEC * fps))
            end = min(frame_count - 1, int(m.hit_frame + CLIP_POST_SEC * fps))
            case = f"hit_{m.hit_idx:04d}"
            case_dir = seg_root / case
            case_dir.mkdir(parents=True, exist_ok=True)
            out_mp4 = case_dir / f"{case}.mp4"
            out_skel = case_dir / f"{case}_skeleton.mp4"

            writer = cv2.VideoWriter(str(out_mp4), fourcc, fps, (width, height)) if EXPORT_RAW_SEGMENT else None
            writer_skel = cv2.VideoWriter(str(out_skel), fourcc, fps, (width, height))
            cap.set(cv2.CAP_PROP_POS_FRAMES, start)
            f = start
            while f <= end:
                ok, frame = cap.read()
                if not ok:
                    break
                frame = _rotate_frame(frame, rotation)
                if writer is not None:
                    raw = frame.copy()
                    cv2.putText(raw, f"HIT {m.hit_idx}", (20, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)
                    cv2.putText(raw, f"Frame {f}", (20, 68), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
                    cv2.putText(
                        raw,
                        f"SpeedPeak {m.speed_frame}  AudioPeak {m.audio_frame}",
                        (20, 102),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.65,
                        (255, 220, 0),
                        2,
                    )
                    cv2.putText(raw, f"HitFrame {m.hit_frame}", (20, 132), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 220, 0), 2)
                    writer.write(raw)

                skel = frame.copy()
                if use_gpu:
                    gm = cv2.cuda_GpuMat()
                    gm.upload(skel)
                    rgb = cv2.cuda.cvtColor(gm, cv2.COLOR_BGR2RGB).download()
                else:
                    rgb = cv2.cvtColor(skel, cv2.COLOR_BGR2RGB)
                pose_result = pose.process(rgb)
                _draw_pose_skeleton(skel, pose_result)
                cv2.putText(skel, f"HIT {m.hit_idx}", (20, 34), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 255, 0), 2)
                cv2.putText(skel, f"Frame {f}", (20, 68), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2)
                cv2.putText(
                    skel,
                    f"SpeedPeak {m.speed_frame}  AudioPeak {m.audio_frame}",
                    (20, 102),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    0.65,
                    (255, 220, 0),
                    2,
                )
                cv2.putText(skel, f"HitFrame {m.hit_frame}", (20, 132), cv2.FONT_HERSHEY_SIMPLEX, 0.65, (255, 220, 0), 2)
                writer_skel.write(skel)
                f += 1
            if writer is not None:
                writer.release()
            writer_skel.release()

            # total_hit keeps skeleton-only clips
            shutil.copy2(out_skel, total_root / f"{case}_skeleton.mp4")

            meta = {
                "hit_idx": m.hit_idx,
                "speed_frame": m.speed_frame,
                "audio_frame": m.audio_frame,
                "hit_frame": m.hit_frame,
                "delta_frames": m.delta_frames,
                "delta_sec": m.delta_sec,
                "start_frame": start,
                "end_frame": end,
                "start_sec": start / max(fps, 1e-6),
                "end_sec": end / max(fps, 1e-6),
                "clip_raw": str(out_mp4),
                "clip_skeleton": str(out_skel),
            }
            with (case_dir / "segment_meta.json").open("w", encoding="utf-8") as fmeta:
                json.dump(meta, fmeta, indent=2, ensure_ascii=False)

    cap.release()
    return use_gpu, float(time.perf_counter() - t0)


def run() -> int:
    t_all0 = time.perf_counter()
    root = Path(__file__).resolve().parent
    out_dir = root / OUTPUT_DIR
    out_dir.mkdir(parents=True, exist_ok=True)

    t0 = time.perf_counter()
    series = _extract_right_wrist_series_fast(str(root / VIDEO_PATH), DET_CONF, TRACK_CONF)
    t_extract_series = float(time.perf_counter() - t0)
    speed_raw = np.asarray(series["speed"], dtype=float)
    fps = float(series["fps"])
    n = int(series["frame_count"])
    width = int(series["width"])
    height = int(series["height"])
    rotation = int(series["rotation"])

    t0 = time.perf_counter()
    audio_raw = np.asarray(extract_audio_amplitude(str(root / VIDEO_PATH), fps=fps, num_frames=n), dtype=float)
    t_extract_audio = float(time.perf_counter() - t0)
    if len(audio_raw) < n:
        audio_raw = np.pad(audio_raw, (0, n - len(audio_raw)), mode="edge")
    if len(audio_raw) > n:
        audio_raw = audio_raw[:n]

    t0 = time.perf_counter()
    speed_smooth, speed_base, speed_dn = _denoise_signal(speed_raw, SPEED_MEDIAN_KERNEL, SPEED_SMOOTH_WIN, SPEED_BASELINE_KERNEL)
    audio_smooth, audio_base, audio_dn = _denoise_signal(audio_raw, AUDIO_MEDIAN_KERNEL, AUDIO_SMOOTH_WIN, AUDIO_BASELINE_KERNEL)
    t_denoise = float(time.perf_counter() - t0)

    t0 = time.perf_counter()
    speed_peaks, speed_cfg = _detect_peaks(speed_dn, fps, PEAK_DISTANCE_SEC, SPEED_HEIGHT_PERCENTILE, SPEED_MIN_HEIGHT, SPEED_PROM_SCALE)
    audio_peaks, audio_cfg = _detect_peaks(audio_dn, fps, PEAK_DISTANCE_SEC, AUDIO_HEIGHT_PERCENTILE, AUDIO_MIN_HEIGHT, AUDIO_PROM_SCALE)
    t_detect_peaks = float(time.perf_counter() - t0)

    t0 = time.perf_counter()
    matches = _intersect_peaks(speed_peaks, audio_peaks, speed_dn, audio_dn, fps, INTERSECT_TOLERANCE_SEC)
    t_intersect = float(time.perf_counter() - t0)

    _save_signal_csv(
        out_dir / "signals.csv",
        fps,
        speed_raw,
        speed_smooth,
        speed_base,
        speed_dn,
        audio_raw,
        audio_smooth,
        audio_base,
        audio_dn,
    )
    _save_peak_csv(out_dir / "intersection_hits.csv", matches)

    np.savetxt(out_dir / "speed_peaks_frames.txt", speed_peaks, fmt="%d")
    np.savetxt(out_dir / "audio_peaks_frames.txt", audio_peaks, fmt="%d")

    _plot_signal(out_dir / "speed_signal_overview.png", fps, speed_raw, speed_smooth, speed_dn, speed_peaks, matches, "V2 Speed Signal", "speed")
    _plot_signal(out_dir / "audio_signal_overview.png", fps, audio_raw, audio_smooth, audio_dn, audio_peaks, matches, "V2 Audio Signal", "audio")

    gpu_used, t_export = _export_segments(str(root / VIDEO_PATH), out_dir, matches, fps, width, height, rotation)
    t_all = float(time.perf_counter() - t_all0)

    summary = {
        "video_path": str((root / VIDEO_PATH).resolve()),
        "fps": fps,
        "frame_count": n,
        "duration_sec": n / max(fps, 1e-6),
        "rotation_applied_deg": rotation,
        "num_speed_peaks": int(len(speed_peaks)),
        "num_audio_peaks": int(len(audio_peaks)),
        "num_intersection_hits": int(len(matches)),
        "intersect_tolerance_sec": float(INTERSECT_TOLERANCE_SEC),
        "gpu_enabled_requested": bool(ENABLE_GPU),
        "gpu_used": bool(gpu_used),
        "timing_sec": {
            "extract_series": t_extract_series,
            "extract_audio": t_extract_audio,
            "denoise": t_denoise,
            "detect_peaks": t_detect_peaks,
            "intersect": t_intersect,
            "export_segments": t_export,
            "total": t_all,
        },
        "speed_peak_config": speed_cfg,
        "audio_peak_config": audio_cfg,
        "hits": [m.__dict__ for m in matches],
    }
    with (out_dir / "summary.json").open("w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    print("[OK] video       :", VIDEO_PATH)
    print("[OK] out_dir     :", out_dir)
    print("[OK] total_hit   :", out_dir / "total_hit")
    print("[OK] fast_pose   :", f"long_side={FAST_POSE_LONG_SIDE}, complexity={FAST_POSE_MODEL_COMPLEXITY}")
    print("[OK] raw_segment :", EXPORT_RAW_SEGMENT)
    print("[OK] gpu_enabled :", ENABLE_GPU)
    print("[OK] gpu_used    :", gpu_used)
    print("[OK] timing(sec):", f"series={t_extract_series:.2f}, audio={t_extract_audio:.2f}, denoise={t_denoise:.2f}, peaks={t_detect_peaks:.2f}, intersect={t_intersect:.2f}, export={t_export:.2f}, total={t_all:.2f}")
    print("[OK] speed_peaks :", len(speed_peaks))
    print("[OK] audio_peaks :", len(audio_peaks))
    print("[OK] hits(v3)    :", len(matches))
    print("[OK] summary     :", out_dir / "summary.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(run())
