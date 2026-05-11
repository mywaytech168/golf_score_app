from __future__ import annotations

import os
from typing import List

import cv2
import numpy as np

from .impact import compute_right_wrist_metrics
from .types import FramePose, ImpactResult


SKELETON_EDGES = [
    ("left_shoulder", "right_shoulder"),
    ("left_shoulder", "left_elbow"),
    ("left_elbow", "left_wrist"),
    ("right_shoulder", "right_elbow"),
    ("right_elbow", "right_wrist"),
    ("left_shoulder", "left_hip"),
    ("right_shoulder", "right_hip"),
    ("left_hip", "right_hip"),
]


def _draw_pose(frame, pose: FramePose):
    for a, b in SKELETON_EDGES:
        pa = pose.landmarks_xy.get(a)
        pb = pose.landmarks_xy.get(b)
        if pa is None or pb is None:
            continue
        cv2.line(frame, (int(pa[0]), int(pa[1])), (int(pb[0]), int(pb[1])), (0, 255, 255), 2)

    for _, p in pose.landmarks_xy.items():
        cv2.circle(frame, (int(p[0]), int(p[1])), 4, (0, 255, 0), -1)


def _draw_series(canvas, values: np.ndarray, rect, color, title: str):
    x0, y0, w, h = rect
    cv2.rectangle(canvas, (x0, y0), (x0 + w, y0 + h), (200, 200, 200), 1)
    cv2.putText(canvas, title, (x0 + 6, y0 + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)
    n = len(values)
    if n <= 1:
        return
    vmin = float(np.min(values))
    vmax = float(np.max(values))
    if abs(vmax - vmin) < 1e-6:
        vmax = vmin + 1.0
    pts = []
    for i, v in enumerate(values):
        px = x0 + int(i * (w - 1) / (n - 1))
        py = y0 + h - 1 - int((v - vmin) * (h - 1) / (vmax - vmin))
        pts.append((px, py))
    for i in range(1, len(pts)):
        cv2.line(canvas, pts[i - 1], pts[i], color, 2)
    # Y-axis value labels
    cv2.putText(canvas, f"{vmax:.2f}", (x0 + 5, y0 + 36), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)
    cv2.putText(canvas, f"{vmin:.2f}", (x0 + 5, y0 + h - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)
    # X-axis frame ticks
    for k in range(5):
        tx = x0 + int(k * (w - 1) / 4)
        frame_v = int(k * (n - 1) / 4)
        cv2.line(canvas, (tx, y0 + h), (tx, y0 + h + 5), (180, 180, 180), 1)
        cv2.putText(canvas, str(frame_v), (tx - 12, y0 + h + 22), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (210, 210, 210), 1)
    cv2.putText(canvas, "Frame", (x0 + w - 70, y0 + h + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (210, 210, 210), 1)


def _draw_series_with_ms_axis(canvas, values: np.ndarray, rect, color, title: str, fps: float):
    x0, y0, w, h = rect
    cv2.rectangle(canvas, (x0, y0), (x0 + w, y0 + h), (200, 200, 200), 1)
    cv2.putText(canvas, title, (x0 + 6, y0 + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.55, color, 2)
    n = len(values)
    if n <= 1:
        return
    vmin = float(np.min(values))
    vmax = float(np.max(values))
    if abs(vmax - vmin) < 1e-6:
        vmax = vmin + 1.0
    pts = []
    for i, v in enumerate(values):
        px = x0 + int(i * (w - 1) / (n - 1))
        py = y0 + h - 1 - int((v - vmin) * (h - 1) / (vmax - vmin))
        pts.append((px, py))
    for i in range(1, len(pts)):
        cv2.line(canvas, pts[i - 1], pts[i], color, 2)

    cv2.putText(canvas, f"{vmax:.2f}", (x0 + 5, y0 + 36), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)
    cv2.putText(canvas, f"{vmin:.2f}", (x0 + 5, y0 + h - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)

    total_ms = (n - 1) / max(fps, 1e-6) * 1000.0
    for k in range(5):
        tx = x0 + int(k * (w - 1) / 4)
        t_ms = k * total_ms / 4.0
        cv2.line(canvas, (tx, y0 + h), (tx, y0 + h + 5), (180, 180, 180), 1)
        cv2.putText(canvas, f"{t_ms:.0f}", (tx - 14, y0 + h + 22), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (210, 210, 210), 1)
    cv2.putText(canvas, "Time (ms)", (x0 + w - 90, y0 + h + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (210, 210, 210), 1)


def write_metrics_plot(out_path: str, right_y: np.ndarray, right_speed: np.ndarray):
    w, h = 1280, 720
    canvas = np.zeros((h, w, 3), dtype=np.uint8)
    canvas[:, :] = (25, 25, 25)
    cv2.putText(canvas, "Right Wrist Metrics", (40, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (240, 240, 240), 2)
    _draw_series(canvas, right_y, rect=(40, 80, 1200, 260), color=(0, 255, 255), title="Right Wrist Y (pixel)")
    _draw_series(canvas, right_speed, rect=(40, 390, 1200, 260), color=(0, 200, 0), title="Right Wrist Speed (pixel/frame)")
    cv2.imwrite(out_path, canvas)


def write_time_audio_plot(out_path: str, right_y: np.ndarray, right_speed: np.ndarray, audio_amp: np.ndarray, fps: float):
    w, h = 1360, 980
    canvas = np.zeros((h, w, 3), dtype=np.uint8)
    canvas[:, :] = (25, 25, 25)
    cv2.putText(canvas, "Right Wrist + Audio (Time Axis in ms)", (40, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (240, 240, 240), 2)
    _draw_series_with_ms_axis(
        canvas, right_y, rect=(40, 90, 1280, 250), color=(0, 255, 255), title="Right Wrist Y (pixel)", fps=fps
    )
    _draw_series_with_ms_axis(
        canvas,
        right_speed,
        rect=(40, 390, 1280, 250),
        color=(0, 200, 0),
        title="Right Wrist Speed (pixel/frame)",
        fps=fps,
    )
    _draw_series_with_ms_axis(
        canvas,
        audio_amp,
        rect=(40, 690, 1280, 250),
        color=(255, 180, 0),
        title="Audio Amplitude (normalized 0~1)",
        fps=fps,
    )
    cv2.imwrite(out_path, canvas)


def _normalize(x: np.ndarray) -> np.ndarray:
    vmin = float(np.min(x))
    vmax = float(np.max(x))
    if abs(vmax - vmin) < 1e-8:
        return np.zeros_like(x, dtype=np.float32)
    return ((x - vmin) / (vmax - vmin)).astype(np.float32)


def _draw_overlay_plot(
    out_path: str,
    right_y: np.ndarray,
    right_speed: np.ndarray,
    audio_amp: np.ndarray,
    fps: float,
    top_idx: int,
    fast_idx: int,
    down_idx: int,
    use_ms_axis: bool,
):
    w, h = 1360, 980
    canvas = np.zeros((h, w, 3), dtype=np.uint8)
    canvas[:, :] = (25, 25, 25)
    axis_name = "Time (ms)" if use_ms_axis else "Frame"
    cv2.putText(canvas, f"Right Wrist + Audio ({axis_name})", (40, 45), cv2.FONT_HERSHEY_SIMPLEX, 1.0, (240, 240, 240), 2)

    n = len(right_y)
    if n <= 1:
        cv2.imwrite(out_path, canvas)
        return

    y_norm = _normalize(right_y)
    s_norm = _normalize(right_speed)
    a_norm = _normalize(audio_amp)

    # Three subplots
    subplots = [
        ((60, 100, 1260, 230), y_norm, (0, 255, 255), "Right Wrist Y (norm)"),
        ((60, 390, 1260, 230), s_norm, (0, 200, 0), "Right Wrist Speed (norm)"),
        ((60, 680, 1260, 230), a_norm, (255, 180, 0), "Audio Amplitude (norm)"),
    ]

    total_ms = (n - 1) / max(fps, 1e-6) * 1000.0

    def to_pts(values: np.ndarray, x0: int, y0: int, pw: int, ph: int):
        pts = []
        for i, v in enumerate(values):
            px = x0 + int(i * (pw - 1) / (n - 1))
            py = y0 + ph - 1 - int(v * (ph - 1))
            pts.append((px, py))
        return pts

    for (x0, y0, pw, ph), values, color, title in subplots:
        cv2.rectangle(canvas, (x0, y0), (x0 + pw, y0 + ph), (200, 200, 200), 1)
        cv2.putText(canvas, title, (x0 + 8, y0 + 22), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 2)
        cv2.putText(canvas, "1.00", (x0 + 8, y0 + 42), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)
        cv2.putText(canvas, "0.00", (x0 + 8, y0 + ph - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (220, 220, 220), 1)

        pts = to_pts(values, x0, y0, pw, ph)
        for i in range(1, n):
            cv2.line(canvas, pts[i - 1], pts[i], color, 2)

        for k in range(6):
            tx = x0 + int(k * (pw - 1) / 5)
            cv2.line(canvas, (tx, y0 + ph), (tx, y0 + ph + 5), (180, 180, 180), 1)
            if use_ms_axis:
                label = f"{(k * total_ms / 5):.0f}"
            else:
                label = f"{int(k * (n - 1) / 5)}"
            cv2.putText(canvas, label, (tx - 14, y0 + ph + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.42, (210, 210, 210), 1)
        cv2.putText(canvas, axis_name, (x0 + pw - 95, y0 + ph + 20), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (210, 210, 210), 1)

        # Event markers: TOP / FAST / DOWN
        events = [("TOP", top_idx, (255, 180, 0)), ("FAST", fast_idx, (0, 255, 0)), ("DOWN", down_idx, (0, 220, 255))]
        for name, idx, col in events:
            idx = int(max(0, min(n - 1, idx)))
            ex = x0 + int(idx * (pw - 1) / (n - 1))
            cv2.line(canvas, (ex, y0), (ex, y0 + ph), col, 1)
            cv2.putText(canvas, name, (ex + 4, y0 + 18), cv2.FONT_HERSHEY_SIMPLEX, 0.5, col, 2)
            cv2.circle(canvas, pts[idx], 4, col, -1)

    cv2.imwrite(out_path, canvas)


def write_audio_overlay_plots(
    frames_out_path: str,
    times_out_path: str,
    right_y: np.ndarray,
    right_speed: np.ndarray,
    audio_amp: np.ndarray,
    fps: float,
    top_idx: int,
    fast_idx: int,
    down_idx: int,
):
    _draw_overlay_plot(
        out_path=frames_out_path,
        right_y=right_y,
        right_speed=right_speed,
        audio_amp=audio_amp,
        fps=fps,
        top_idx=top_idx,
        fast_idx=fast_idx,
        down_idx=down_idx,
        use_ms_axis=False,
    )
    _draw_overlay_plot(
        out_path=times_out_path,
        right_y=right_y,
        right_speed=right_speed,
        audio_amp=audio_amp,
        fps=fps,
        top_idx=top_idx,
        fast_idx=fast_idx,
        down_idx=down_idx,
        use_ms_axis=True,
    )


def write_annotated_video(out_path: str, frames: List, poses: List[FramePose], impact: ImpactResult, fps: float):
    if not frames:
        raise RuntimeError("No frames to write.")
    h, w = frames[0].shape[:2]
    writer = cv2.VideoWriter(out_path, cv2.VideoWriter_fourcc(*"mp4v"), fps, (w, h))
    out_dir = os.path.dirname(out_path)

    _, right_y, right_speed = compute_right_wrist_metrics(poses)
    top_idx = impact.top_frame if impact.top_frame is not None else impact.backswing_top_frame
    down_idx = impact.down_frame if impact.down_frame is not None else impact.lowest_wrist_frame
    fast_idx = impact.right_peak_speed_frame

    for i, frame in enumerate(frames):
        canvas = frame.copy()
        pose = poses[i]
        _draw_pose(canvas, pose)

        cv2.putText(
            canvas,
            f"TOP frame: {top_idx if top_idx is not None else '-'}",
            (40, 55),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.95,
            (255, 180, 0),
            2,
        )
        cv2.putText(
            canvas,
            f"DOWN frame: {down_idx if down_idx is not None else '-'}",
            (40, 95),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.95,
            (0, 220, 255),
            2,
        )
        cv2.putText(
            canvas,
            f"FAST frame: {fast_idx if fast_idx is not None else '-'}",
            (40, 135),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.95,
            (0, 255, 0),
            2,
        )
        if top_idx is not None and i == top_idx:
            cv2.putText(canvas, "TOP", (40, 180), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (255, 180, 0), 4)
            cv2.imwrite(os.path.join(out_dir, "top_frame.jpg"), canvas)
        if down_idx is not None and i == down_idx:
            cv2.putText(canvas, "DOWN", (40, 220), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 220, 255), 4)
            cv2.imwrite(os.path.join(out_dir, "down_frame.jpg"), canvas)
        if fast_idx is not None and i == fast_idx:
            cv2.putText(canvas, "FAST", (40, 260), cv2.FONT_HERSHEY_SIMPLEX, 1.5, (0, 255, 0), 4)

        ry = float(right_y[i]) if i < len(right_y) else 0.0
        rv = float(right_speed[i]) if i < len(right_speed) else 0.0
        cv2.putText(canvas, f"R_Wrist_Y(px): {ry:.1f}", (40, h - 65), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (230, 230, 230), 2)
        cv2.putText(canvas, f"R_Wrist_Speed(px/f): {rv:.2f}", (40, h - 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (230, 230, 230), 2)

        cv2.putText(
            canvas,
            f"Frame={i}  Time={i / fps:.3f}s",
            (w - 340, h - 30),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (255, 255, 255),
            2,
        )
        writer.write(canvas)

    writer.release()
