"""
ball_trajectory_worker.py  —  Server-side ball trajectory extractor

移植自 trajectory_tracker_v3_stable.py，無 GUI、無影片渲染。
加入 hitSec 視窗支援（只在擊球附近搜尋）。

CLI:
    python ball_trajectory_worker.py \
        --video /tmp/clip.mp4 \
        [--hit_sec 2.5] \
        [--flip_mode 0] \
        [--roi_cx_ratio 0.5984] \
        [--roi_cy_ratio 0.3759] \
        [--roi_radius 200]

stdout: JSON  { "track_pts": [[x,y],...], "fps": float,
                "width": int, "height": int, "rotation": int }
stderr: 進度 / debug log

flip_mode 說明（與 Python cv2 語意一致）:
  0 = 不旋轉（Android coded-space 影片，OpenCV 讀取已是 landscape）
  5 = ROTATE_90_CCW（portrait 存儲但無 rotation metadata 的影片）
"""
from __future__ import annotations

import argparse
import json
import math
import subprocess
import sys
from collections import deque
from typing import Dict, List, Optional, Tuple

import cv2
import numpy as np


# ──────────────────────────────────────────────────────────────
# 常數（對應 trajectory_tracker_v3_stable.py + Android BallTracker）
# ──────────────────────────────────────────────────────────────

AREA_LO_BASE   = 6
AREA_HI_BASE   = 150
CIRC_BASE      = 0.55
DIFF_THRESH    = 18
MORPH_K        = 3

CFG_SPEED      = 0.4
CIRC_MIN       = 0.45
AREA_LO_MIN    = 6

# FAR adaptive
ENABLE_FAR_ADAPTIVE = True
FAR_CIRC_FLOOR      = 0.35
FAR_AREA_LO_FLOOR   = 1
FAR_RELAX_GAIN      = 1.0
FAR_AREA_EMA_ALPHA  = 0.20
FAR_FEW_CANDS_MAX   = 3
FAR_MANY_CANDS_STOP = 25

# P0 / P1
P1_DEADLINE_FRAMES = 25
P1_MIN_DIST_PX     = 0.0
P1_MAX_DIST_PX     = 320.0
WAIT_MAX_FRAMES    = 180

# Tracking stop
NO_CAND_PATIENCE             = 5
NO_CAND_PATIENCE_POST_IMPACT = 20
TOO_MANY_CANDS_THRESHOLD     = 4
BLUE_P_OFFSET                = -2
BLUE_TO_LAST_P_MAX_DIST      = 150.0

# Y direction
USE_Y_DIRECTION    = True
STRICT_Y_DIRECTION = False
Y_TOL              = 1
Y_MAX_STEP         = 80

# Step guard phases
EARLY_PHASE_LEN              = 5
STEP_ABS_HARD_MAX_EARLY      = 130.0
STEP_ABS_HARD_MAX_STABLE     = 160.0
STEP_ABS_HARD_MAX_MISS       = 200.0
STEP_ABS_HARD_MAX_POST_IMPACT= 350.0
PRED_DIST_HARD_MAX_EARLY     = 170.0
PRED_DIST_HARD_MAX_STABLE    = 210.0
PRED_DIST_HARD_MAX_MISS      = 250.0
PRED_DIST_HARD_MAX_POST_IMPACT=450.0

STEP_EMA_ALPHA       = 0.25
STEP_GROWTH_FACTOR   = 1.9
STEP_ABS_MAX         = 140.0
OUTLIER_STRIKES_FREEZE = 8

# hitSec 搜尋視窗
HIT_LEAD_FRAMES  = 5
HIT_TRAIL_FRAMES = 25

# trackQuality
TQ_INIT      = 50.0
TQ_GOOD_HIT  = 3.0
TQ_JUMP_HIT  = 0.5
TQ_BAD_REJECT= -6.0
TQ_MISS      = -2.5
TQ_MIN_STOP  = 18.0

# ROI miss 擴張
ROI_MISS_SCALE_MID   = 1.8
ROI_MISS_SCALE_LARGE = 3.2
ROI_HALF_MAX_ABS     = 280.0

# ──────────────────────────────────────────────────────────────
# Kalman 2D
# ──────────────────────────────────────────────────────────────

class Kalman2D:
    def __init__(self, dt: float):
        self.dt = dt
        self.x  = np.zeros((4, 1), dtype=np.float64)
        self.P  = np.eye(4, dtype=np.float64) * 1000
        self.I  = np.eye(4, dtype=np.float64)
        self.A  = np.array([[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]], dtype=np.float64)
        self.H  = np.array([[1,0,0,0],[0,1,0,0]], dtype=np.float64)
        self.Q  = np.diag([3.0, 3.0, 120.0, 120.0])
        self.R  = np.diag([10.0, 10.0])
        self.initialized = False

    def init_from_points(self, p0: Tuple[float,float], p1: Tuple[float,float]):
        dt = max(self.dt, 1e-6)
        vx, vy = (p1[0]-p0[0])/dt, (p1[1]-p0[1])/dt
        self.x[:, 0] = [p1[0], p1[1], vx, vy]
        self.P = np.diag([80., 80., 900., 900.])
        self.initialized = True

    def predict(self):
        self.x = self.A @ self.x
        self.P = self.A @ self.P @ self.A.T + self.Q

    def update(self, zx: float, zy: float):
        z = np.array([[zx], [zy]], dtype=np.float64)
        y = z - self.H @ self.x
        S = self.H @ self.P @ self.H.T + self.R
        try:
            K = self.P @ self.H.T @ np.linalg.inv(S)
        except np.linalg.LinAlgError:
            K = self.P @ self.H.T @ np.linalg.pinv(S)
        self.x = self.x + K @ y
        self.P = (self.I - K @ self.H) @ self.P

    @property
    def pos(self) -> Tuple[float, float]:
        return float(self.x[0,0]), float(self.x[1,0])


# ──────────────────────────────────────────────────────────────
# 像素偵測（幀差 + 形態開運算 + BFS）
# ──────────────────────────────────────────────────────────────

def _detect_blobs(cur_gray: np.ndarray, prev_gray: np.ndarray,
                  diff_thresh: int, area_lo: int, area_hi: int,
                  circ_min: float) -> List[Dict]:
    diff = cv2.absdiff(cur_gray, prev_gray)
    _, binary = cv2.threshold(diff, diff_thresh, 255, cv2.THRESH_BINARY)
    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (MORPH_K, MORPH_K))
    opened = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)

    h, w = opened.shape
    visited = np.zeros((h, w), dtype=bool)
    blobs: List[Dict] = []

    for sy in range(h):
        for sx in range(w):
            if not opened[sy, sx] or visited[sy, sx]:
                continue
            # BFS
            queue = deque([(sx, sy)])
            visited[sy, sx] = True
            sum_x, sum_y, area, perim, diff_sum = 0, 0, 0, 0, 0
            while queue:
                cx, cy = queue.popleft()
                sum_x += cx; sum_y += cy; area += 1
                diff_sum += int(diff[cy, cx])
                is_border = False
                for nx, ny in ((cx-1,cy),(cx+1,cy),(cx,cy-1),(cx,cy+1)):
                    if nx < 0 or nx >= w or ny < 0 or ny >= h:
                        is_border = True; continue
                    if not opened[ny, nx]:
                        is_border = True; continue
                    if not visited[ny, nx]:
                        visited[ny, nx] = True
                        queue.append((nx, ny))
                if is_border:
                    perim += 1
            if not (area_lo <= area <= area_hi):
                continue
            circ = (4.0 * math.pi * area / (perim * perim)) if perim > 0 else 0.0
            if circ < circ_min:
                continue
            blobs.append({
                "cx": sum_x // area,
                "cy": sum_y // area,
                "area": area,
                "circ": circ,
                "diff_mean": diff_sum / area,
            })
    return blobs


def _get_dynamic_cfg(p_index: int, miss_count: int,
                     area_ema: Optional[float]) -> Tuple[int, int, float]:
    t  = max(p_index - 1, 0)
    tt = CFG_SPEED * t
    relax = 1.0 / (1.0 + 0.45 * tt)
    lo   = max(AREA_LO_MIN, min(round(AREA_LO_BASE * relax), AREA_LO_BASE))
    hi   = max(lo + 2, min(round(AREA_HI_BASE * (0.80 + 0.20 * relax)), AREA_HI_BASE))
    circ = max(CIRC_MIN, min(CIRC_BASE * (0.90 * relax + 0.10), CIRC_BASE))

    if ENABLE_FAR_ADAPTIVE and miss_count > 0:
        k = miss_count * FAR_RELAX_GAIN
        lo   = max(FAR_AREA_LO_FLOOR, round(lo - 0.8 * k))
        hi   = round(hi + 1.2 * k)
        if area_ema and area_ema > 0:
            lo = min(lo, max(FAR_AREA_LO_FLOOR, round(area_ema * 0.35)))
            hi = max(hi, round(area_ema * 2.8))
        hi   = max(lo + 2, hi)
        circ = max(FAR_CIRC_FLOOR, circ - 0.03 * k)
    return lo, hi, circ


# ──────────────────────────────────────────────────────────────
# 主追蹤函式
# ──────────────────────────────────────────────────────────────

def extract_trajectory(
    video_path: str,
    hit_sec: Optional[float] = None,
    flip_mode: int = 0,
    roi_cx_ratio: float = 1149.0/1920,
    roi_cy_ratio: float = 406.0/1080,
    roi_radius: int = 200,
) -> Dict:
    """
    從影片擷取球軌跡點。

    座標空間說明
    -----------
    所有輸出座標均在 **coded space**（即 Android 錄製的 landscape 空間，
    rotation metadata 尚未 apply）。renderer 也在此空間作業。

    roi_cx_ratio / roi_cy_ratio 是 coded space 的比例；函式內部會自動
    處理 OpenCV 是否 auto-apply rotation，然後將 track_pts 轉回 coded space。

    Returns:
        {
          "track_pts": [{"x","y","frame_idx","pts_us"}, ...],  # coded-space
          "fps": float,
          "width": int,   # coded width
          "height": int,  # coded height
          "rotation": int,
        }
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"無法開啟影片: {video_path}")

    fps   = cap.get(cv2.CAP_PROP_FPS) or 30.0
    raw_w = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    raw_h = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

    # 讀取 rotation metadata
    rotation = _read_rotation_metadata(video_path)

    # ── 偵測 OpenCV 是否 auto-apply rotation ──────────────────
    # 對於 rotation=90/270 的 Android 影片：
    #   coded space: 1920×1080 (landscape, raw_w > raw_h)
    #   如果 OpenCV auto-rotated: 回傳 portrait (raw_w < raw_h)
    opencv_auto_rotated = (rotation in (90, 270)) and (raw_h > raw_w)
    if opencv_auto_rotated:
        coded_w, coded_h = raw_h, raw_w   # OpenCV swapped dimensions
    else:
        coded_w, coded_h = raw_w, raw_h

    # algo space = 實際 OpenCV 回傳的空間（不再額外 flip）
    algo_w, algo_h = raw_w, raw_h

    # ── ROI：caller 傳入的比例是 coded space，轉換到 algo space ──
    # coded ROI 中心
    coded_roi_cx = coded_w * roi_cx_ratio   # e.g. 1920 * 0.5984 = 1149
    coded_roi_cy = coded_h * roi_cy_ratio   # e.g. 1080 * 0.3759 = 406
    if opencv_auto_rotated:
        # coded(cx,cy) → algo/portrait: ax = coded_h-1-cy, ay = cx
        roi_cx = round(coded_h - 1 - coded_roi_cy)  # portrait x
        roi_cy = round(coded_roi_cx)                 # portrait y
    else:
        roi_cx = round(coded_roi_cx)
        roi_cy = round(coded_roi_cy)
    roi_r = roi_radius

    # ── 靜止幀自動偵測球位：比 hardcoded ROI 更準確 ────────────
    auto_cx, auto_cy = _detect_static_ball(cap, fps, hit_sec, algo_w, algo_h,
                                            opencv_auto_rotated, coded_w, coded_h)
    if auto_cx is not None:
        roi_cx, roi_cy = auto_cx, auto_cy
        print(f"[worker] ✅ 靜止球偵測 → algo ROI=({roi_cx},{roi_cy})", file=sys.stderr)
    else:
        print(f"[worker] ⚠️ 靜止球偵測失敗，使用預設 ROI=({roi_cx},{roi_cy})", file=sys.stderr)

    print(f"[worker] video={raw_w}x{raw_h} fps={fps:.1f} "
          f"coded={coded_w}x{coded_h} rot={rotation}° "
          f"auto_rot={opencv_auto_rotated} "
          f"algo ROI=({roi_cx},{roi_cy}) r={roi_r}", file=sys.stderr)

    dt = 1.0 / max(fps, 1.0)
    kf = Kalman2D(dt=dt)

    # hitSec 視窗
    hit_frame_idx    = round(hit_sec * fps) if hit_sec is not None else -1
    hit_win_start    = max(0, hit_frame_idx - HIT_LEAD_FRAMES) if hit_frame_idx >= 0 else 0
    hit_win_end      = hit_frame_idx + HIT_TRAIL_FRAMES         if hit_frame_idx >= 0 else -1

    if hit_frame_idx >= 0:
        print(f"[worker] hitFrame={hit_frame_idx} window=[{hit_win_start},{hit_win_end}]",
              file=sys.stderr)

    # 追蹤狀態
    STATE_WAIT_P0, STATE_WAIT_P1, STATE_TRACKING, STATE_STOPPED = 0, 1, 2, 3
    state        = STATE_WAIT_P0
    # track_pts 存 (x, y, frame_idx)，frame_idx 為影片全局 0-based 幀號
    track_pts: List[Tuple[int,int,int]] = []
    p0_frame_idx = -1
    wait_frames  = 0
    no_cand_cnt  = 0
    step_ema: Optional[float]  = None
    area_ema: Optional[float]  = None
    y_dir: Optional[int]       = None
    blue_hist: deque = deque(maxlen=10)
    outlier_strikes = 0
    track_quality   = TQ_INIT

    prev_gray: Optional[np.ndarray] = None
    frame_idx = 0

    while True:
        ret, frame0 = cap.read()
        if not ret:
            break

        # 翻轉 / 旋轉
        frame = _apply_flip(frame0, flip_mode)
        gray  = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        frame_idx += 1
        fi = frame_idx - 1  # 0-based

        if prev_gray is None:
            prev_gray = gray
            continue

        # Kalman 預測
        blue_pred: Optional[Tuple[float,float]] = None
        if state == STATE_TRACKING and kf.initialized:
            kf.predict()
            blue_pred = kf.pos
            blue_hist.append(blue_pred)

        # 動態門檻偵測 blobs
        p_index = max(len(track_pts) - 1, 0)
        if state in (STATE_WAIT_P0, STATE_WAIT_P1):
            lo, hi, circ_thr = AREA_LO_BASE, AREA_HI_BASE, CIRC_BASE
        else:
            lo, hi, circ_thr = _get_dynamic_cfg(p_index, no_cand_cnt, area_ema)

        raw_blobs = _detect_blobs(gray, prev_gray, DIFF_THRESH, lo, hi, circ_thr)

        # ROI 篩選
        blobs = _roi_filter(raw_blobs, state, roi_cx, roi_cy, roi_r,
                            track_pts, no_cand_cnt, blue_pred)

        # 狀態機
        if state == STATE_WAIT_P0:
            state = _handle_wait_p0(fi, blobs, track_pts, roi_cx, roi_cy,
                                     hit_win_start, hit_win_end,
                                     wait_frames)
            if state != STATE_WAIT_P0:
                p0_frame_idx = fi
                wait_frames  = 0
            else:
                wait_frames += 1
                if wait_frames >= WAIT_MAX_FRAMES:
                    state = STATE_STOPPED

        elif state == STATE_WAIT_P1:
            result = _handle_wait_p1(fi, blobs, track_pts, p0_frame_idx, kf)
            if result == "reset":
                track_pts.clear()
                state = STATE_WAIT_P0
                p0_frame_idx = -1
                wait_frames  = 0
                kf = Kalman2D(dt=dt)
            elif result == "ok":
                state           = STATE_TRACKING
                no_cand_cnt     = 0
                outlier_strikes = 0
                step_ema        = None
                track_quality   = TQ_INIT

        elif state == STATE_TRACKING:
            assert blue_pred is not None
            state, no_cand_cnt, step_ema, area_ema, y_dir, \
                outlier_strikes, track_quality = _handle_tracking(
                    fi, blobs, track_pts, blue_pred, blue_hist,
                    no_cand_cnt, step_ema, area_ema, y_dir,
                    outlier_strikes, track_quality,
                    roi_r, hit_frame_idx, kf,
                )

        prev_gray = gray

        if state == STATE_STOPPED:
            break

    cap.release()

    dt_us = 1_000_000.0 / max(fps, 1.0)

    # ── algo space → coded space ──────────────────────────────
    # coded space 才是 Android renderer 期待的座標系
    def to_coded(ax: int, ay: int) -> Tuple[int, int]:
        if opencv_auto_rotated:
            # OpenCV applied CW 90°: algo(portrait) → coded(landscape)
            # coded_cx = ay, coded_cy = coded_h-1-ax
            return int(ay), int(coded_h - 1 - ax)
        return int(ax), int(ay)

    result_pts = []
    for p in track_pts:
        ax, ay, fi = p
        cx, cy = to_coded(ax, ay)
        result_pts.append({
            "x": cx, "y": cy,
            "frame_idx": fi,
            "pts_us": int(fi * dt_us),
        })

    print(f"[worker] done: {len(result_pts)} track_pts (coded {coded_w}x{coded_h})",
          file=sys.stderr)

    return {
        "track_pts": result_pts,
        "fps":       fps,
        "width":     coded_w,   # 永遠回傳 coded 尺寸
        "height":    coded_h,
        "rotation":  rotation,
    }


# ──────────────────────────────────────────────────────────────
# 狀態機子函式
# ──────────────────────────────────────────────────────────────

def _handle_wait_p0(fi: int, blobs: List[Dict],
                    track_pts: List, roi_cx: int, roi_cy: int,
                    hit_win_start: int, hit_win_end: int,
                    wait_frames: int) -> int:
    if fi < hit_win_start:
        return 0  # STATE_WAIT_P0
    if hit_win_end >= 0 and fi > hit_win_end:
        return 3  # STATE_STOPPED

    if not blobs:
        return 0

    best = min(blobs, key=lambda b: (b["cx"]-roi_cx)**2 + (b["cy"]-roi_cy)**2)
    track_pts.append((best["cx"], best["cy"], fi))
    print(f"[worker] P0 @ frame {fi} ({best['cx']},{best['cy']})", file=sys.stderr)
    return 1  # STATE_WAIT_P1


def _handle_wait_p1(fi: int, blobs: List[Dict],
                    track_pts: List, p0_frame_idx: int,
                    kf: Kalman2D) -> str:
    if fi - p0_frame_idx > P1_DEADLINE_FRAMES:
        print(f"[worker] P1 deadline expired @ frame {fi}, reset", file=sys.stderr)
        return "reset"
    if not blobs:
        return "wait"

    p0 = track_pts[0]
    valid = [b for b in blobs
             if P1_MIN_DIST_PX <= _dist(b["cx"],b["cy"],p0[0],p0[1]) <= P1_MAX_DIST_PX]
    if not valid:
        return "wait"

    best = min(valid, key=lambda b: _dist2(b["cx"],b["cy"],p0[0],p0[1]))
    track_pts.append((best["cx"], best["cy"], fi))
    kf.init_from_points((float(p0[0]),float(p0[1])),
                        (float(best["cx"]),float(best["cy"])))
    print(f"[worker] P1 @ frame {fi} ({best['cx']},{best['cy']}) "
          f"dist={_dist(best['cx'],best['cy'],p0[0],p0[1]):.1f}", file=sys.stderr)
    return "ok"


def _handle_tracking(fi: int, blobs: List[Dict],
                     track_pts: List, blue_pred: Tuple[float,float],
                     blue_hist: deque,
                     no_cand_cnt: int, step_ema: Optional[float],
                     area_ema: Optional[float], y_dir: Optional[int],
                     outlier_strikes: int, track_quality: float,
                     roi_r: int, hit_frame_idx: int, kf: Kalman2D):
    STATE_TRACKING, STATE_STOPPED = 2, 3
    is_post_impact = hit_frame_idx >= 0 and fi >= hit_frame_idx

    if not blobs:
        no_cand_cnt += 1
        penalty = TQ_MISS * (0.5 if is_post_impact else 1.0)
        track_quality += penalty
        if is_post_impact and kf.initialized:
            px, py = blue_pred
            track_pts.append((round(px), round(py), fi))

        patience = NO_CAND_PATIENCE_POST_IMPACT if is_post_impact else NO_CAND_PATIENCE
        if no_cand_cnt > patience:
            return (STATE_STOPPED, no_cand_cnt, step_ema, area_ema, y_dir,
                    outlier_strikes, track_quality)
        if track_quality < TQ_MIN_STOP and len(track_pts) >= 4:
            return (STATE_STOPPED, no_cand_cnt, step_ema, area_ema, y_dir,
                    outlier_strikes, track_quality)
        return (STATE_TRACKING, no_cand_cnt, step_ema, area_ema, y_dir,
                outlier_strikes, track_quality)

    if len(blobs) >= FAR_MANY_CANDS_STOP:
        track_quality += TQ_MISS
        if track_quality < TQ_MIN_STOP and len(track_pts) >= 4:
            return (STATE_STOPPED, no_cand_cnt, step_ema, area_ema, y_dir,
                    outlier_strikes, track_quality)
        return (STATE_TRACKING, no_cand_cnt, step_ema, area_ema, y_dir,
                outlier_strikes, track_quality)

    no_cand_cnt = 0
    px, py = blue_pred
    tooMany = len(blobs) >= TOO_MANY_CANDS_THRESHOLD
    appended = False

    # 候選過多：用 Kalman 歷史點
    if tooMany and len(blue_hist) > 0:
        idx = len(blue_hist) - 1 + BLUE_P_OFFSET
        idx = max(0, idx)
        if idx < len(blue_hist):
            chosen = blue_hist[idx]
            if track_pts:
                last = track_pts[-1]
                if _dist(round(chosen[0]),round(chosen[1]),last[0],last[1]) <= BLUE_TO_LAST_P_MAX_DIST:
                    track_pts.append((round(chosen[0]), round(chosen[1]), fi))
                    track_quality += TQ_JUMP_HIT
                    appended = True

    if not appended and blobs:
        pool = list(blobs)

        # Y 方向過濾
        if USE_Y_DIRECTION and y_dir is not None and no_cand_cnt == 0 and track_pts:
            last_y = track_pts[-1][1]
            if y_dir < 0:
                pool_y = [b for b in pool if b["cy"] <= last_y + Y_TOL]
            else:
                pool_y = [b for b in pool if b["cy"] >= last_y - Y_TOL]
            pool_y = [b for b in pool_y if abs(b["cy"] - last_y) <= Y_MAX_STEP]
            if pool_y:
                pool = pool_y
            elif STRICT_Y_DIRECTION:
                pool = []

        if pool:
            if len(pool) <= FAR_FEW_CANDS_MAX:
                best = min(pool, key=lambda b: _dist2(b["cx"],b["cy"],round(px),round(py)))
            else:
                best = min(pool, key=lambda b:
                    _dist(b["cx"],b["cy"],round(px),round(py)) - 0.15*b["diff_mean"])

            # Step guard
            accept = True
            is_jump = False
            if track_pts:
                last = track_pts[-1]  # (x, y, frame_idx)
                step     = _dist(best["cx"],best["cy"],last[0],last[1])
                pred_dist= _dist(best["cx"],best["cy"],round(px),round(py))

                base_lim = STEP_ABS_MAX if step_ema is None else max(STEP_ABS_MAX, step_ema * STEP_GROWTH_FACTOR)
                lim      = base_lim * (1.0 + 0.35 * no_cand_cnt)
                hard_step= _phase_step_hard_max(fi, len(track_pts), no_cand_cnt, hit_frame_idx)
                hard_pred= _phase_pred_hard_max(fi, len(track_pts), no_cand_cnt, hit_frame_idx)
                step_lim = min(hard_step, lim)

                if step > step_lim or pred_dist > hard_pred:
                    accept   = False
                    is_jump  = True
                else:
                    is_jump = step_ema is not None and step > step_ema * 1.5
                    step_ema = step if step_ema is None \
                               else (1-STEP_EMA_ALPHA)*step_ema + STEP_EMA_ALPHA*step

            if accept:
                track_quality += TQ_JUMP_HIT if is_jump else TQ_GOOD_HIT
                track_quality  = min(track_quality, 100.0)
                outlier_strikes = 0
                kf.update(float(best["cx"]), float(best["cy"]))
                track_pts.append((best["cx"], best["cy"], fi))
                area_f = float(best["area"])
                area_ema = area_f if area_ema is None \
                           else (1-FAR_AREA_EMA_ALPHA)*area_ema + FAR_AREA_EMA_ALPHA*area_f

                if USE_Y_DIRECTION and y_dir is None and len(track_pts) >= 3:
                    dy = track_pts[-1][1] - track_pts[0][1]  # y component
                    if abs(dy) >= 2:
                        y_dir = 1 if dy > 0 else -1
            else:
                track_quality += TQ_BAD_REJECT
                outlier_strikes += 1
                if outlier_strikes >= OUTLIER_STRIKES_FREEZE and len(track_pts) >= 8:
                    return (STATE_STOPPED, no_cand_cnt, step_ema, area_ema, y_dir,
                            outlier_strikes, track_quality)

    if track_quality < TQ_MIN_STOP and len(track_pts) >= 4:
        return (STATE_STOPPED, no_cand_cnt, step_ema, area_ema, y_dir,
                outlier_strikes, track_quality)

    return (STATE_TRACKING, no_cand_cnt, step_ema, area_ema, y_dir,
            outlier_strikes, track_quality)


# ──────────────────────────────────────────────────────────────
# ROI 篩選
# ──────────────────────────────────────────────────────────────

def _roi_filter(blobs: List[Dict], state: int,
                roi_cx: int, roi_cy: int, roi_r: int,
                track_pts: List, no_cand_cnt: int,
                blue_pred: Optional[Tuple[float,float]]) -> List[Dict]:
    if not blobs:
        return blobs

    if state == 0:  # WAIT_P0
        return [b for b in blobs
                if _dist(b["cx"],b["cy"],roi_cx,roi_cy) <= roi_r]

    if state == 1:  # WAIT_P1
        if not track_pts:
            return blobs
        p0 = track_pts[0]
        return [b for b in blobs
                if _dist(b["cx"],b["cy"],p0[0],p0[1]) <= roi_r]

    if state == 2:  # TRACKING
        radius = _miss_roi_radius(roi_r, no_cand_cnt)
        if no_cand_cnt > 0 and blue_pred is not None:
            cx, cy = round(blue_pred[0]), round(blue_pred[1])
        elif track_pts:
            cx, cy = track_pts[-1][0], track_pts[-1][1]
        else:
            return blobs
        return [b for b in blobs
                if _dist(b["cx"],b["cy"],cx,cy) <= radius]

    return blobs


def _miss_roi_radius(roi_r: int, no_cand_cnt: int) -> float:
    if no_cand_cnt == 0:
        return roi_r
    elif no_cand_cnt <= 2:
        return min(roi_r * ROI_MISS_SCALE_MID,   ROI_HALF_MAX_ABS)
    else:
        return min(roi_r * ROI_MISS_SCALE_LARGE,  ROI_HALF_MAX_ABS)


# ──────────────────────────────────────────────────────────────
# 分階段 step guard
# ──────────────────────────────────────────────────────────────

def _phase_step_hard_max(fi: int, n_pts: int, no_cand: int, hit_fi: int) -> float:
    if hit_fi >= 0 and fi >= hit_fi:
        return STEP_ABS_HARD_MAX_POST_IMPACT
    if n_pts < EARLY_PHASE_LEN:
        return STEP_ABS_HARD_MAX_EARLY
    if no_cand == 0:
        return STEP_ABS_HARD_MAX_STABLE
    return STEP_ABS_HARD_MAX_MISS


def _phase_pred_hard_max(fi: int, n_pts: int, no_cand: int, hit_fi: int) -> float:
    if hit_fi >= 0 and fi >= hit_fi:
        return PRED_DIST_HARD_MAX_POST_IMPACT
    if n_pts < EARLY_PHASE_LEN:
        return PRED_DIST_HARD_MAX_EARLY
    if no_cand == 0:
        return PRED_DIST_HARD_MAX_STABLE
    return PRED_DIST_HARD_MAX_MISS


# ──────────────────────────────────────────────────────────────
# 工具函式
# ──────────────────────────────────────────────────────────────

def _detect_static_ball(
    cap, fps: float, hit_sec: Optional[float],
    algo_w: int, algo_h: int,
    opencv_auto_rotated: bool, coded_w: int, coded_h: int,
) -> Tuple[Optional[int], Optional[int]]:
    """
    在擊球前的靜止幀中用亮度閾值找白色高爾夫球，
    回傳球在 algo space 的 (cx, cy)。找不到回傳 (None, None)。

    高爾夫球特徵：
      - 白色 / 高亮度 (luma > 220)
      - 小圓形 (area 3-120 px, circularity > 0.55)
      - 在畫面下半部（球座在地面）
    """
    # 決定要讀哪一幀：擊球前 ~60 幀（約 2 秒）
    if hit_sec is not None and fps > 0:
        sample_fi = max(0, int(hit_sec * fps) - 60)
    else:
        sample_fi = 0

    saved_pos = cap.get(cv2.CAP_PROP_POS_FRAMES)
    try:
        cap.set(cv2.CAP_PROP_POS_FRAMES, sample_fi)
        ret, frame = cap.read()
        if not ret:
            return None, None

        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)

        # 亮度閾值：高爾夫球在室外通常是最亮的小圓物
        _, binary = cv2.threshold(gray, 210, 255, cv2.THRESH_BINARY)
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        cleaned = cv2.morphologyEx(binary, cv2.MORPH_OPEN, kernel)

        contours, _ = cv2.findContours(cleaned, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)

        # 「在畫面下半部」的判斷要依 algo space 轉換
        # coded space 的 bottom（portrait 顯示的球座位置）：
        #   rotation=90 coded: 球在右半部 (cx > coded_w * 0.6)
        #   portrait algo (auto-rotated): 球在下半部 (ay > algo_h * 0.6)
        #   no rotation coded: 球在下半部 (ay > algo_h * 0.5)
        def _is_in_ball_zone(ax: int, ay: int) -> bool:
            if opencv_auto_rotated:
                return ay > algo_h * 0.55  # portrait: ball at bottom
            elif coded_w > coded_h:        # landscape coded (rotation=90)
                return ax > algo_w * 0.6   # right side = bottom of portrait
            else:
                return ay > algo_h * 0.5

        best_cx, best_cy, best_score = None, None, 0.0
        for cnt in contours:
            area = cv2.contourArea(cnt)
            if not (3 <= area <= 120):
                continue
            perimeter = cv2.arcLength(cnt, True)
            if perimeter < 1:
                continue
            circ = 4 * math.pi * area / (perimeter ** 2)
            if circ < 0.55:
                continue
            M = cv2.moments(cnt)
            if M['m00'] == 0:
                continue
            ax = int(M['m10'] / M['m00'])
            ay = int(M['m01'] / M['m00'])
            if not _is_in_ball_zone(ax, ay):
                continue
            # 分數：圓度 × 亮度均值 × 位置（越靠近典型球位越高分）
            score = circ * (gray[ay, ax] / 255.0)
            if score > best_score:
                best_score, best_cx, best_cy = score, ax, ay

        return best_cx, best_cy

    except Exception as e:
        print(f"[worker] _detect_static_ball 失敗: {e}", file=sys.stderr)
        return None, None
    finally:
        cap.set(cv2.CAP_PROP_POS_FRAMES, saved_pos)


def _apply_flip(frame: np.ndarray, mode: int) -> np.ndarray:
    if mode == 1: return cv2.flip(frame, 0)
    if mode == 2: return cv2.flip(frame, 1)
    if mode == 3: return cv2.flip(frame, -1)
    if mode == 4: return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if mode == 5: return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if mode == 6: return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def _read_rotation_metadata(video_path: str) -> int:
    """用 ffprobe 讀取影片 rotation metadata（OpenCV 不支援）。"""
    try:
        r = subprocess.run(
            ["ffprobe", "-v", "quiet", "-select_streams", "v:0",
             "-show_entries", "stream_tags=rotate",
             "-of", "default=noprint_wrappers=1:nokey=1",
             video_path],
            capture_output=True, text=True, timeout=5)
        rot = int(r.stdout.strip()) if r.stdout.strip() else 0
        return rot
    except Exception:
        return 0


def _dist(ax: int, ay: int, bx: int, by: int) -> float:
    return math.sqrt((ax-bx)**2 + (ay-by)**2)


def _dist2(ax: int, ay: int, bx: int, by: int) -> float:
    return (ax-bx)**2 + (ay-by)**2


# ──────────────────────────────────────────────────────────────
# CLI entry point
# ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(description="Ball trajectory extractor for server-side use")
    parser.add_argument("--video",        required=True,  help="影片路徑")
    parser.add_argument("--hit_sec",      type=float,     default=None,   help="擊球秒數（可選）")
    parser.add_argument("--flip_mode",    type=int,       default=0,      help="翻轉模式（0=不翻）")
    parser.add_argument("--roi_cx_ratio", type=float,     default=1149/1920, help="ROI 中心 X 比例")
    parser.add_argument("--roi_cy_ratio", type=float,     default=406/1080,  help="ROI 中心 Y 比例")
    parser.add_argument("--roi_radius",   type=int,       default=200,    help="ROI 半徑（px）")
    args = parser.parse_args()

    result = extract_trajectory(
        video_path   = args.video,
        hit_sec      = args.hit_sec,
        flip_mode    = args.flip_mode,
        roi_cx_ratio = args.roi_cx_ratio,
        roi_cy_ratio = args.roi_cy_ratio,
        roi_radius   = args.roi_radius,
    )

    # JSON to stdout（C# 讀取）
    print(json.dumps(result, ensure_ascii=False))


if __name__ == "__main__":
    main()
