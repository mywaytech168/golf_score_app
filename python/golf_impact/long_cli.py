from __future__ import annotations

import argparse
import csv
import json
import os
import subprocess
from dataclasses import asdict, dataclass
from typing import Dict, List, Tuple

import cv2
import mediapipe as mp
import numpy as np
from scipy.signal import find_peaks

from .audio import extract_audio_amplitude
from .impact import _interp_nan, _moving_average


@dataclass
class SwingEvent:
    idx: int
    top_frame: int
    fast_frame: int
    down_frame: int
    start_frame: int
    end_frame: int
    score: float
    keep: bool = True
    reject_reason: str = ""
    pos_valid_ratio: float = 0.0
    pos_drift_px: float = 0.0
    pos_spread_px: float = 0.0
    anchor_dist_px: float = 0.0
    audio_peak: float = 0.0
    audio_confirmed: bool = False


SKELETON_EDGES = [
    (11, 12),  # shoulders
    (11, 13),
    (13, 15),  # left arm
    (12, 14),
    (14, 16),  # right arm
    (11, 23),
    (12, 24),  # torso
    (23, 24),  # hips
]


def parse_args():
    p = argparse.ArgumentParser(description="Long video multi-hit segmentation (single golfer).")
    p.add_argument("--video", required=True, help="Path to long video.")
    p.add_argument("--output-dir", default="runs/long", help="Output directory.")
    p.add_argument("--det-conf", type=float, default=0.5, help="Pose detection confidence.")
    p.add_argument("--track-conf", type=float, default=0.5, help="Pose tracking confidence.")
    p.add_argument("--min-sep-sec", type=float, default=2.0, help="Minimum separation between FAST events.")
    p.add_argument("--pre-sec", type=float, default=2.0, help="Segment pre-roll before FAST (seconds).")
    p.add_argument("--post-sec", type=float, default=2.0, help="Segment post-roll after FAST (seconds).")
    p.add_argument("--fast-speed-min", type=float, default=5.0, help="Minimum absolute FAST speed (px/frame).")
    p.add_argument("--fast-speed-percentile", type=float, default=92.0, help="Global speed percentile threshold for FAST candidates.")
    p.add_argument("--fast-z-min", type=float, default=0.8, help="Minimum local z-score of FAST.")
    p.add_argument("--fast-rise-min", type=float, default=1.5, help="Minimum rise vs pre-window median.")
    p.add_argument("--fast-drop-min", type=float, default=1.0, help="Minimum drop vs post-window median.")
    p.add_argument("--top-down-span-min", type=float, default=8.0, help="Minimum Y span from TOP to DOWN (px).")
    p.add_argument("--min-fast-sec", type=float, default=2.0, help="Ignore FAST candidates before this time (sec).")
    p.add_argument("--top-fast-min-sec", type=float, default=0.45, help="Minimum time gap from TOP to FAST (sec).")
    p.add_argument("--fast-down-min-sec", type=float, default=0.18, help="Minimum time gap from FAST to DOWN (sec).")
    p.add_argument("--audio-window-sec", type=float, default=0.18, help="Audio peak search window around FAST (sec).")
    p.add_argument("--audio-global-percentile", type=float, default=70.0, help="Global audio percentile threshold for hit confirmation.")
    p.add_argument("--audio-min-peak", type=float, default=0.06, help="Absolute minimum normalized audio peak for hit confirmation.")
    p.add_argument("--audio-otsu-gate", action="store_true", help="Enable Otsu split threshold from candidate audio peaks.")
    p.add_argument("--audio-seed-window-sec", type=float, default=0.22, help="Search speed max near audio peaks (sec).")
    p.add_argument("--audio-seed-speed-ratio", type=float, default=0.7, help="Min speed ratio vs speed threshold for audio-seeded candidates.")
    p.add_argument("--peak-distance-sec", type=float, default=0.18, help="Minimum local spacing for speed peak detection (sec).")
    p.add_argument("--peak-width-sec", type=float, default=0.0, help="Minimum local width for speed peaks (sec), 0 to disable.")
    p.add_argument("--peak-prom-scale", type=float, default=1.2, help="Prominence scale for adaptive speed peak detection.")
    return p.parse_args()


def _probe_rotation(video_path: str) -> int:
    cmd = ["ffprobe", "-v", "error", "-print_format", "json", "-show_streams", video_path]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
        if proc.returncode != 0:
            return 0
        data = json.loads(proc.stdout)
        streams = data.get("streams", [])
        v = next((s for s in streams if s.get("codec_type") == "video"), None)
        if not v:
            return 0
        for sd in v.get("side_data_list", []):
            if "rotation" in sd:
                rot = int(round(float(sd["rotation"])))
                # Normalize to {-270,-180,-90,0,90,180,270}
                rot = ((rot + 360) % 360)
                if rot > 180:
                    rot -= 360
                return rot
        tags = v.get("tags", {})
        if "rotate" in tags:
            rot = int(round(float(tags["rotate"])))
            rot = ((rot + 360) % 360)
            if rot > 180:
                rot -= 360
            return rot
    except Exception:
        return 0
    return 0


def _rotate_frame(frame, rotation: int):
    if rotation == -90:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if rotation == 90:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if abs(rotation) == 180:
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def _draw_pose_skeleton(frame, pose_result):
    if not pose_result.pose_landmarks:
        return
    h, w = frame.shape[:2]
    lms = pose_result.pose_landmarks.landmark
    pts = []
    for lm in lms:
        pts.append((int(lm.x * w), int(lm.y * h), float(lm.visibility)))
    # Draw all landmarks
    for i, (x, y, v) in enumerate(pts):
        if v >= 0.2:
            cv2.circle(frame, (x, y), 4, (0, 255, 0), -1)
            cv2.putText(frame, str(i), (x + 5, y - 5), cv2.FONT_HERSHEY_SIMPLEX, 0.4, (255, 255, 255), 1)
    # Draw skeleton edges
    for a, b in SKELETON_EDGES:
        xa, ya, va = pts[a]
        xb, yb, vb = pts[b]
        if va < 0.2 or vb < 0.2:
            continue
        cv2.line(frame, (xa, ya), (xb, yb), (0, 255, 255), 2)
    # right wrist highlight
    x, y, v = pts[16]
    if v >= 0.2:
        cv2.circle(frame, (x, y), 6, (0, 0, 255), -1)


def _extract_right_wrist_series(video_path: str, det_conf: float, track_conf: float) -> Dict[str, object]:
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

    mp_pose = mp.solutions.pose
    right_x: List[float] = []
    right_y: List[float] = []
    hip_x: List[float] = []
    hip_y: List[float] = []
    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        min_detection_confidence=det_conf,
        min_tracking_confidence=track_conf,
    ) as pose:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            frame = _rotate_frame(frame, rotation)
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            r = pose.process(rgb)
            if r.pose_landmarks:
                lms = r.pose_landmarks.landmark
                rw = lms[16]  # right_wrist
                lh = lms[23]  # left_hip
                rh = lms[24]  # right_hip
                if rw.visibility >= 0.2:
                    right_x.append(float(rw.x * frame.shape[1]))
                    right_y.append(float(rw.y * frame.shape[0]))
                else:
                    right_x.append(np.nan)
                    right_y.append(np.nan)

                hips = []
                if lh.visibility >= 0.2:
                    hips.append((float(lh.x * frame.shape[1]), float(lh.y * frame.shape[0])))
                if rh.visibility >= 0.2:
                    hips.append((float(rh.x * frame.shape[1]), float(rh.y * frame.shape[0])))
                if hips:
                    hx = float(np.mean([p[0] for p in hips]))
                    hy = float(np.mean([p[1] for p in hips]))
                    hip_x.append(hx)
                    hip_y.append(hy)
                else:
                    hip_x.append(np.nan)
                    hip_y.append(np.nan)
            else:
                right_x.append(np.nan)
                right_y.append(np.nan)
                hip_x.append(np.nan)
                hip_y.append(np.nan)
    cap.release()

    right_x_raw = np.array(right_x, dtype=float)
    right_y_raw = np.array(right_y, dtype=float)
    hip_x_raw = np.array(hip_x, dtype=float)
    hip_y_raw = np.array(hip_y, dtype=float)

    x = _moving_average(_interp_nan(right_x_raw), 5)
    y = _moving_average(_interp_nan(right_y_raw), 5)
    speed = np.zeros_like(y)
    if len(y) > 1:
        dx = np.diff(x)
        dy = np.diff(y)
        speed[1:] = np.sqrt(dx * dx + dy * dy)  # px/frame
    speed = _moving_average(speed, 5)
    return {
        "right_y": y,
        "speed": speed,
        "fps": float(fps),
        "frame_count": frame_count,
        "width": out_w,
        "height": out_h,
        "rotation": rotation,
        "hip_x_raw": hip_x_raw,
        "hip_y_raw": hip_y_raw,
    }


def _local_maxima(x: np.ndarray) -> np.ndarray:
    if len(x) < 3:
        return np.array([], dtype=int)
    return np.where((x[1:-1] >= x[:-2]) & (x[1:-1] > x[2:]))[0] + 1


def _detect_speed_peaks(
    speed: np.ndarray,
    fps: float,
    base_height: float,
    peak_distance_sec: float,
    peak_width_sec: float,
    peak_prom_scale: float,
) -> np.ndarray:
    n = len(speed)
    if n < 3:
        return np.array([], dtype=int)
    distance = max(1, int(peak_distance_sec * fps))
    width = max(1, int(peak_width_sec * fps)) if peak_width_sec > 0 else None
    med = float(np.median(speed))
    mad = float(np.median(np.abs(speed - med))) + 1e-6
    prom = max(peak_prom_scale * mad, 0.04 * float(np.max(speed)))
    try:
        kwargs = {
            "height": base_height,
            "distance": distance,
            "prominence": prom,
        }
        if width is not None:
            kwargs["width"] = width
        peaks, _ = find_peaks(speed, **kwargs)
        if len(peaks) > 0:
            return peaks.astype(int)
    except Exception:
        pass
    # fallback
    maxima = _local_maxima(speed)
    return np.array([i for i in maxima if speed[i] >= base_height], dtype=int)


def _otsu_threshold_01(values: np.ndarray, bins: int = 128) -> float:
    v = np.asarray(values, dtype=float)
    v = v[np.isfinite(v)]
    if len(v) < 4:
        return float("nan")
    v = np.clip(v, 0.0, 1.0)
    if float(np.max(v) - np.min(v)) < 1e-6:
        return float("nan")
    hist, edges = np.histogram(v, bins=bins, range=(0.0, 1.0))
    hist = hist.astype(float)
    p = hist / max(1.0, float(np.sum(hist)))
    w = np.cumsum(p)
    centers = (edges[:-1] + edges[1:]) * 0.5
    mu = np.cumsum(p * centers)
    mu_t = mu[-1]
    den = w * (1.0 - w)
    sigma_b2 = np.zeros_like(den)
    ok = den > 1e-12
    sigma_b2[ok] = ((mu_t * w[ok] - mu[ok]) ** 2) / den[ok]
    k = int(np.argmax(sigma_b2))
    return float(centers[k])


def _detect_swings(
    y: np.ndarray,
    speed: np.ndarray,
    audio_amp: np.ndarray,
    fps: float,
    min_sep_sec: float,
    pre_sec: float,
    post_sec: float,
    fast_speed_min: float,
    fast_z_min: float,
    fast_rise_min: float,
    fast_drop_min: float,
    top_down_span_min: float,
    min_fast_sec: float,
    top_fast_min_sec: float,
    fast_down_min_sec: float,
    fast_speed_percentile: float,
    audio_window_sec: float,
    audio_global_percentile: float,
    audio_min_peak: float,
    audio_otsu_gate: bool,
    audio_seed_window_sec: float,
    audio_seed_speed_ratio: float,
    peak_distance_sec: float,
    peak_width_sec: float,
    peak_prom_scale: float,
) -> Tuple[List[SwingEvent], Dict[str, float], List[SwingEvent]]:
    n = len(y)
    if n == 0:
        return [], {"speed_thr": 0.0, "audio_thr_base": 0.0, "audio_thr_otsu": float("nan"), "audio_thr_final": 0.0}, []

    p90 = float(np.percentile(speed, 90))
    mean = float(np.mean(speed))
    std = float(np.std(speed))
    # Raise speed floor to avoid too many weak peaks; audio will confirm true hits.
    thr = max(
        fast_speed_min,
        float(np.percentile(speed, fast_speed_percentile)),
        mean + 0.6 * std,
        0.55 * p90,
    )

    maxima = _detect_speed_peaks(
        speed=speed,
        fps=fps,
        base_height=thr,
        peak_distance_sec=peak_distance_sec,
        peak_width_sec=peak_width_sec,
        peak_prom_scale=peak_prom_scale,
    )
    maxima_set = {int(i) for i in maxima}
    min_fast_frame = int(max(0.0, min_fast_sec) * fps)
    if len(audio_amp) > 0:
        a_med = float(np.median(audio_amp))
        a_mad = float(np.median(np.abs(audio_amp - a_med))) + 1e-6
        a_height = max(float(np.percentile(audio_amp, min(95.0, audio_global_percentile + 8.0))), float(audio_min_peak))
        a_prom = max(2.0 * a_mad, 0.03)
        a_distance = max(1, int(peak_distance_sec * fps))
        try:
            a_peaks, _ = find_peaks(audio_amp, height=a_height, distance=a_distance, prominence=a_prom)
        except Exception:
            a_peaks = np.array([], dtype=int)
        seed_w = max(1, int(audio_seed_window_sec * fps))
        speed_floor = max(fast_speed_min, audio_seed_speed_ratio * thr)
        for ap in a_peaks:
            l = max(0, int(ap) - seed_w)
            r = min(n, int(ap) + seed_w + 1)
            if l >= r:
                continue
            fast_local = int(l + np.argmax(speed[l:r]))
            if fast_local < min_fast_frame:
                continue
            if float(speed[fast_local]) >= speed_floor:
                maxima_set.add(fast_local)
    maxima = np.array(sorted(maxima_set), dtype=int)

    candidates: List[SwingEvent] = []
    rejected: List[SwingEvent] = []
    local_w = max(3, int(0.35 * fps))
    rej_pre = 1.0
    rej_post = 1.0
    for i in maxima:
        if int(i) < min_fast_frame:
            continue
        s = float(speed[i])
        if s < max(thr, fast_speed_min):
            continue

        l = max(0, i - local_w)
        r = min(n, i + local_w + 1)
        local = speed[l:r]
        mu = float(np.mean(local))
        sd = float(np.std(local)) + 1e-6
        z = (s - mu) / sd
        if z < fast_z_min:
            fast = int(i)
            start = max(0, int(fast - rej_pre * fps))
            end = min(n - 1, int(fast + rej_post * fps))
            rj = SwingEvent(
                idx=0,
                top_frame=fast,
                fast_frame=fast,
                down_frame=fast,
                start_frame=start,
                end_frame=end,
                score=float(s),
                keep=False,
                reject_reason="zscore",
            )
            rejected.append(rj)
            continue

        pre = speed[max(0, i - local_w) : i]
        post = speed[i + 1 : min(n, i + 1 + local_w)]
        if len(pre) < 3 or len(post) < 3:
            continue
        rise = s - float(np.median(pre))
        drop = s - float(np.median(post))
        if rise < fast_rise_min or drop < fast_drop_min:
            continue
        fast = int(i)
        top_l = max(0, fast - int(1.2 * fps))
        top_r = max(top_l + 1, fast - int(0.08 * fps))
        if top_l >= top_r:
            continue
        top = top_l + int(np.argmin(y[top_l:top_r]))

        down_l = max(top + 1, fast - int(0.15 * fps))
        down_r = min(n, fast + int(0.35 * fps))
        if down_l >= down_r:
            continue
        down = down_l + int(np.argmax(y[down_l:down_r]))

        if (fast - top) < int(max(0.0, top_fast_min_sec) * fps):
            start = max(0, int(fast - rej_pre * fps))
            end = min(n - 1, int(fast + rej_post * fps))
            rj = SwingEvent(
                idx=0,
                top_frame=int(top),
                fast_frame=int(fast),
                down_frame=int(down),
                start_frame=start,
                end_frame=end,
                score=float(s),
                keep=False,
                reject_reason="top_fast_gap",
            )
            rejected.append(rj)
            continue
        if (down - fast) < int(max(0.0, fast_down_min_sec) * fps):
            start = max(0, int(fast - rej_pre * fps))
            end = min(n - 1, int(fast + rej_post * fps))
            rj = SwingEvent(
                idx=0,
                top_frame=int(top),
                fast_frame=int(fast),
                down_frame=int(down),
                start_frame=start,
                end_frame=end,
                score=float(s),
                keep=False,
                reject_reason="fast_down_gap",
            )
            rejected.append(rj)
            continue

        y_span = float(y[down] - y[top])
        if y_span < top_down_span_min:
            continue

        # Audio confirmation score around FAST
        aw = max(1, int(audio_window_sec * fps))
        if len(audio_amp) > 0:
            al = max(0, fast - aw)
            ar = min(len(audio_amp), fast + aw + 1)
            audio_peak = float(np.max(audio_amp[al:ar])) if al < ar else 0.0
        else:
            audio_peak = 0.0

        # Segment around FAST (requested): FAST - pre_sec to FAST + post_sec.
        start = max(0, int(fast - pre_sec * fps))
        end = min(n - 1, int(fast + post_sec * fps))
        ev = SwingEvent(
            idx=0,
            top_frame=int(top),
            fast_frame=int(fast),
            down_frame=int(down),
            start_frame=int(start),
            end_frame=int(end),
            score=float(speed[fast] + 0.15 * y_span + 3.0 * audio_peak),
        )
        ev.audio_peak = audio_peak
        candidates.append(ev)

    # Audio gate first (to filter empty swings before spacing suppression)
    audio_otsu = float("nan")
    if len(audio_amp) > 0:
        base_audio_thr = max(float(np.percentile(audio_amp, audio_global_percentile)), float(audio_min_peak))
        if audio_otsu_gate:
            cand_audio = np.array([ev.audio_peak for ev in candidates], dtype=float)
            audio_otsu = _otsu_threshold_01(cand_audio)
            if np.isfinite(audio_otsu):
                audio_thr = max(base_audio_thr, float(audio_otsu))
            else:
                audio_thr = base_audio_thr
        else:
            audio_thr = base_audio_thr
    else:
        audio_thr = 0.0

    gated: List[SwingEvent] = []
    for ev in candidates:
        if len(audio_amp) == 0 or ev.audio_peak >= audio_thr:
            ev.audio_confirmed = True if len(audio_amp) > 0 else False
            gated.append(ev)
        else:
            rj = SwingEvent(
                idx=0,
                top_frame=int(ev.top_frame),
                fast_frame=int(ev.fast_frame),
                down_frame=int(ev.down_frame),
                start_frame=int(ev.start_frame),
                end_frame=int(ev.end_frame),
                score=float(ev.score),
                keep=False,
                reject_reason="audio_gate",
            )
            rj.audio_peak = float(ev.audio_peak)
            rejected.append(rj)

    # Apply min-separation in chronological order.
    # This avoids global score suppression that can swallow true hits in dense/noisy sections.
    gated.sort(key=lambda e: e.fast_frame)
    min_sep = max(1, int(min_sep_sec * fps))
    selected: List[SwingEvent] = []
    for ev in gated:
        if not selected:
            selected.append(ev)
            continue
        prev = selected[-1]
        if (ev.fast_frame - prev.fast_frame) >= min_sep:
            selected.append(ev)
            continue
        if ev.score > prev.score:
            selected[-1] = ev

    selected.sort(key=lambda e: e.fast_frame)
    events: List[SwingEvent] = []
    for j, ev in enumerate(selected, start=1):
        ev.idx = j
        events.append(ev)
    debug = {
        "speed_thr": float(thr),
        "audio_thr_base": float(base_audio_thr) if len(audio_amp) > 0 else 0.0,
        "audio_thr_otsu": float(audio_otsu),
        "audio_thr_final": float(audio_thr),
    }
    return events, debug, rejected


def _segment_stability_metrics(hip_x: np.ndarray, hip_y: np.ndarray, start: int, end: int) -> Tuple[float, float, float, float, float]:
    xs = hip_x[start : end + 1]
    ys = hip_y[start : end + 1]
    valid = np.isfinite(xs) & np.isfinite(ys)
    if len(valid) == 0:
        return 0.0, np.nan, np.nan, np.nan, np.nan

    valid_ratio = float(np.mean(valid))
    if np.sum(valid) < 5:
        return valid_ratio, np.nan, np.nan, np.nan, np.nan

    xv = xs[valid]
    yv = ys[valid]
    med_x = float(np.median(xv))
    med_y = float(np.median(yv))

    m = len(xv)
    k = max(2, m // 5)
    first = np.column_stack([xv[:k], yv[:k]])
    last = np.column_stack([xv[-k:], yv[-k:]])
    first_med = np.median(first, axis=0)
    last_med = np.median(last, axis=0)
    drift_px = float(np.hypot(last_med[0] - first_med[0], last_med[1] - first_med[1]))

    d = np.hypot(xv - med_x, yv - med_y)
    spread_px = float(np.percentile(d, 90))
    return valid_ratio, med_x, med_y, drift_px, spread_px


def _filter_events_by_position_stability(
    events: List[SwingEvent], hip_x_raw: np.ndarray, hip_y_raw: np.ndarray, width: int, height: int
) -> List[SwingEvent]:
    if not events:
        return events
    diag = float(np.hypot(width, height))
    basic_kept: List[SwingEvent] = []
    centers: List[Tuple[float, float]] = []

    for ev in events:
        valid_ratio, med_x, med_y, drift_px, spread_px = _segment_stability_metrics(
            hip_x_raw, hip_y_raw, ev.start_frame, ev.end_frame
        )
        ev.pos_valid_ratio = 0.0 if np.isnan(valid_ratio) else float(valid_ratio)
        ev.pos_drift_px = 0.0 if np.isnan(drift_px) else float(drift_px)
        ev.pos_spread_px = 0.0 if np.isnan(spread_px) else float(spread_px)

        reasons = []
        if valid_ratio < 0.75:
            reasons.append("low_visible_ratio")
        if not np.isnan(drift_px) and drift_px > 0.09 * diag:
            reasons.append("large_position_drift")
        if not np.isnan(spread_px) and spread_px > 0.09 * diag:
            reasons.append("large_position_spread")
        if np.isnan(med_x) or np.isnan(med_y):
            reasons.append("invalid_center")

        if reasons:
            ev.keep = False
            ev.reject_reason = "|".join(reasons)
            continue

        centers.append((float(med_x), float(med_y)))
        basic_kept.append(ev)

    if not basic_kept:
        return events

    anchor = np.median(np.array(centers, dtype=float), axis=0)
    anchor_r = 0.14 * diag
    for ev in basic_kept:
        valid_ratio, med_x, med_y, _, _ = _segment_stability_metrics(hip_x_raw, hip_y_raw, ev.start_frame, ev.end_frame)
        dist = float(np.hypot(med_x - anchor[0], med_y - anchor[1]))
        ev.anchor_dist_px = dist
        if dist > anchor_r:
            ev.keep = False
            ev.reject_reason = "off_anchor_position"

    return events


def _write_segments(video_path: str, out_dir: str, events: List[SwingEvent], fps: float, width: int, height: int, rotation: int):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    mp_pose = mp.solutions.pose

    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        min_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    ) as pose:
        for ev in events:
            if not ev.keep:
                continue
            case = f"hit_{ev.idx:04d}"
            case_dir = os.path.join(out_dir, case)
            os.makedirs(case_dir, exist_ok=True)
            out_mp4 = os.path.join(case_dir, f"{case}.mp4")
            out_skel = os.path.join(case_dir, f"{case}_skeleton.mp4")

            writer_raw = cv2.VideoWriter(out_mp4, fourcc, fps, (width, height))
            writer_skel = cv2.VideoWriter(out_skel, fourcc, fps, (width, height))
            cap.set(cv2.CAP_PROP_POS_FRAMES, ev.start_frame)
            f = ev.start_frame
            while f <= ev.end_frame:
                ok, frame = cap.read()
                if not ok:
                    break
                frame = _rotate_frame(frame, rotation)
                writer_raw.write(frame)

                canvas = frame.copy()
                rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)
                result = pose.process(rgb)
                _draw_pose_skeleton(canvas, result)
                cv2.putText(canvas, f"Frame {f}", (25, 40), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (255, 255, 255), 2)
                cv2.putText(canvas, f"TOP {ev.top_frame}", (25, 80), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 180, 0), 2)
                cv2.putText(canvas, f"FAST {ev.fast_frame}", (25, 115), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
                cv2.putText(canvas, f"DOWN {ev.down_frame}", (25, 150), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 220, 255), 2)
                if f == ev.top_frame:
                    cv2.putText(canvas, "TOP", (25, 190), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (255, 180, 0), 3)
                if f == ev.fast_frame:
                    cv2.putText(canvas, "FAST", (25, 225), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 255, 0), 3)
                if f == ev.down_frame:
                    cv2.putText(canvas, "DOWN", (25, 260), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (0, 220, 255), 3)
                writer_skel.write(canvas)
                f += 1
            writer_raw.release()
            writer_skel.release()

            meta = {
                "case": case,
                "top_frame_global": ev.top_frame,
                "fast_frame_global": ev.fast_frame,
                "down_frame_global": ev.down_frame,
                "start_frame_global": ev.start_frame,
                "end_frame_global": ev.end_frame,
                "fps": fps,
                "top_time_sec": ev.top_frame / fps,
                "fast_time_sec": ev.fast_frame / fps,
                "down_time_sec": ev.down_frame / fps,
                "start_time_sec": ev.start_frame / fps,
                "end_time_sec": ev.end_frame / fps,
                "score": ev.score,
                "pos_valid_ratio": ev.pos_valid_ratio,
                "pos_drift_px": ev.pos_drift_px,
                "pos_spread_px": ev.pos_spread_px,
                "anchor_dist_px": ev.anchor_dist_px,
            }
            with open(os.path.join(case_dir, "segment_meta.json"), "w", encoding="utf-8") as jf:
                json.dump(meta, jf, indent=2, ensure_ascii=False)
    cap.release()


def _write_rejected_segments(
    video_path: str, out_dir: str, rejected_events: List[SwingEvent], fps: float, width: int, height: int, rotation: int
):
    if not rejected_events:
        return
    root = os.path.join(out_dir, "rejected_peaks")
    os.makedirs(root, exist_ok=True)
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")
    fourcc = cv2.VideoWriter_fourcc(*"mp4v")
    reason_idx: Dict[str, int] = {}
    rows = []
    for ev in rejected_events:
        reason = ev.reject_reason if ev.reject_reason else "unknown"
        reason_dir = os.path.join(root, reason)
        os.makedirs(reason_dir, exist_ok=True)
        reason_idx[reason] = reason_idx.get(reason, 0) + 1
        rid = reason_idx[reason]
        case = f"rej_{rid:04d}_f{ev.fast_frame:06d}"
        out_mp4 = os.path.join(reason_dir, f"{case}.mp4")

        writer = cv2.VideoWriter(out_mp4, fourcc, fps, (width, height))
        cap.set(cv2.CAP_PROP_POS_FRAMES, ev.start_frame)
        f = ev.start_frame
        while f <= ev.end_frame:
            ok, frame = cap.read()
            if not ok:
                break
            frame = _rotate_frame(frame, rotation)
            cv2.putText(frame, f"REJECT {reason}", (20, 36), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (0, 180, 255), 2)
            cv2.putText(frame, f"Frame {f}", (20, 72), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (240, 240, 240), 2)
            cv2.putText(frame, f"TOP {ev.top_frame}", (20, 106), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 180, 0), 2)
            cv2.putText(frame, f"FAST {ev.fast_frame}", (20, 136), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
            cv2.putText(frame, f"DOWN {ev.down_frame}", (20, 166), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 220, 255), 2)
            if ev.audio_peak > 0:
                cv2.putText(frame, f"audio_peak {ev.audio_peak:.3f}", (20, 196), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 180, 0), 2)
            writer.write(frame)
            f += 1
        writer.release()
        rows.append(
            [
                reason,
                rid,
                ev.top_frame,
                ev.fast_frame,
                ev.down_frame,
                ev.start_frame,
                ev.end_frame,
                ev.audio_peak,
                out_mp4,
            ]
        )
    cap.release()

    csv_path = os.path.join(root, "rejected_peaks.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(
            [
                "reason",
                "reason_idx",
                "top_frame",
                "fast_frame",
                "down_frame",
                "start_frame",
                "end_frame",
                "audio_peak",
                "clip_path",
            ]
        )
        w.writerows(rows)


def _draw_hline_dashed(img, x0: int, x1: int, y: int, color, dash: int = 10, gap: int = 7, thickness: int = 1):
    x = x0
    while x < x1:
        xe = min(x + dash, x1)
        cv2.line(img, (x, y), (xe, y), color, thickness)
        x += dash + gap


def _write_overview_plot_single(
    out_path: str,
    values: np.ndarray,
    events: List[SwingEvent],
    fps: float,
    title: str,
    line_color,
    std_value: float | None = None,
    std_label: str | None = None,
    extra_thresholds: List[Tuple[str, float, Tuple[int, int, int]]] | None = None,
):
    w, h = 1700, 880
    x0, y0, pw, ph = 70, 100, 1560, 680
    img = np.zeros((h, w, 3), dtype=np.uint8)
    img[:, :] = (22, 22, 22)
    cv2.putText(img, title, (55, 50), cv2.FONT_HERSHEY_SIMPLEX, 1.1, (240, 240, 240), 2)
    cv2.rectangle(img, (x0, y0), (x0 + pw, y0 + ph), (180, 180, 180), 1)

    n = len(values)
    if n <= 1:
        cv2.imwrite(out_path, img)
        return

    vmin = float(values.min())
    vmax = float(values.max())
    vn = (values - vmin) / (vmax - vmin + 1e-6)

    pts = []
    for i in range(n):
        px = x0 + int(i * (pw - 1) / (n - 1))
        py = y0 + ph - 1 - int(vn[i] * (ph - 1))
        pts.append((px, py))
    for i in range(1, n):
        cv2.line(img, pts[i - 1], pts[i], line_color, 1)

    total_sec = n / max(fps, 1e-6)
    for k in range(9):
        tx = x0 + int(k * (pw - 1) / 8)
        sec = k * total_sec / 8.0
        cv2.line(img, (tx, y0 + ph), (tx, y0 + ph + 5), (160, 160, 160), 1)
        cv2.putText(img, f"{sec:.0f}s", (tx - 14, y0 + ph + 24), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (210, 210, 210), 1)
    cv2.putText(img, "Normalized", (80, 82), cv2.FONT_HERSHEY_SIMPLEX, 0.55, line_color, 2)
    cv2.putText(img, f"raw min={vmin:.3f} max={vmax:.3f}", (260, 82), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (210, 210, 210), 1)

    threshold_items: List[Tuple[str, float, Tuple[int, int, int]]] = []
    if std_value is not None:
        label = std_label if std_label else "STD"
        threshold_items.append((label, float(std_value), (245, 245, 245)))
    if extra_thresholds:
        threshold_items.extend(extra_thresholds)
    for j, (label, val, col) in enumerate(threshold_items):
        std_n = (float(val) - vmin) / (vmax - vmin + 1e-6)
        std_n = max(0.0, min(1.0, std_n))
        y_std = y0 + ph - 1 - int(std_n * (ph - 1))
        _draw_hline_dashed(img, x0, x0 + pw, y_std, col, dash=12, gap=8, thickness=1)
        y_text = max(y0 + 18, y_std - 6 - (j % 3) * 16)
        cv2.putText(img, f"{label}={float(val):.3f}", (x0 + 10 + (j // 3) * 220, y_text), cv2.FONT_HERSHEY_SIMPLEX, 0.5, col, 1)

    for ev in events:
        for name, idx, col in (
            ("TOP", ev.top_frame, (255, 180, 0)),
            ("FAST", ev.fast_frame, (0, 255, 0)),
            ("DOWN", ev.down_frame, (0, 220, 255)),
        ):
            px = x0 + int(idx * (pw - 1) / (n - 1))
            py = pts[idx][1]
            cv2.circle(img, (px, py), 3, col, -1)
            cv2.putText(img, name, (px + 4, max(y0 + 15, py - 6)), cv2.FONT_HERSHEY_SIMPLEX, 0.42, col, 1)
    cv2.imwrite(out_path, img)


def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    segments_dir = os.path.join(args.output_dir, "segments")
    os.makedirs(segments_dir, exist_ok=True)

    series = _extract_right_wrist_series(args.video, args.det_conf, args.track_conf)
    y = series["right_y"]
    speed = series["speed"]
    fps = series["fps"]
    frame_count = series["frame_count"]
    width = series["width"]
    height = series["height"]
    rotation = series["rotation"]
    hip_x_raw = series["hip_x_raw"]
    hip_y_raw = series["hip_y_raw"]
    audio_amp = extract_audio_amplitude(args.video, fps=float(fps), num_frames=int(frame_count))

    events_raw, detect_debug, rejected_events = _detect_swings(
        y=y,
        speed=speed,
        audio_amp=audio_amp,
        fps=float(fps),
        min_sep_sec=args.min_sep_sec,
        pre_sec=args.pre_sec,
        post_sec=args.post_sec,
        fast_speed_min=args.fast_speed_min,
        fast_z_min=args.fast_z_min,
        fast_rise_min=args.fast_rise_min,
        fast_drop_min=args.fast_drop_min,
        top_down_span_min=args.top_down_span_min,
        min_fast_sec=args.min_fast_sec,
        top_fast_min_sec=args.top_fast_min_sec,
        fast_down_min_sec=args.fast_down_min_sec,
        fast_speed_percentile=args.fast_speed_percentile,
        audio_window_sec=args.audio_window_sec,
        audio_global_percentile=args.audio_global_percentile,
        audio_min_peak=args.audio_min_peak,
        audio_otsu_gate=args.audio_otsu_gate,
        audio_seed_window_sec=args.audio_seed_window_sec,
        audio_seed_speed_ratio=args.audio_seed_speed_ratio,
        peak_distance_sec=args.peak_distance_sec,
        peak_width_sec=args.peak_width_sec,
        peak_prom_scale=args.peak_prom_scale,
    )
    events = _filter_events_by_position_stability(
        events_raw, hip_x_raw=hip_x_raw, hip_y_raw=hip_y_raw, width=int(width), height=int(height)
    )
    kept_events = [e for e in events if e.keep]

    _write_segments(args.video, segments_dir, kept_events, float(fps), int(width), int(height), int(rotation))
    _write_rejected_segments(
        args.video,
        args.output_dir,
        rejected_events,
        float(fps),
        int(width),
        int(height),
        int(rotation),
    )
    speed_std = max(
        float(args.fast_speed_min),
        float(np.percentile(speed, args.fast_speed_percentile)),
        float(np.mean(speed) + 0.6 * np.std(speed)),
        float(0.55 * np.percentile(speed, 90)),
    )
    audio_std = max(float(np.percentile(audio_amp, args.audio_global_percentile)), float(args.audio_min_peak))
    audio_final_thr = float(detect_debug.get("audio_thr_final", audio_std))

    _write_overview_plot_single(
        os.path.join(args.output_dir, "long_overview_y.png"),
        y,
        kept_events,
        float(fps),
        "Long Overview - Right Wrist Y",
        (0, 255, 255),
    )
    _write_overview_plot_single(
        os.path.join(args.output_dir, "long_overview_speed.png"),
        speed,
        kept_events,
        float(fps),
        "Long Overview - Right Wrist Speed",
        (0, 200, 0),
        std_value=speed_std,
        std_label="speed_std",
    )
    _write_overview_plot_single(
        os.path.join(args.output_dir, "long_overview_audio.png"),
        audio_amp,
        kept_events,
        float(fps),
        "Long Overview - Audio Amplitude",
        (255, 180, 0),
        std_value=audio_std,
        std_label="audio_std",
        extra_thresholds=[("audio_final_thr", audio_final_thr, (255, 128, 128))],
    )

    csv_path = os.path.join(args.output_dir, "events.csv")
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(
            [
                "idx",
                "keep",
                "reject_reason",
                "top_frame",
                "fast_frame",
                "down_frame",
                "start_frame",
                "end_frame",
                "top_sec",
                "fast_sec",
                "down_sec",
                "start_sec",
                "end_sec",
                "score",
                "pos_valid_ratio",
                "pos_drift_px",
                "pos_spread_px",
                "anchor_dist_px",
                "audio_peak",
                "audio_confirmed",
            ]
        )
        for e in events:
            writer.writerow(
                [
                    e.idx,
                    int(e.keep),
                    e.reject_reason,
                    e.top_frame,
                    e.fast_frame,
                    e.down_frame,
                    e.start_frame,
                    e.end_frame,
                    e.top_frame / fps,
                    e.fast_frame / fps,
                    e.down_frame / fps,
                    e.start_frame / fps,
                    e.end_frame / fps,
                    e.score,
                    e.pos_valid_ratio,
                    e.pos_drift_px,
                    e.pos_spread_px,
                    e.anchor_dist_px,
                    e.audio_peak,
                    int(e.audio_confirmed),
                ]
            )

    summary = {
        "video_path": os.path.abspath(args.video),
        "fps": fps,
        "frame_count": frame_count,
        "duration_sec": frame_count / max(fps, 1e-6),
        "rotation_applied_deg": int(rotation),
        "num_hits_raw": len(events),
        "num_hits_kept": len(kept_events),
        "speed_threshold": float(detect_debug.get("speed_thr", speed_std)),
        "audio_threshold_base": float(detect_debug.get("audio_thr_base", audio_std)),
        "audio_threshold_otsu": float(detect_debug.get("audio_thr_otsu", float("nan"))),
        "audio_threshold_final": audio_final_thr,
        "num_rejected_peaks": len(rejected_events),
        "num_rejected_by_reason": {
            "zscore": int(sum(1 for e in rejected_events if e.reject_reason == "zscore")),
            "top_fast_gap": int(sum(1 for e in rejected_events if e.reject_reason == "top_fast_gap")),
            "fast_down_gap": int(sum(1 for e in rejected_events if e.reject_reason == "fast_down_gap")),
            "audio_gate": int(sum(1 for e in rejected_events if e.reject_reason == "audio_gate")),
        },
        "events": [asdict(e) for e in events],
    }
    summary_path = os.path.join(args.output_dir, "summary.json")
    with open(summary_path, "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    print(f"[OK] video      : {args.video}")
    print(f"[OK] fps        : {fps:.4f}")
    print(f"[OK] frames     : {frame_count}")
    print(f"[OK] rotation   : {int(rotation)}")
    print(f"[OK] hits raw   : {len(events)}")
    print(f"[OK] hits kept  : {len(kept_events)}")
    print(f"[OK] summary    : {summary_path}")
    print(f"[OK] events csv : {csv_path}")
    print(f"[OK] segments   : {segments_dir}")
    print(f"[OK] rejected   : {os.path.join(args.output_dir, 'rejected_peaks')}")
    print(f"[OK] overview y : {os.path.join(args.output_dir, 'long_overview_y.png')}")
    print(f"[OK] overview v : {os.path.join(args.output_dir, 'long_overview_speed.png')}")
    print(f"[OK] overview a : {os.path.join(args.output_dir, 'long_overview_audio.png')}")


if __name__ == "__main__":
    main()
