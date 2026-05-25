# ============================================================
# Stable Profile (2026-03-31)
# This file freezes the currently validated trajectory settings.
# ============================================================

import cv2
import numpy as np
from dataclasses import dataclass
from typing import Tuple, List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime

# ============================================================
# Batch / input
# ============================================================
BATCH_MODE = False
INPUT_DIR = r"Y:\Software Engineering\Project\Golf\Test_data\hit_catch\V1"
BATCH_OUTPUT_DIR = r""
VIDEO_PATH = r"hit_003.mp4"
AUTO_DISABLE_UI_IN_BATCH = True

# ============================================================
# Tracking setup
# ============================================================
TRACK_FRAMES: Optional[int] = None  # None=process full video
FLIP_MODE = 5
EXPORT_VIDEO = True
OUT_VIDEO_PATH = None
OUT_ROTATE_MODE = 4
DRAW_TRAJ_UNTIL_PN = None

TRAJ_COLOR_BGR = (255, 220, 160)
TRAJ_ALPHA = 0.8
TRAJ_THICKNESS = 6
TRAJ_DRAW_FROM_P0 = True
TRAJ_MIN_POINTS = 2

P1_MUST_APPEAR_NEXT_FRAME = True
P1_DEADLINE_FRAMES = 1

STEP_MODE_AFTER_P1 = False
ENTER_KEYS = {13, 10}
ESC_KEY = 27

TOO_MANY_CANDS_USE_BLUE_AS_P = True
TOO_MANY_CANDS_THRESHOLD = 4
BLUE_P_OFFSET = -2
BLUE_TO_LASTP_MAX_DIST: Optional[float] = 150.0

SHOW_MAIN = True
SHOW_DEBUG_ROI = True

DETECT_CFG_BASE = dict(
    area_range=(6, 150),
    circ_thresh=0.60,
    diff_thresh=16,
    show_debug=True,
    debug_prefix="DEBUG",
)

MIN_DX = 3
WAIT_MAX_FRAMES = 180
DRAW_CAND_STATS = True
CAND_TEXT_SCALE = 0.42
CAND_TEXT_THICKNESS = 1

ROI_CFG = dict(
    size_init=500,
    size_min=400,
    shrink_over_frames=60,
    center_alpha=0.4,
    max_center_step=80,
)

CFG_SPEED = 0.4
DIFF_MIN = 9
CIRC_MIN = 0.60
AREA_LO_MIN = 6

USE_Y_DIRECTION = True
STRICT_Y_DIRECTION = False
Y_TOL = 1
Y_MAX_STEP = 80

# ============================================================
# New optimization switches (requested)
# ============================================================
FIXED_ROI_MODE = True
FIXED_ROI_CENTER = (1084, 376)

# 1) ROI center tracks latest valid point, size fixed (no shrinking)
ROI_CENTER_LOCK_TO_LAST = True
ROI_FIXED_SIZE = 400

# 2) Stop tracking when no diff candidate
STOP_WHEN_NO_CAND_IN_TRACK = True
NO_CAND_PATIENCE = 4

# Recovery when ball gets small/far:
# enlarge ROI and use predicted center for a few missing frames.
RECOVERY_USE_KALMAN_CENTER_ON_MISS = True
RECOVERY_ROI_GROW_PER_MISS = 35
RECOVERY_ROI_MAX = 420

# 3) Disable forced-left rule; use step-distance sanity check
USE_LEFT_RULE = False
USE_STEP_DIST_GUARD = True
STEP_EMA_ALPHA = 0.25
STEP_GROWTH_FACTOR = 1.9
STEP_ABS_MAX = 140.0
STEP_ABS_HARD_MAX = 130.0
PRED_DIST_HARD_MAX = 170.0
OUTLIER_STRIKES_TO_FREEZE = 8

# 4) Far-ball adaptive detection
ENABLE_FAR_ADAPTIVE = True
FAR_DIFF_FLOOR = 3
FAR_CIRC_FLOOR = 0.35
FAR_AREA_LO_FLOOR = 1
FAR_RELAX_GAIN = 1.0
FAR_AREA_EMA_ALPHA = 0.20
FAR_FEW_CANDS_MAX = 3
FAR_MANY_CANDS_STOP = 25

clicked_point: Optional[Tuple[int, int]] = None


def on_mouse(event, x, y, flags, param):
    global clicked_point
    if event == cv2.EVENT_LBUTTONDOWN:
        clicked_point = (x, y)


def apply_flip(frame: np.ndarray, mode: int) -> np.ndarray:
    if mode == 0:
        return frame
    if mode == 1:
        return cv2.flip(frame, 0)
    if mode == 2:
        return cv2.flip(frame, 1)
    if mode == 3:
        return cv2.flip(frame, -1)
    if mode == 4:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if mode == 5:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if mode == 6:
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def apply_out_rotate(frame: np.ndarray, mode: int) -> np.ndarray:
    if mode == 0:
        return frame
    if mode == 4:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    if mode == 5:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    if mode == 6:
        return cv2.rotate(frame, cv2.ROTATE_180)
    return frame


def preprocess_gray(gray: np.ndarray) -> np.ndarray:
    gray_f = cv2.medianBlur(gray, 3)
    gray_f = cv2.bilateralFilter(gray_f, d=5, sigmaColor=30, sigmaSpace=5)
    return gray_f


def clamp_step(cur: np.ndarray, target: np.ndarray, max_step: float) -> np.ndarray:
    d = target - cur
    dist = float(np.linalg.norm(d))
    if dist <= max_step or dist < 1e-6:
        return target
    return cur + d * (max_step / dist)


def get_dynamic_detect_cfg(p_index: int, roi_size: int) -> Dict[str, Any]:
    cfg = dict(DETECT_CFG_BASE)
    s = float(roi_size) / float(ROI_CFG["size_init"])
    s = float(np.clip(s, 0.20, 1.0))

    t = max(p_index - 1, 0)
    tt = CFG_SPEED * t
    relax = 1.0 / (1.0 + 0.45 * tt)

    base_lo, base_hi = DETECT_CFG_BASE["area_range"]

    lo = int(round(base_lo * (s ** 2) * relax))
    lo = max(AREA_LO_MIN, min(lo, base_lo))

    hi = int(round(base_hi * (s ** 2) * (0.80 + 0.20 * relax)))
    hi = max(lo + 2, min(hi, base_hi))

    cfg["area_range"] = (lo, hi)

    base_thr = float(DETECT_CFG_BASE["diff_thresh"])
    thr = base_thr * (0.55 * s + 0.45) * relax
    thr = float(np.clip(thr, DIFF_MIN, base_thr))
    cfg["diff_thresh"] = int(round(thr))

    base_c = float(DETECT_CFG_BASE["circ_thresh"])
    circ = base_c * (0.90 * relax + 0.10)
    circ = float(np.clip(circ, CIRC_MIN, base_c))
    cfg["circ_thresh"] = circ

    return cfg


def get_far_adaptive_cfg(base_cfg: Dict[str, Any], miss_count: int, area_ema: Optional[float]) -> Dict[str, Any]:
    cfg = dict(base_cfg)
    if not ENABLE_FAR_ADAPTIVE or miss_count <= 0:
        return cfg

    k = float(miss_count) * float(FAR_RELAX_GAIN)
    lo0, hi0 = cfg["area_range"]

    # As misses increase, allow smaller blobs and lower contrast / circularity.
    lo = max(FAR_AREA_LO_FLOOR, int(round(lo0 - 0.8 * k)))
    hi = int(round(hi0 + 1.2 * k))

    # If we have an estimated ball size, bias area range around it.
    if area_ema is not None and area_ema > 0:
        lo = min(lo, max(FAR_AREA_LO_FLOOR, int(round(area_ema * 0.35))))
        hi = max(hi, int(round(area_ema * 2.8)))

    hi = max(lo + 2, hi)
    cfg["area_range"] = (lo, hi)

    cfg["diff_thresh"] = max(FAR_DIFF_FLOOR, int(round(cfg["diff_thresh"] - 1.2 * k)))
    cfg["circ_thresh"] = max(FAR_CIRC_FLOOR, float(cfg["circ_thresh"] - 0.03 * k))
    return cfg


def detect_candidates_with_stats(cur_gray: np.ndarray, prev_gray: np.ndarray, cfg: Dict[str, Any]) -> List[Dict[str, Any]]:
    if cur_gray is None or prev_gray is None:
        return []
    if cur_gray.size == 0 or prev_gray.size == 0:
        return []
    if cur_gray.shape != prev_gray.shape:
        return []

    area_range = cfg["area_range"]
    circ_thresh = cfg["circ_thresh"]
    diff_thresh = cfg["diff_thresh"]
    show_debug = cfg.get("show_debug", False)
    prefix = cfg.get("debug_prefix", "DEBUG")

    diff = cv2.absdiff(cur_gray, prev_gray)
    _, binary = cv2.threshold(diff, diff_thresh, 255, cv2.THRESH_BINARY)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))

    if show_debug and SHOW_DEBUG_ROI:
        cv2.imshow(f"{prefix}_DIFF", diff)
        cv2.imshow(f"{prefix}_BINARY", binary)
        cv2.waitKey(1)

    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    results: List[Dict[str, Any]] = []
    for cnt in contours:
        area = float(cv2.contourArea(cnt))
        if not (area_range[0] <= area <= area_range[1]):
            continue

        peri = float(cv2.arcLength(cnt, True))
        if peri <= 1e-6:
            continue

        circ = float(4 * np.pi * area / (peri ** 2))
        if circ < circ_thresh:
            continue

        M = cv2.moments(cnt)
        if M["m00"] == 0:
            continue
        cx = int(M["m10"] / M["m00"])
        cy = int(M["m01"] / M["m00"])

        mask = np.zeros_like(diff, dtype=np.uint8)
        cv2.drawContours(mask, [cnt], -1, 255, -1)
        mean_diff = float(cv2.mean(diff, mask=mask)[0])

        results.append({"pt_roi": (cx, cy), "area": area, "circ": circ, "diff": mean_diff})

    return results


@dataclass
class KFParams:
    dt: float
    process_pos_var: float = 3.0
    process_vel_var: float = 120.0
    meas_var: float = 10.0


class KalmanFilter2D:
    def __init__(self, p: KFParams):
        self.p = p
        self.x = np.zeros((4, 1), np.float32)
        self.P = np.eye(4, dtype=np.float32) * 1000
        self.I = np.eye(4, dtype=np.float32)
        self.initialized = False
        self._build()

    def _build(self):
        dt = self.p.dt
        self.A = np.array([[1, 0, dt, 0], [0, 1, 0, dt], [0, 0, 1, 0], [0, 0, 0, 1]], np.float32)
        self.H = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], np.float32)
        self.Q = np.diag([self.p.process_pos_var] * 2 + [self.p.process_vel_var] * 2).astype(np.float32)
        self.R = np.diag([self.p.meas_var] * 2).astype(np.float32)

    def initialize_from_two_points(self, p0: Tuple[int, int], p1: Tuple[int, int]):
        dt = max(self.p.dt, 1e-6)
        vx = (p1[0] - p0[0]) / dt
        vy = (p1[1] - p0[1]) / dt
        self.x[:, 0] = np.array([p1[0], p1[1], vx, vy], dtype=np.float32)
        self.P = np.diag([80, 80, 900, 900]).astype(np.float32)
        self.initialized = True
        print(f"Kalman init: p0={p0}, p1={p1}, v=({vx:.1f},{vy:.1f})")

    def predict(self):
        self.x = self.A @ self.x
        self.P = self.A @ self.P @ self.A.T + self.Q

    def update(self, z_xy: Tuple[int, int]):
        z = np.array(z_xy, np.float32).reshape(2, 1)
        y = z - self.H @ self.x
        S = self.H @ self.P @ self.H.T + self.R
        try:
            invS = np.linalg.inv(S)
        except np.linalg.LinAlgError:
            invS = np.linalg.pinv(S)
        K = self.P @ self.H.T @ invS
        self.x = self.x + K @ y
        self.P = (self.I - K @ self.H) @ self.P

    def pos(self) -> Tuple[float, float]:
        return float(self.x[0, 0]), float(self.x[1, 0])


def pick_blue_from_history(blue_hist: List[np.ndarray], offset: int) -> Optional[np.ndarray]:
    if not blue_hist:
        return None
    if offset > 0:
        offset = 0
    idx = -1 + offset
    if abs(idx) > len(blue_hist):
        return None
    return blue_hist[idx]


def make_out_path(video_path: str, out_dir: Optional[str]) -> str:
    p = Path(video_path)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_name = f"{p.stem}_traj_{ts}.mp4"
    if out_dir is None:
        return str(p.with_name(out_name))
    od = Path(out_dir)
    od.mkdir(parents=True, exist_ok=True)
    return str(od / out_name)


def draw_traj_overlay_only(
    base_bgr: np.ndarray,
    pts: List[Tuple[int, int]],
    pn: Optional[int],
    color_bgr: Tuple[int, int, int],
    alpha: float,
    thickness: int,
    draw_from_p0: bool,
    min_points: int,
) -> np.ndarray:
    if pts is None or len(pts) < min_points:
        return base_bgr

    max_idx = len(pts) - 1
    if pn is not None:
        max_idx = min(max_idx, int(pn))

    start_idx = 0 if draw_from_p0 else 1
    if max_idx - start_idx + 1 < min_points:
        return base_bgr

    overlay = base_bgr.copy()
    for i in range(start_idx + 1, max_idx + 1):
        cv2.line(overlay, pts[i - 1], pts[i], color_bgr, thickness, cv2.LINE_AA)

    return cv2.addWeighted(overlay, alpha, base_bgr, 1.0 - alpha, 0)


STATE_WAIT_P0 = 0
STATE_WAIT_P1 = 1
STATE_TRACKING = 2
STATE_TRACK_STOPPED = 3


def process_one_video(video_path: str, out_dir: Optional[str]) -> Optional[str]:
    global clicked_point

    print("\n" + "=" * 80)
    print("Process:", video_path)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("Cannot open:", video_path)
        return None

    fps = cap.get(cv2.CAP_PROP_FPS)
    dt = 1.0 / max(fps, 1.0)
    print(f"FPS={fps:.3f}, dt={dt:.4f}")

    clicked_point = None
    kf = KalmanFilter2D(KFParams(dt=dt))
    prev_gray: Optional[np.ndarray] = None
    frame_idx = 0

    roi_center: Optional[Tuple[int, int]] = None
    state = STATE_WAIT_P0
    wait_frames = 0

    track_pts: List[Tuple[int, int]] = []
    p0_frame_idx: Optional[int] = None

    roi_center_smooth: Optional[np.ndarray] = None
    y_dir: Optional[int] = None
    step_mode_active = False
    blue_hist: List[np.ndarray] = []
    no_cand_count = 0
    step_ema: Optional[float] = None
    area_ema: Optional[float] = None
    outlier_strikes = 0

    writer = None
    out_path = OUT_VIDEO_PATH

    if FIXED_ROI_MODE:
        roi_center = tuple(map(int, FIXED_ROI_CENTER))
        print("FIXED ROI center:", roi_center)

    while True:
        ret, frame0 = cap.read()
        if not ret:
            break
        frame_idx += 1

        frame = apply_flip(frame0, FLIP_MODE)
        raw_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = preprocess_gray(raw_gray)

        if frame_idx == 1:
            if (roi_center is None) and (not FIXED_ROI_MODE):
                temp = frame.copy()
                cv2.namedWindow("FIRST_FRAME_CLICK", cv2.WINDOW_NORMAL)
                cv2.setMouseCallback("FIRST_FRAME_CLICK", on_mouse)
                print("Click ROI center, press key to confirm")
                while True:
                    vis0 = temp.copy()
                    if clicked_point is not None:
                        cv2.circle(vis0, clicked_point, 6, (0, 0, 255), -1)
                    cv2.imshow("FIRST_FRAME_CLICK", vis0)
                    if cv2.waitKey(20) != -1:
                        break
                cv2.destroyWindow("FIRST_FRAME_CLICK")
                roi_center = clicked_point if clicked_point else (gray.shape[1] // 2, gray.shape[0] // 2)
                print("ROI center =", roi_center)

            if EXPORT_VIDEO and writer is None:
                if out_path is None:
                    out_path = make_out_path(video_path, out_dir)
                probe = apply_out_rotate(frame.copy(), OUT_ROTATE_MODE)
                oh, ow = probe.shape[:2]
                fourcc = cv2.VideoWriter_fourcc(*"mp4v")
                writer = cv2.VideoWriter(out_path, fourcc, float(max(fps, 1.0)), (ow, oh))
                if not writer.isOpened():
                    print("VideoWriter open failed:", out_path)
                    writer = None
                else:
                    print("Output:", out_path)

        if prev_gray is None:
            prev_gray = gray
            if writer is not None:
                out_vis = draw_traj_overlay_only(
                    frame.copy(), track_pts, DRAW_TRAJ_UNTIL_PN,
                    TRAJ_COLOR_BGR, TRAJ_ALPHA, TRAJ_THICKNESS,
                    TRAJ_DRAW_FROM_P0, TRAJ_MIN_POINTS
                )
                writer.write(apply_out_rotate(out_vis, OUT_ROTATE_MODE))
            continue

        if (TRACK_FRAMES is not None) and (TRACK_FRAMES > 0) and (frame_idx > TRACK_FRAMES):
            print("Reached TRACK_FRAMES")
            break

        # Stop trajectory computation but keep exporting preview/output frames.
        if state == STATE_TRACK_STOPPED:
            if writer is not None:
                out_vis = draw_traj_overlay_only(
                    frame.copy(),
                    track_pts,
                    pn=DRAW_TRAJ_UNTIL_PN,
                    color_bgr=TRAJ_COLOR_BGR,
                    alpha=TRAJ_ALPHA,
                    thickness=TRAJ_THICKNESS,
                    draw_from_p0=TRAJ_DRAW_FROM_P0,
                    min_points=TRAJ_MIN_POINTS,
                )
                writer.write(apply_out_rotate(out_vis, OUT_ROTATE_MODE))

            if SHOW_MAIN:
                cv2.imshow("Tracking (preview)", frame)
                k = cv2.waitKey(30) & 0xFF
                if k == ESC_KEY:
                    break

            prev_gray = gray
            continue

        this_blue_xy: Optional[np.ndarray] = None

        # ROI behavior requested: fixed size, center lock to latest valid point in tracking.
        # Recovery: when misses occur, temporarily expand ROI and use Kalman-predicted center.
        if state in (STATE_WAIT_P0, STATE_WAIT_P1):
            cx, cy = roi_center
            roi_size = ROI_FIXED_SIZE
        else:
            if kf.initialized:
                # Predict first so current frame uses freshest expected location.
                kf.predict()
                this_blue_xy = np.array(kf.pos(), dtype=np.float32)
                blue_hist.append(this_blue_xy.copy())

            use_pred_center = (
                RECOVERY_USE_KALMAN_CENTER_ON_MISS
                and no_cand_count > 0
                and this_blue_xy is not None
            )

            if use_pred_center:
                cx, cy = int(round(this_blue_xy[0])), int(round(this_blue_xy[1]))
            elif ROI_CENTER_LOCK_TO_LAST and len(track_pts) > 0:
                cx, cy = track_pts[-1]
            else:
                target = np.array(kf.pos(), dtype=np.float32)
                if roi_center_smooth is None:
                    roi_center_smooth = target.copy()
                target_limited = clamp_step(roi_center_smooth, target, ROI_CFG["max_center_step"])
                a = ROI_CFG["center_alpha"]
                roi_center_smooth = (1 - a) * roi_center_smooth + a * target_limited
                cx, cy = int(round(roi_center_smooth[0])), int(round(roi_center_smooth[1]))
            roi_size = min(
                RECOVERY_ROI_MAX,
                int(ROI_FIXED_SIZE + no_cand_count * RECOVERY_ROI_GROW_PER_MISS),
            )

        p_index = max(len(track_pts) - 1, 0)
        active_cfg = get_dynamic_detect_cfg(p_index, roi_size) if state == STATE_TRACKING else dict(DETECT_CFG_BASE)
        if state == STATE_TRACKING:
            active_cfg = get_far_adaptive_cfg(active_cfg, no_cand_count, area_ema)

        half = roi_size // 2
        x1, y1 = max(cx - half, 0), max(cy - half, 0)
        x2, y2 = min(cx + half, frame.shape[1] - 1), min(cy + half, frame.shape[0] - 1)
        if x2 <= x1 or y2 <= y1:
            prev_gray = gray
            continue

        roi_g = gray[y1:y2, x1:x2]
        prev_roi_g = prev_gray[y1:y2, x1:x2]

        if SHOW_DEBUG_ROI:
            cv2.imshow("DEBUG_ROI", roi_g)
            cv2.waitKey(1)

        cand_stats_roi = detect_candidates_with_stats(roi_g, prev_roi_g, active_cfg)
        cand_stats_glb: List[Dict[str, Any]] = []
        for c in cand_stats_roi:
            gx = x1 + c["pt_roi"][0]
            gy = y1 + c["pt_roi"][1]
            cand_stats_glb.append({"pt": (gx, gy), "area": c["area"], "circ": c["circ"], "diff": c["diff"]})

        if state == STATE_WAIT_P0:
            wait_frames += 1
            if cand_stats_glb:
                rc = np.array(roi_center, dtype=np.float32)
                best = min(cand_stats_glb, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - rc))
                p0 = best["pt"]
                track_pts = [p0]
                state = STATE_WAIT_P1
                wait_frames = 0
                p0_frame_idx = frame_idx
                print(f"Captured p0={p0}")
            elif wait_frames >= WAIT_MAX_FRAMES:
                print("Timeout waiting p0")

        elif state == STATE_WAIT_P1:
            wait_frames += 1

            if P1_MUST_APPEAR_NEXT_FRAME and (p0_frame_idx is not None):
                if frame_idx - p0_frame_idx > P1_DEADLINE_FRAMES:
                    print(f"Reset false p0={track_pts[0]}")
                    track_pts = []
                    state = STATE_WAIT_P0
                    wait_frames = 0
                    p0_frame_idx = None
                    prev_gray = gray
                    continue

            if cand_stats_glb:
                p0 = track_pts[0]
                if USE_LEFT_RULE:
                    valid = [c for c in cand_stats_glb if c["pt"][0] < p0[0] - MIN_DX]
                else:
                    valid = list(cand_stats_glb)

                if valid:
                    p0v = np.array(p0, dtype=np.float32)
                    best = min(valid, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - p0v))
                    p1 = best["pt"]
                    track_pts.append(p1)

                    kf.initialize_from_two_points(p0, p1)
                    p0_frame_idx = None
                    state = STATE_TRACKING
                    roi_center_smooth = np.array(p1, dtype=np.float32)

                    step_mode_active = bool(STEP_MODE_AFTER_P1)
                    blue_hist.clear()
                    no_cand_count = 0
                    step_ema = None
                    outlier_strikes = 0
                    print("Enter TRACKING")

            elif wait_frames >= WAIT_MAX_FRAMES:
                print("Timeout waiting p1")

        elif state == STATE_TRACKING:
            if this_blue_xy is None:
                this_blue_xy = np.array(kf.pos(), dtype=np.float32)
                blue_hist.append(this_blue_xy.copy())

            if not cand_stats_glb:
                no_cand_count += 1
                if STOP_WHEN_NO_CAND_IN_TRACK and no_cand_count > NO_CAND_PATIENCE:
                    print(f"Tracking stopped: no candidates in diff ({no_cand_count} frames)")
                    state = STATE_TRACK_STOPPED
                    no_cand_count = 0
            else:
                no_cand_count = 0
                if len(cand_stats_glb) >= FAR_MANY_CANDS_STOP:
                    print(f"Tracking stopped: too many candidates ({len(cand_stats_glb)}) -> likely background")
                    state = STATE_TRACK_STOPPED
                    continue
                too_many = (len(cand_stats_glb) >= TOO_MANY_CANDS_THRESHOLD)
                appended = False

                if too_many and TOO_MANY_CANDS_USE_BLUE_AS_P:
                    chosen_blue = pick_blue_from_history(blue_hist, BLUE_P_OFFSET)
                    if chosen_blue is not None:
                        ok = True
                        if BLUE_TO_LASTP_MAX_DIST is not None and track_pts:
                            last = np.array(track_pts[-1], dtype=np.float32)
                            d = float(np.linalg.norm(chosen_blue - last))
                            if d > float(BLUE_TO_LASTP_MAX_DIST):
                                ok = False
                        if ok:
                            p_from_blue = (int(round(chosen_blue[0])), int(round(chosen_blue[1])))
                            track_pts.append(p_from_blue)
                            appended = True

                if (not appended) and cand_stats_glb:
                    last_pt = track_pts[-1]
                    if USE_LEFT_RULE:
                        pool = [c for c in cand_stats_glb if c["pt"][0] < last_pt[0] - MIN_DX]
                    else:
                        pool = list(cand_stats_glb)

                    if pool and USE_Y_DIRECTION and (y_dir is not None) and (no_cand_count == 0):
                        if y_dir < 0:
                            pool_y = [c for c in pool if c["pt"][1] <= last_pt[1] + Y_TOL]
                        else:
                            pool_y = [c for c in pool if c["pt"][1] >= last_pt[1] - Y_TOL]
                        pool_y = [c for c in pool_y if abs(c["pt"][1] - last_pt[1]) <= Y_MAX_STEP]
                        if pool_y:
                            pool = pool_y
                        elif STRICT_Y_DIRECTION:
                            pool = []

                    if pool:
                        pred = this_blue_xy
                        # If only a few candidates appear after misses, trust distance-to-prediction.
                        if len(pool) <= FAR_FEW_CANDS_MAX:
                            best = min(pool, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - pred))
                        else:
                            # For medium candidate counts, prefer higher diff while staying near prediction.
                            best = min(
                                pool,
                                key=lambda c: (
                                    np.linalg.norm(np.array(c["pt"], dtype=np.float32) - pred)
                                    - 0.15 * float(c.get("diff", 0.0))
                                ),
                            )
                        z = best["pt"]

                        # requested: reject sudden large jumps in distance
                        accept = True
                        if USE_STEP_DIST_GUARD and track_pts:
                            step = float(np.linalg.norm(np.array(z, dtype=np.float32) - np.array(track_pts[-1], dtype=np.float32)))
                            base_lim = STEP_ABS_MAX if step_ema is None else max(STEP_ABS_MAX, step_ema * STEP_GROWTH_FACTOR)
                            lim = base_lim * (1.0 + 0.35 * float(no_cand_count))
                            pred_dist = float(np.linalg.norm(np.array(z, dtype=np.float32) - pred))
                            hard_lim = min(STEP_ABS_HARD_MAX, lim)
                            if (step > hard_lim) or (pred_dist > PRED_DIST_HARD_MAX):
                                accept = False
                            else:
                                if step_ema is None:
                                    step_ema = step
                                else:
                                    step_ema = (1.0 - STEP_EMA_ALPHA) * step_ema + STEP_EMA_ALPHA * step

                        if accept:
                            outlier_strikes = 0
                            kf.update(z)
                            track_pts.append((int(z[0]), int(z[1])))
                            area_now = float(best.get("area", 0.0))
                            if area_now > 0:
                                if area_ema is None:
                                    area_ema = area_now
                                else:
                                    area_ema = (1.0 - FAR_AREA_EMA_ALPHA) * area_ema + FAR_AREA_EMA_ALPHA * area_now
                            if USE_Y_DIRECTION and y_dir is None and len(track_pts) >= 3:
                                p0_, p1_, p2_ = track_pts[0], track_pts[1], track_pts[2]
                                dy = (p2_[1] - p0_[1])
                                if abs(dy) >= 2:
                                    y_dir = 1 if dy > 0 else -1
                        else:
                            # Skip outlier point this frame; keep trying on next frames.
                            outlier_strikes += 1
                            if outlier_strikes >= OUTLIER_STRIKES_TO_FREEZE and len(track_pts) >= 8:
                                print(f"Tracking frozen: persistent outlier jumps ({outlier_strikes})")
                                state = STATE_TRACK_STOPPED
        else:
            pass

        if writer is not None:
            out_vis = draw_traj_overlay_only(
                frame.copy(),
                track_pts,
                pn=DRAW_TRAJ_UNTIL_PN,
                color_bgr=TRAJ_COLOR_BGR,
                alpha=TRAJ_ALPHA,
                thickness=TRAJ_THICKNESS,
                draw_from_p0=TRAJ_DRAW_FROM_P0,
                min_points=TRAJ_MIN_POINTS,
            )
            writer.write(apply_out_rotate(out_vis, OUT_ROTATE_MODE))

        if SHOW_MAIN:
            cv2.imshow("Tracking (preview)", frame)
            if step_mode_active and state == STATE_TRACKING:
                while True:
                    k = cv2.waitKey(0) & 0xFF
                    if k in ENTER_KEYS or k == ESC_KEY:
                        break
                if k == ESC_KEY:
                    break
            else:
                k = cv2.waitKey(30) & 0xFF
                if k == ESC_KEY:
                    break

        prev_gray = gray

    cap.release()
    if writer is not None:
        writer.release()

    if SHOW_MAIN or SHOW_DEBUG_ROI:
        cv2.destroyAllWindows()

    if EXPORT_VIDEO and out_path and Path(out_path).exists():
        print("Done:", out_path)
        return out_path

    print("Done (no export)")
    return None


def main():
    global SHOW_MAIN, SHOW_DEBUG_ROI

    if BATCH_MODE and AUTO_DISABLE_UI_IN_BATCH:
        SHOW_MAIN = False
        SHOW_DEBUG_ROI = False
        DETECT_CFG_BASE["show_debug"] = False

    if BATCH_MODE:
        in_dir = Path(INPUT_DIR)
        if not in_dir.exists():
            print("INPUT_DIR not found:", INPUT_DIR)
            return

        vids = sorted([p for p in in_dir.glob("*.mp4")])
        print(f"Batch mode: {INPUT_DIR}, {len(vids)} videos")
        if len(vids) == 0:
            return

        out_dir = BATCH_OUTPUT_DIR
        if out_dir is not None:
            Path(out_dir).mkdir(parents=True, exist_ok=True)

        for vp in vids:
            process_one_video(str(vp), out_dir=out_dir)
    else:
        process_one_video(VIDEO_PATH, out_dir=None)


if __name__ == "__main__":
    main()

