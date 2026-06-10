import cv2
import numpy as np
from dataclasses import dataclass
from typing import Tuple, List, Optional, Dict, Any
from pathlib import Path
from datetime import datetime

# ============================================================
# ✅ 新增：批量處理 / 固定 ROI 中心模式
# ============================================================
BATCH_MODE = False  # ✅ 是否啟用批量模式

# 批量輸入資料夾（會掃描 *.mp4）
INPUT_DIR = r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\phase"

# 批量輸出資料夾（None=輸出到影片同資料夾；建議設一個子資料夾）
BATCH_OUTPUT_DIR = r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\phase\traj_out"

# 單支影片模式用
VIDEO_PATH = r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\phase\clip_stabilized_pose_phase.mp4"

# ✅ 固定 ROI center 模式（新增）
FIXED_ROI_MODE = True
FIXED_ROI_CENTER = (742, 255)

# 批量時建議關 UI（避免視窗爆炸）
AUTO_DISABLE_UI_IN_BATCH = True

# ============================================================
# 使用者設定
# ============================================================
TRACK_FRAMES = 300

# ============================================================
# ✅ 影像翻轉/倒置（演算法座標系）
# ============================================================
FLIP_MODE = 5
# 0 = 不處理
# 1 = 上下顛倒
# 2 = 左右鏡像
# 3 = 上下+左右
# 4 = 旋轉 90° 順時針
# 5 = 旋轉 90° 逆時針
# 6 = 旋轉 180°

# ============================================================
# ✅ 輸出影片設定（只畫軌跡線）
# ============================================================
EXPORT_VIDEO = True
OUT_VIDEO_PATH = None  # None=自動命名（批量時會自動用 stem 命名）

# ✅ 輸出旋轉（只影響輸出影片，不影響演算法追蹤）
OUT_ROTATE_MODE = 4
# 0 = 不旋轉
# 4 = 旋轉 90° 順時針（向右轉90度）
# 5 = 旋轉 90° 逆時針
# 6 = 旋轉 180°

# ✅ 只畫到 pn（含）；None=全部
DRAW_TRAJ_UNTIL_PN = 6

# ✅ 軌跡樣式
TRAJ_COLOR_BGR = (255, 220, 160)  # 淡藍 (BGR)
TRAJ_ALPHA = 0.8
TRAJ_THICKNESS = 6
TRAJ_DRAW_FROM_P0 = True
TRAJ_MIN_POINTS = 2

# ============================================================
# ✅ p0 驗證規則：p0 出現後，下一幀必須出現 p1，否則 p0 當誤判
# ============================================================
P1_MUST_APPEAR_NEXT_FRAME = True
P1_DEADLINE_FRAMES = 1

# ============================================================
# ✅ 逐幀人工步進模式：抓到 p1 後，每一幀都停住，按 Enter 才繼續
# ============================================================
STEP_MODE_AFTER_P1 = False
ENTER_KEYS = {13, 10}
ESC_KEY = 27

# ============================================================
# ✅ 候選點太多時：改用「藍點預測」當作新的 p
# ============================================================
TOO_MANY_CANDS_USE_BLUE_AS_P = True
TOO_MANY_CANDS_THRESHOLD = 4
BLUE_P_OFFSET = -2
BLUE_TO_LASTP_MAX_DIST: Optional[float] = 150.0

# ============================================================
# 顯示（UI）開關：輸出影片不會使用這些疊圖
# ============================================================
SHOW_MAIN = True
SHOW_DEBUG_ROI = True

DETECT_CFG_BASE = dict(
    area_range=(4, 150),
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
    size_init=200,
    size_min=80,
    shrink_over_frames=60,
    center_alpha=0.4,
    max_center_step=80,
)

CFG_SPEED = 0.6
DIFF_MIN = 9
CIRC_MIN = 0.60
AREA_LO_MIN = 6

USE_Y_DIRECTION = True
Y_TOL = 1
Y_MAX_STEP = 80

# ============================================================
# 方案 B：滑鼠點擊（只決定 ROI 固定中心）
# ============================================================
clicked_point: Optional[Tuple[int, int]] = None

def on_mouse(event, x, y, flags, param):
    global clicked_point
    if event == cv2.EVENT_LBUTTONDOWN:
        clicked_point = (x, y)

# ============================================================
# 前處理 / 影像旋轉
# ============================================================
def apply_flip(frame: np.ndarray, mode: int) -> np.ndarray:
    if mode == 0:
        return frame
    elif mode == 1:
        return cv2.flip(frame, 0)
    elif mode == 2:
        return cv2.flip(frame, 1)
    elif mode == 3:
        return cv2.flip(frame, -1)
    elif mode == 4:
        return cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
    elif mode == 5:
        return cv2.rotate(frame, cv2.ROTATE_90_COUNTERCLOCKWISE)
    elif mode == 6:
        return cv2.rotate(frame, cv2.ROTATE_180)
    else:
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

# ============================================================
# ROI 工具
# ============================================================
def clamp_step(cur: np.ndarray, target: np.ndarray, max_step: float) -> np.ndarray:
    d = target - cur
    dist = float(np.linalg.norm(d))
    if dist <= max_step or dist < 1e-6:
        return target
    return cur + d * (max_step / dist)

def roi_size_schedule(size_init: int, size_min: int, t: int, T: int) -> int:
    if T <= 1:
        return size_min
    u = min(max(t / float(T), 0.0), 1.0)
    u2 = 1.0 - (1.0 - u) ** 2
    s = size_init + (size_min - size_init) * u2
    return int(round(s))

# ============================================================
# 動態 DETECT_CFG
# ============================================================
def get_dynamic_detect_cfg(p_index: int, roi_size: int) -> Dict[str, Any]:
    cfg = dict(DETECT_CFG_BASE)
    s = float(roi_size) / float(ROI_CFG["size_init"])
    s = float(np.clip(s, 0.20, 1.0))

    t = max(p_index - 1, 0)
    tt = CFG_SPEED * t
    relax = 1.0 / (1.0 + 0.45 * tt)

    base_lo, base_hi = DETECT_CFG_BASE["area_range"]

    lo = int(round(base_lo * (s**2) * relax))
    lo = max(AREA_LO_MIN, min(lo, base_lo))

    hi = int(round(base_hi * (s**2) * (0.80 + 0.20 * relax)))
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

# ============================================================
# 候選點偵測
# ============================================================
def detect_candidates_with_stats(cur_gray: np.ndarray, prev_gray: np.ndarray, cfg: Dict[str, Any]) -> List[Dict[str, Any]]:
    if cur_gray is None or prev_gray is None:
        return []
    if cur_gray.size == 0 or prev_gray.size == 0:
        return []
    if cur_gray.shape != prev_gray.shape:
        return []

    area_range  = cfg["area_range"]
    circ_thresh = cfg["circ_thresh"]
    diff_thresh = cfg["diff_thresh"]
    show_debug  = cfg.get("show_debug", False)
    prefix      = cfg.get("debug_prefix", "DEBUG")

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

# ============================================================
# Kalman Filter
# ============================================================
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
        self.A = np.array([[1,0,dt,0],[0,1,0,dt],[0,0,1,0],[0,0,0,1]], np.float32)
        self.H = np.array([[1,0,0,0],[0,1,0,0]], np.float32)
        self.Q = np.diag([self.p.process_pos_var]*2 + [self.p.process_vel_var]*2).astype(np.float32)
        self.R = np.diag([self.p.meas_var]*2).astype(np.float32)

    def initialize_from_two_points(self, p0: Tuple[int, int], p1: Tuple[int, int]):
        dt = max(self.p.dt, 1e-6)
        vx = (p1[0] - p0[0]) / dt
        vy = (p1[1] - p0[1]) / dt
        self.x[:, 0] = np.array([p1[0], p1[1], vx, vy], dtype=np.float32)
        self.P = np.diag([80, 80, 900, 900]).astype(np.float32)
        self.initialized = True
        print(f"🎯 Kalman 初始化：p0={p0}, p1={p1}, v=({vx:.1f},{vy:.1f})")

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

# ============================================================
# 工具：取藍點歷史
# ============================================================
def pick_blue_from_history(blue_hist: List[np.ndarray], offset: int) -> Optional[np.ndarray]:
    if not blue_hist:
        return None
    if offset > 0:
        offset = 0
    idx = -1 + offset
    if abs(idx) > len(blue_hist):
        return None
    return blue_hist[idx]

# ============================================================
# ✅ 輸出路徑（批量支援 out_dir）
# ============================================================
def make_out_path(video_path: str, out_dir: Optional[str]) -> str:
    p = Path(video_path)
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_name = f"{p.stem}_traj_{ts}.mp4"
    if out_dir is None:
        return str(p.with_name(out_name))
    od = Path(out_dir)
    od.mkdir(parents=True, exist_ok=True)
    return str(od / out_name)

# ============================================================
# ✅ 軌跡疊圖（只畫線 + alpha；不畫點）
# ============================================================
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

# ============================================================
# 主程式（狀態機）
# ============================================================
STATE_WAIT_P0 = 0
STATE_WAIT_P1 = 1
STATE_TRACKING = 2

def process_one_video(video_path: str, out_dir: Optional[str]) -> Optional[str]:
    global clicked_point

    print("\n" + "="*90)
    print("▶ 處理影片：", video_path)

    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        print("❌ 無法開啟影片：", video_path)
        return None

    fps = cap.get(cv2.CAP_PROP_FPS)
    dt = 1.0 / max(fps, 1.0)
    print(f"✅ FPS={fps:.3f}, dt={dt:.4f}")

    # 每支影片都要重置
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
    track_t = 0

    y_dir: Optional[int] = None
    step_mode_active = False
    blue_hist: List[np.ndarray] = []

    writer = None
    out_path = OUT_VIDEO_PATH

    # 若是固定 ROI 模式：直接設定（但要等讀到第一幀知道影像大小也行；這裡先照你要求固定值）
    if FIXED_ROI_MODE:
        roi_center = tuple(map(int, FIXED_ROI_CENTER))
        print("✅ FIXED_ROI_MODE: ROI center =", roi_center)

    while True:
        ret, frame0 = cap.read()
        if not ret:
            break
        frame_idx += 1

        # === 演算法用 frame（可用 FLIP_MODE）===
        frame = apply_flip(frame0, FLIP_MODE)
        raw_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = preprocess_gray(raw_gray)

        # 初始化：第一幀決定 ROI center（非固定模式才需要點擊）
        if frame_idx == 1:
            if (roi_center is None) and (not FIXED_ROI_MODE):
                temp = frame.copy()
                cv2.namedWindow("FIRST_FRAME_CLICK", cv2.WINDOW_NORMAL)
                cv2.setMouseCallback("FIRST_FRAME_CLICK", on_mouse)
                print("🖱 點擊 ROI 中心（球將飛過的區域），按任意鍵確認")
                while True:
                    vis0 = temp.copy()
                    if clicked_point is not None:
                        cv2.circle(vis0, clicked_point, 6, (0, 0, 255), -1)
                    cv2.imshow("FIRST_FRAME_CLICK", vis0)
                    if cv2.waitKey(20) != -1:
                        break
                cv2.destroyWindow("FIRST_FRAME_CLICK")
                roi_center = clicked_point if clicked_point else (gray.shape[1] // 2, gray.shape[0] // 2)
                print("✅ ROI center =", roi_center)

            # ✅ 初始化 writer：用「輸出旋轉後」的尺寸
            if EXPORT_VIDEO and writer is None:
                if out_path is None:
                    out_path = make_out_path(video_path, out_dir)

                probe = apply_out_rotate(frame.copy(), OUT_ROTATE_MODE)
                oh, ow = probe.shape[:2]
                fourcc = cv2.VideoWriter_fourcc(*"mp4v")
                writer = cv2.VideoWriter(out_path, fourcc, float(max(fps, 1.0)), (ow, oh))
                if not writer.isOpened():
                    print("❌ VideoWriter 開啟失敗，將不輸出影片：", out_path)
                    writer = None
                else:
                    print("💾 輸出影片：", out_path)
                    print(f"   ↳ OUT_ROTATE_MODE={OUT_ROTATE_MODE}, out_size=({ow},{oh})")

        if prev_gray is None:
            prev_gray = gray
            if writer is not None:
                out_vis = frame.copy()
                out_vis = draw_traj_overlay_only(
                    out_vis, track_pts, DRAW_TRAJ_UNTIL_PN,
                    TRAJ_COLOR_BGR, TRAJ_ALPHA, TRAJ_THICKNESS,
                    TRAJ_DRAW_FROM_P0, TRAJ_MIN_POINTS
                )
                out_vis = apply_out_rotate(out_vis, OUT_ROTATE_MODE)
                writer.write(out_vis)
            continue

        if frame_idx > TRACK_FRAMES:
            print("✅ 到達 TRACK_FRAMES")
            break

        # ROI center + size
        if state in (STATE_WAIT_P0, STATE_WAIT_P1):
            cx, cy = roi_center
            roi_size = ROI_CFG["size_init"]
        else:
            target = np.array(kf.pos(), dtype=np.float32)
            if roi_center_smooth is None:
                roi_center_smooth = target.copy()
            target_limited = clamp_step(roi_center_smooth, target, ROI_CFG["max_center_step"])
            a = ROI_CFG["center_alpha"]
            roi_center_smooth = (1 - a) * roi_center_smooth + a * target_limited
            cx, cy = int(round(roi_center_smooth[0])), int(round(roi_center_smooth[1]))
            roi_size = roi_size_schedule(ROI_CFG["size_init"], ROI_CFG["size_min"], track_t, ROI_CFG["shrink_over_frames"])

        p_index = max(len(track_pts) - 1, 0)
        active_cfg = get_dynamic_detect_cfg(p_index, roi_size) if state == STATE_TRACKING else dict(DETECT_CFG_BASE)

        half = roi_size // 2
        x1, y1 = max(cx - half, 0), max(cy - half, 0)
        x2, y2 = min(cx + half, frame.shape[1] - 1), min(cy + half, frame.shape[0] - 1)
        if x2 <= x1 or y2 <= y1:
            prev_gray = gray
            if writer is not None:
                out_vis = frame.copy()
                out_vis = draw_traj_overlay_only(
                    out_vis, track_pts, DRAW_TRAJ_UNTIL_PN,
                    TRAJ_COLOR_BGR, TRAJ_ALPHA, TRAJ_THICKNESS,
                    TRAJ_DRAW_FROM_P0, TRAJ_MIN_POINTS
                )
                out_vis = apply_out_rotate(out_vis, OUT_ROTATE_MODE)
                writer.write(out_vis)
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

        # --------------------------------------------------------
        # 狀態機
        # --------------------------------------------------------
        STRICT_Y_DIRECTION = True

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
                print(f"✅ 捕捉到 p0={p0}（等待 p1 左側，deadline={P1_DEADLINE_FRAMES}f）")
            elif wait_frames >= WAIT_MAX_FRAMES:
                print("⚠️ 超時：等不到 p0")

        elif state == STATE_WAIT_P1:
            wait_frames += 1

            if P1_MUST_APPEAR_NEXT_FRAME and (p0_frame_idx is not None):
                if frame_idx - p0_frame_idx > P1_DEADLINE_FRAMES:
                    print(f"🧹 p0 誤判：p0={track_pts[0]}，{P1_DEADLINE_FRAMES} 幀內無 p1 -> reset")
                    track_pts = []
                    state = STATE_WAIT_P0
                    wait_frames = 0
                    p0_frame_idx = None
                    prev_gray = gray
                    continue

            if cand_stats_glb:
                p0 = track_pts[0]
                valid = [c for c in cand_stats_glb if c["pt"][0] < p0[0] - MIN_DX]
                if valid:
                    p0v = np.array(p0, dtype=np.float32)
                    best = min(valid, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - p0v))
                    p1 = best["pt"]
                    track_pts.append(p1)

                    kf.initialize_from_two_points(p0, p1)
                    p0_frame_idx = None
                    state = STATE_TRACKING
                    track_t = 0
                    roi_center_smooth = np.array(p1, dtype=np.float32)

                    step_mode_active = bool(STEP_MODE_AFTER_P1)
                    blue_hist.clear()
                    print("✅ 進入 TRACKING")
                    if step_mode_active:
                        print("⏸ STEP MODE：每幀按 Enter 才會前進（ESC 退出）")

            elif wait_frames >= WAIT_MAX_FRAMES:
                print("⚠️ 超時：抓不到 p1")

        else:  # TRACKING
            track_t += 1

            # predict（藍點）
            kf.predict()
            this_blue_xy = np.array(kf.pos(), dtype=np.float32)
            blue_hist.append(this_blue_xy.copy())

            too_many = (len(cand_stats_glb) >= TOO_MANY_CANDS_THRESHOLD)

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

            else:
                if cand_stats_glb:
                    last_pt = track_pts[-1]
                    pool_left = [c for c in cand_stats_glb if c["pt"][0] < last_pt[0] - MIN_DX]
                    pool = pool_left

                    if pool:
                        if USE_Y_DIRECTION and (y_dir is not None):
                            if y_dir < 0:
                                pool_y = [c for c in pool if c["pt"][1] <= last_pt[1] + Y_TOL]
                            else:
                                pool_y = [c for c in pool if c["pt"][1] >= last_pt[1] - Y_TOL]
                            pool_y = [c for c in pool_y if abs(c["pt"][1] - last_pt[1]) <= Y_MAX_STEP]

                            if pool_y:
                                pool = pool_y
                            else:
                                pool = [] if STRICT_Y_DIRECTION else pool_left 

                        if pool:
                            pred = this_blue_xy
                            best = min(pool, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - pred))
                            z = best["pt"]
                            kf.update(z)
                            track_pts.append((int(z[0]), int(z[1])))

                            if USE_Y_DIRECTION and y_dir is None and len(track_pts) >= 3:
                                p0_, p1_, p2_ = track_pts[0], track_pts[1], track_pts[2]
                                dy = (p2_[1] - p0_[1])
                                if abs(dy) >= 2:
                                    y_dir = 1 if dy > 0 else -1
                                print(f"📌 y_dir set = {y_dir} (dy={dy})")

        # --------------------------------------------------------
        # ✅ 輸出影片：只畫軌跡
        # --------------------------------------------------------
        if writer is not None:
            out_vis = frame.copy()
            out_vis = draw_traj_overlay_only(
                out_vis,
                track_pts,
                pn=DRAW_TRAJ_UNTIL_PN,
                color_bgr=TRAJ_COLOR_BGR,
                alpha=TRAJ_ALPHA,
                thickness=TRAJ_THICKNESS,
                draw_from_p0=TRAJ_DRAW_FROM_P0,
                min_points=TRAJ_MIN_POINTS,
            )
            out_vis = apply_out_rotate(out_vis, OUT_ROTATE_MODE)
            writer.write(out_vis)

        # --------------------------------------------------------
        # UI 顯示
        # --------------------------------------------------------
        if SHOW_MAIN:
            cv2.imshow("Tracking (preview)", frame)
            if step_mode_active and state == STATE_TRACKING:
                while True:
                    k = cv2.waitKey(0) & 0xFF
                    if k in ENTER_KEYS:
                        break
                    if k == ESC_KEY:
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
        print("✅ 完成輸出：", out_path)
        return out_path

    print("✅ 結束（未輸出）")
    return None

def main():
    global SHOW_MAIN, SHOW_DEBUG_ROI

    # 批量時自動關 UI（你也可以自己手動設 False）
    if BATCH_MODE and AUTO_DISABLE_UI_IN_BATCH:
        SHOW_MAIN = False
        SHOW_DEBUG_ROI = False
        DETECT_CFG_BASE["show_debug"] = False

    if BATCH_MODE:
        in_dir = Path(INPUT_DIR)
        if not in_dir.exists():
            print("❌ INPUT_DIR 不存在：", INPUT_DIR)
            return

        vids = sorted([p for p in in_dir.glob("*.mp4")])
        print(f"📂 批量模式：{INPUT_DIR}")
        print(f"🔍 找到 {len(vids)} 支 mp4")
        if len(vids) == 0:
            return

        out_dir = BATCH_OUTPUT_DIR
        if out_dir is not None:
            Path(out_dir).mkdir(parents=True, exist_ok=True)
            print(f"💾 批量輸出到：{out_dir}")

        for vp in vids:
            # 每支影片都用同一套參數處理
            process_one_video(str(vp), out_dir=out_dir)
    else:
        process_one_video(VIDEO_PATH, out_dir=None)

if __name__ == "__main__":
    main()
