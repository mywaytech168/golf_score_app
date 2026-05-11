from __future__ import annotations

from typing import List, Optional, Tuple

import numpy as np

from .types import FramePose, ImpactResult


def _safe_point(pose: FramePose, name: str) -> Optional[Tuple[float, float]]:
    p = pose.landmarks_xy.get(name)
    v = pose.visibility.get(name, 0.0)
    if p is None or v < 0.2:
        return None
    return p


def _interp_nan(x: np.ndarray) -> np.ndarray:
    y = x.astype(float).copy()
    n = len(y)
    idx = np.arange(n)
    mask = np.isfinite(y)
    if not np.any(mask):
        return np.zeros_like(y)
    y[~mask] = np.interp(idx[~mask], idx[mask], y[mask])
    return y


def _moving_average(x: np.ndarray, k: int = 7) -> np.ndarray:
    if k <= 1:
        return x
    k = min(k, len(x))
    if k % 2 == 0:
        k += 1
    pad = k // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    kernel = np.ones(k) / k
    return np.convolve(xp, kernel, mode="valid")


def _norm(x: np.ndarray) -> np.ndarray:
    return (x - x.min()) / (x.max() - x.min() + 1e-6)


def compute_right_wrist_metrics(poses: List[FramePose]) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    right_x = []
    right_y = []
    for p in poses:
        rw = _safe_point(p, "right_wrist")
        right_x.append(np.nan if rw is None else rw[0])
        right_y.append(np.nan if rw is None else rw[1])

    x = _moving_average(_interp_nan(np.array(right_x)), 5)
    y = _moving_average(_interp_nan(np.array(right_y)), 5)

    speed = np.zeros_like(y)
    if len(y) > 1:
        dx = np.diff(x)
        dy = np.diff(y)
        speed[1:] = np.sqrt(dx * dx + dy * dy)  # pixel/frame
    speed = _moving_average(speed, 5)
    return x, y, speed


def _choose_handedness(poses: List[FramePose]) -> str:
    left_x = []
    right_x = []
    for p in poses:
        lw = p.landmarks_xy.get("left_wrist")
        rw = p.landmarks_xy.get("right_wrist")
        if lw is not None and rw is not None:
            left_x.append(lw[0])
            right_x.append(rw[0])
    if len(left_x) < 3:
        return "right"
    # side-view heuristic: golfer facing right often indicates right-handed setup.
    return "right" if np.nanmedian(left_x) < np.nanmedian(right_x) else "left"


def estimate_impact(poses: List[FramePose], fps: float) -> ImpactResult:
    if not poses:
        raise RuntimeError("No pose frames.")

    handedness = _choose_handedness(poses)
    _, right_y, right_speed = compute_right_wrist_metrics(poses)

    n = len(poses)
    # FAST: frame with max right-wrist speed (ignore very early frames).
    fast_start = min(max(int(0.05 * fps), 2), max(n - 1, 0))
    if fast_start < n:
        fast_idx = fast_start + int(np.argmax(right_speed[fast_start:]))
    else:
        fast_idx = int(np.argmax(right_speed))

    # TOP must be before FAST.
    if fast_idx > 0:
        top_idx = int(np.argmin(right_y[:fast_idx]))
    else:
        top_idx = int(np.argmin(right_y))

    # DOWN: lowest point (max Y) near FAST.
    win = max(int(0.20 * fps), 3)
    down_start = max(top_idx + 1, fast_idx - win)
    down_end = min(n, fast_idx + win + 1)
    if down_start < down_end:
        down_idx = down_start + int(np.argmax(right_y[down_start:down_end]))
    else:
        down_idx = fast_idx

    # For backward compatibility, use DOWN as impact proxy.
    impact_idx = int(down_idx)
    confidence = float(np.clip(_norm(right_speed)[fast_idx], 0.0, 1.0))

    impact_time = impact_idx / fps
    return ImpactResult(
        impact_frame=int(impact_idx),
        impact_time_sec=float(impact_time),
        confidence=float(confidence),
        handedness=handedness,
        top_frame=int(top_idx),
        down_frame=int(down_idx),
        backswing_top_frame=int(top_idx),
        lowest_wrist_frame=int(down_idx),
        left_top_frame=None,
        right_top_frame=int(top_idx),
        left_low_frame=None,
        right_low_frame=int(down_idx),
        left_peak_speed_frame=None,
        right_peak_speed_frame=int(fast_idx),
        follow_through_frame=None,
    )
