"""
Golf ball trajectory tracking and analysis system.
Complete rewrite from ball_tracking_no_cnn_stable_21.py with full functionality.
Includes Kalman filter, state machine, blue point history, Y direction tracking.
"""

import cv2
import numpy as np
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import List, Dict, Tuple, Optional, Any
import warnings
from datetime import datetime
import os


# ============================================================
# Configuration & Enums
# ============================================================

class FlipMode(Enum):
    """Image flip/rotation modes for algorithm coordinate system"""
    NO_FLIP = 0
    FLIP_VERTICAL = 1
    FLIP_HORIZONTAL = 2
    FLIP_BOTH = 3
    ROTATE_90_CW = 4
    ROTATE_90_CCW = 5
    ROTATE_180 = 6


class ProcessingMode(Enum):
    """Processing mode: single video or batch"""
    SINGLE_VIDEO = "single"
    BATCH_MODE = "batch"


@dataclass
class BallTrackingConfig:
    """Configuration for ball tracking system"""
    
    # Video processing
    track_frames: int = 300
    batch_mode: bool = True
    input_dir: str = r"\\10.1.1.101\ORVIA\videos\..."
    output_dir: Optional[str] = None
    video_path: str = ""
    
    # ROI settings
    fixed_roi_mode: bool = True
    fixed_roi_center: Tuple[int, int] = (742, 255)
    roi_cfg: Dict[str, Any] = field(default_factory=lambda: {
        "size_init": 200,
        "size_min": 80,
        "shrink_over_frames": 60,
        "center_alpha": 0.4,
        "max_center_step": 80,
    })
    
    # Image processing
    flip_mode: int = 5  # ROTATE_90_CCW
    out_rotate_mode: int = 4
    
    # Detection parameters
    detect_cfg_base: Dict[str, Any] = field(default_factory=lambda: {
        "area_range": (4, 150),
        "circ_thresh": 0.60,
        "diff_thresh": 16,
        "show_debug": True,  # 匹配原版
    })
    
    # Output settings
    export_video: bool = True
    out_video_path: Optional[str] = None
    draw_traj_until_pn: Optional[int] = 6  # None=畫全部軌跡（原版=6只畫前6點）
    traj_color_bgr: Tuple[int, int, int] = (255, 220, 160)
    traj_alpha: float = 0.8
    traj_thickness: int = 6
    traj_draw_from_p0: bool = True
    traj_min_points: int = 2
    
    # UI settings
    show_main: bool = True
    show_debug_roi: bool = True
    
    # Tracking parameters
    min_dx: int = 3
    wait_max_frames: int = 180
    p1_must_appear_next: bool = True
    p1_deadline_frames: int = 1
    step_mode_after_p1: bool = False
    enter_keys: set = field(default_factory=lambda: {13, 10})
    esc_key: int = 27
    
    # Blue point settings
    too_many_cands_use_blue: bool = True
    too_many_cands_threshold: int = 4
    blue_p_offset: int = -2
    blue_to_lastp_max_dist: Optional[float] = 150.0
    
    # Y direction tracking
    use_y_direction: bool = True
    y_tol: int = 1
    y_max_step: int = 80
    
    # Other
    auto_disable_ui_in_batch: bool = True
    
    def __post_init__(self):
        """Validate configuration"""
        if self.traj_alpha < 0 or self.traj_alpha > 1:
            raise ValueError("traj_alpha must be between 0 and 1")
        if self.track_frames < 1:
            raise ValueError("track_frames must be positive")


# ============================================================
# Kalman Filter
# ============================================================

@dataclass
class KFParams:
    """Kalman Filter parameters"""
    dt: float = 0.033
    process_pos_var: float = 3.0      # 匹配原版
    process_vel_var: float = 120.0    # 匹配原版
    meas_var: float = 10.0            # 匹配原版


class KalmanFilter2D:
    """2D Kalman Filter for ball position tracking"""
    
    def __init__(self, p: KFParams):
        self.p = p
        self.x = np.zeros((4, 1), dtype=np.float32)  # [x, y, vx, vy]
        self.P = np.eye(4, dtype=np.float32) * 1000
        self.initialized = False
        self.I = np.eye(4, dtype=np.float32)
        self._build()
    
    def _build(self):
        """Build matrices"""
        dt = self.p.dt
        self.A = np.array([[1, 0, dt, 0], [0, 1, 0, dt], [0, 0, 1, 0], [0, 0, 0, 1]], dtype=np.float32)
        self.H = np.array([[1, 0, 0, 0], [0, 1, 0, 0]], dtype=np.float32)
        self.Q = np.diag([self.p.process_pos_var]*2 + [self.p.process_vel_var]*2).astype(np.float32)
        self.R = np.diag([self.p.meas_var]*2).astype(np.float32)
    
    def initialize_from_two_points(self, p0: Tuple[int, int], p1: Tuple[int, int]):
        """Initialize from two points"""
        dt = max(self.p.dt, 1e-6)
        vx = (p1[0] - p0[0]) / dt
        vy = (p1[1] - p0[1]) / dt
        self.x[:, 0] = np.array([p1[0], p1[1], vx, vy], dtype=np.float32)
        self.P = np.diag([80, 80, 900, 900]).astype(np.float32)
        self.initialized = True
        print(f"🎯 Kalman initialized: p0={p0}, p1={p1}, v=({vx:.1f},{vy:.1f})")
    
    def predict(self):
        """Predict next state"""
        self.x = self.A @ self.x
        self.P = self.A @ self.P @ self.A.T + self.Q
    
    def update(self, z_xy: Tuple[int, int]):
        """Update with measurement"""
        z = np.array(z_xy, dtype=np.float32).reshape(2, 1)
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
        """Get current position"""
        return float(self.x[0, 0]), float(self.x[1, 0])


# ============================================================
# Image Processing
# ============================================================

class ImageProcessor:
    """Static image processing utilities"""
    
    @staticmethod
    def apply_flip(frame: np.ndarray, mode: int) -> np.ndarray:
        """Apply flip/rotation based on mode"""
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
        return frame
    
    @staticmethod
    def preprocess_gray(raw_gray: np.ndarray) -> np.ndarray:
        """Preprocess grayscale image"""
        blurred = cv2.medianBlur(raw_gray, 3)
        smoothed = cv2.bilateralFilter(blurred, d=5, sigmaColor=30, sigmaSpace=5)
        return smoothed


# ============================================================
# Utility Functions
# ============================================================

def make_out_path(video_path: str, out_dir: Optional[str]) -> str:
    """Generate output video path"""
    p = Path(video_path)
    out_name = f"{p.stem}_traj.mp4"
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
    """Draw trajectory overlay"""
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


def pick_blue_from_history(blue_hist: List[np.ndarray], offset: int) -> Optional[np.ndarray]:
    """Pick blue point from history"""
    if not blue_hist:
        return None
    if offset > 0:
        offset = 0
    idx = -1 + offset
    if abs(idx) > len(blue_hist):
        return None
    return blue_hist[idx]


def clamp_step(current: np.ndarray, target: np.ndarray, max_step: float) -> np.ndarray:
    """Clamp movement step"""
    diff = target - current
    dist = np.linalg.norm(diff)
    if dist > max_step:
        diff = diff / dist * max_step
    return current + diff


def roi_size_schedule(size_init: int, size_min: int, track_t: int, shrink_over_frames: int) -> int:
    """Calculate ROI size based on tracking progress (ease-out quadratic)"""
    if shrink_over_frames <= 1:
        return size_min
    progress = min(max(track_t / float(shrink_over_frames), 0.0), 1.0)
    # 二次缓动曲线 (ease-out): u2 = 1 - (1-u)^2
    ease_progress = 1.0 - (1.0 - progress) ** 2
    size = size_init + (size_min - size_init) * ease_progress
    return int(round(size))


def get_dynamic_detect_cfg(p_index: int, roi_size: int, cfg_base: Dict, roi_cfg: Dict) -> Dict:
    """Get dynamic detection config"""
    cfg = cfg_base.copy()
    # ✅ 使用配置中的实际 size_init，确保参数缩放一致
    s = float(roi_size) / float(roi_cfg["size_init"])
    s = float(np.clip(s, 0.20, 1.0))
    
    # Adjust threshold based on tracking progress
    t = max(p_index - 1, 0)
    CFG_SPEED = 0.6
    tt = CFG_SPEED * t
    relax = 1.0 / (1.0 + 0.45 * tt)
    
    base_lo, base_hi = cfg_base.get("area_range", (4, 150))
    AREA_LO_MIN = 6
    lo = int(round(base_lo * (s**2) * relax))
    lo = max(AREA_LO_MIN, min(lo, base_lo))
    hi = int(round(base_hi * (s**2) * (0.80 + 0.20 * relax)))
    hi = max(lo + 2, min(hi, base_hi))
    cfg["area_range"] = (lo, hi)
    
    base_thr = float(cfg_base.get("diff_thresh", 16))
    DIFF_MIN = 9
    thr = base_thr * (0.55 * s + 0.45) * relax
    thr = float(np.clip(thr, DIFF_MIN, base_thr))
    cfg["diff_thresh"] = int(round(thr))
    
    base_c = float(cfg_base.get("circ_thresh", 0.60))
    CIRC_MIN = 0.60
    circ = base_c * (0.90 * relax + 0.10)
    circ = float(np.clip(circ, CIRC_MIN, base_c))
    cfg["circ_thresh"] = circ
    
    return cfg


def detect_candidates_with_stats(
    roi_g: np.ndarray,
    prev_roi_g: np.ndarray,
    cfg: Dict,
) -> List[Dict[str, Any]]:
    """Detect ball candidates with statistics"""
    if roi_g is None or prev_roi_g is None:
        return []
    if roi_g.size == 0 or prev_roi_g.size == 0:
        return []
    if roi_g.shape != prev_roi_g.shape:
        return []
    
    area_range = cfg.get("area_range", (4, 150))
    circ_thresh = cfg.get("circ_thresh", 0.60)
    diff_thresh = cfg.get("diff_thresh", 16)
    show_debug = cfg.get("show_debug", False)
    prefix = cfg.get("debug_prefix", "DEBUG")
    
    # Compute difference and threshold
    diff = cv2.absdiff(roi_g, prev_roi_g)
    _, binary = cv2.threshold(diff, diff_thresh, 255, cv2.THRESH_BINARY)
    binary = cv2.morphologyEx(binary, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
    
    if show_debug:
        cv2.imshow(f"{prefix}_DIFF", diff)
        cv2.imshow(f"{prefix}_BINARY", binary)
        cv2.waitKey(1)
    
    # Find contours
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
# Main Processing Functions
# ============================================================

def process_one_video(video_path: str, config: BallTrackingConfig) -> Optional[str]:
    """Process single video with full state machine"""
    
    print("\n" + "="*90)
    print("▶ Processing video:", video_path)
    
    # 檢查文件是否存在
    if not os.path.exists(video_path):
        print(f"❌ [第 401 行] 視頻文件不存在: {video_path}")
        print(f"   完整路徑: {os.path.abspath(video_path)}")
        return None
    
    print(f"✅ 文件存在，大小: {os.path.getsize(video_path)} bytes")
    
    # 嘗試打開視頻
    print(f"🎬 嘗試使用 OpenCV 打開視頻...")
    cap = cv2.VideoCapture(video_path)
    
    if not cap.isOpened():
        print(f"❌ [第 415 行] 無法打開視頻")
        print(f"   路徑: {video_path}")
        print(f"   可能原因:")
        print(f"     1. 文件格式不支持")
        print(f"     2. 視頻編碼器未安裝")
        print(f"     3. 文件已損壞")
        print(f"     4. 網絡路徑權限問題")
        
        # 嘗試獲取更多信息
        try:
            import subprocess
            # 使用 ffprobe 檢查文件信息
            result = subprocess.run(
                ["ffprobe", "-v", "error", "-show_format", video_path],
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode == 0:
                print(f"   ℹ️  ffprobe 信息: {result.stdout[:200]}")
            else:
                print(f"   ℹ️  ffprobe 錯誤: {result.stderr[:200]}")
        except Exception as e:
            print(f"   ℹ️  無法運行 ffprobe: {e}")
        
        return None
    
    fps = cap.get(cv2.CAP_PROP_FPS)
    dt = 1.0 / max(fps, 1.0)
    print(f"✅ FPS={fps:.3f}, dt={dt:.4f}")
    
    # Initialize state
    kf = KalmanFilter2D(KFParams(dt=dt))
    prev_gray: Optional[np.ndarray] = None
    frame_idx = 0
    
    roi_center: Optional[Tuple[int, int]] = None
    state = 0  # STATE_WAIT_P0
    wait_frames = 0
    
    track_pts: List[Tuple[int, int]] = []
    p0_frame_idx: Optional[int] = None
    
    roi_center_smooth: Optional[np.ndarray] = None
    track_t = 0
    
    y_dir: Optional[int] = None
    step_mode_active = False
    blue_hist: List[np.ndarray] = []
    
    writer = None
    out_path = config.out_video_path
    
    clicked_point: Optional[Tuple[int, int]] = None
    
    # Fixed ROI mode
    if config.fixed_roi_mode:
        roi_center = tuple(map(int, config.fixed_roi_center))
        print("✅ FIXED_ROI_MODE: ROI center =", roi_center)
    
    while True:
        ret, frame0 = cap.read()
        if not ret:
            break
        frame_idx += 1
        
        # Apply flip
        frame = ImageProcessor.apply_flip(frame0, config.flip_mode)
        raw_gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        gray = ImageProcessor.preprocess_gray(raw_gray)
        
        # Initialize on first frame
        if frame_idx == 1 and roi_center is None and not config.fixed_roi_mode:
            print("🖱 Need to click ROI center (not implemented in refactored version)")
            roi_center = (gray.shape[1] // 2, gray.shape[0] // 2)
        
        # Initialize writer
        if config.export_video and writer is None:
            if out_path is None:
                out_path = make_out_path(video_path, config.output_dir)
            
            # 计算旋转后的输出尺寸
            probe = frame.copy()
            if config.out_rotate_mode == 4:
                probe = cv2.rotate(probe, cv2.ROTATE_90_CLOCKWISE)
            elif config.out_rotate_mode == 5:
                probe = cv2.rotate(probe, cv2.ROTATE_90_COUNTERCLOCKWISE)
            elif config.out_rotate_mode == 6:
                probe = cv2.rotate(probe, cv2.ROTATE_180)
            oh, ow = probe.shape[:2]
            fourcc = cv2.VideoWriter_fourcc(*"mp4v")
            writer = cv2.VideoWriter(out_path, fourcc, float(max(fps, 1.0)), (ow, oh))
            if not writer.isOpened():
                print("❌ VideoWriter failed:", out_path)
                writer = None
            else:
                print("💾 Output video:", out_path)
        
        if prev_gray is None:
            prev_gray = gray
            if writer is not None:
                out_vis = frame.copy()
                out_vis = draw_traj_overlay_only(
                    out_vis, track_pts, config.draw_traj_until_pn,
                    config.traj_color_bgr, config.traj_alpha, config.traj_thickness,
                    config.traj_draw_from_p0, config.traj_min_points
                )
                # 应用输出旋转
                if config.out_rotate_mode == 4:
                    out_vis = cv2.rotate(out_vis, cv2.ROTATE_90_CLOCKWISE)
                elif config.out_rotate_mode == 5:
                    out_vis = cv2.rotate(out_vis, cv2.ROTATE_90_COUNTERCLOCKWISE)
                elif config.out_rotate_mode == 6:
                    out_vis = cv2.rotate(out_vis, cv2.ROTATE_180)
                writer.write(out_vis)
            continue
        
        if frame_idx > config.track_frames:
            print("✅ Reached TRACK_FRAMES")
            break
        
        # Calculate ROI
        if state in (0, 1):  # WAIT_P0, WAIT_P1
            cx, cy = roi_center
            roi_size = config.roi_cfg["size_init"]
        else:  # TRACKING
            target = np.array(kf.pos(), dtype=np.float32)
            if roi_center_smooth is None:
                roi_center_smooth = target.copy()
            target_limited = clamp_step(roi_center_smooth, target, config.roi_cfg["max_center_step"])
            a = config.roi_cfg["center_alpha"]
            roi_center_smooth = (1 - a) * roi_center_smooth + a * target_limited
            cx, cy = int(round(roi_center_smooth[0])), int(round(roi_center_smooth[1]))
            roi_size = roi_size_schedule(
                config.roi_cfg["size_init"],
                config.roi_cfg["size_min"],
                track_t,
                config.roi_cfg["shrink_over_frames"]
            )
        
        # Extract ROI
        half = roi_size // 2
        x1 = max(cx - half, 0)
        y1 = max(cy - half, 0)
        x2 = min(cx + half, frame.shape[1] - 1)
        y2 = min(cy + half, frame.shape[0] - 1)
        
        if x2 <= x1 or y2 <= y1:
            prev_gray = gray
            if writer is not None:
                out_vis = frame.copy()
                out_vis = draw_traj_overlay_only(
                    out_vis, track_pts, config.draw_traj_until_pn,
                    config.traj_color_bgr, config.traj_alpha, config.traj_thickness,
                    config.traj_draw_from_p0, config.traj_min_points
                )
                # 应用输出旋转
                if config.out_rotate_mode == 4:
                    out_vis = cv2.rotate(out_vis, cv2.ROTATE_90_CLOCKWISE)
                elif config.out_rotate_mode == 5:
                    out_vis = cv2.rotate(out_vis, cv2.ROTATE_90_COUNTERCLOCKWISE)
                elif config.out_rotate_mode == 6:
                    out_vis = cv2.rotate(out_vis, cv2.ROTATE_180)
                writer.write(out_vis)
            continue
        
        roi_g = gray[y1:y2, x1:x2]
        prev_roi_g = prev_gray[y1:y2, x1:x2]
        
        # Detect candidates
        # ✅ 只在TRACKING时用dynamic detect，WAIT阶段用最宽松参数
        if state == 2:  # TRACKING
            active_cfg = get_dynamic_detect_cfg(len(track_pts) - 1, roi_size, config.detect_cfg_base, config.roi_cfg)
        else:  # WAIT_P0, WAIT_P1
            active_cfg = config.detect_cfg_base
        cand_stats_roi = detect_candidates_with_stats(roi_g, prev_roi_g, active_cfg)
        
        # Convert to global coordinates
        cand_stats_glb: List[Dict[str, Any]] = []
        for c in cand_stats_roi:
            gx = x1 + c["pt_roi"][0]
            gy = y1 + c["pt_roi"][1]
            cand_stats_glb.append({"pt": (gx, gy), "area": c["area"], "circ": c["circ"], "diff": c["diff"]})
        
        # State machine
        if state == 0:  # WAIT_P0
            wait_frames += 1
            if cand_stats_glb:
                rc = np.array(roi_center, dtype=np.float32)
                best = min(cand_stats_glb, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - rc))
                p0 = best["pt"]
                track_pts = [p0]
                state = 1
                wait_frames = 0
                p0_frame_idx = frame_idx
                print(f"✅ Captured p0={p0}")
            elif wait_frames >= config.wait_max_frames:
                print("⚠️ Timeout: no p0")
        
        elif state == 1:  # WAIT_P1
            wait_frames += 1
            
            if config.p1_must_appear_next and p0_frame_idx is not None:
                if frame_idx - p0_frame_idx > config.p1_deadline_frames:
                    print(f"🧹 p0 false alarm: reset")
                    track_pts = []
                    state = 0
                    wait_frames = 0
                    p0_frame_idx = None
                    prev_gray = gray
                    continue
            
            if cand_stats_glb:
                p0 = track_pts[0]
                valid = [c for c in cand_stats_glb if c["pt"][0] < p0[0] - config.min_dx]
                if valid:
                    p0v = np.array(p0, dtype=np.float32)
                    best = min(valid, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - p0v))
                    p1 = best["pt"]
                    track_pts.append(p1)
                    
                    kf.initialize_from_two_points(p0, p1)
                    p0_frame_idx = None
                    state = 2
                    track_t = 0
                    roi_center_smooth = np.array(p1, dtype=np.float32)
                    step_mode_active = config.step_mode_after_p1
                    blue_hist.clear()
                    print("✅ Entering TRACKING")
        
        else:  # TRACKING (state == 2)
            track_t += 1
            
            kf.predict()
            this_blue_xy = np.array(kf.pos(), dtype=np.float32)
            blue_hist.append(this_blue_xy.copy())
            
            too_many = len(cand_stats_glb) >= config.too_many_cands_threshold
            
            if too_many and config.too_many_cands_use_blue:
                chosen_blue = pick_blue_from_history(blue_hist, config.blue_p_offset)
                if chosen_blue is not None:
                    ok = True
                    if config.blue_to_lastp_max_dist is not None and track_pts:
                        last = np.array(track_pts[-1], dtype=np.float32)
                        d = float(np.linalg.norm(chosen_blue - last))
                        if d > float(config.blue_to_lastp_max_dist):
                            ok = False
                    if ok:
                        p_from_blue = (int(round(chosen_blue[0])), int(round(chosen_blue[1])))
                        track_pts.append(p_from_blue)
                        if track_t % 30 == 0:  # 每30幀打印一次
                            print(f"  � Frame {frame_idx}: Too many candidates ({len(cand_stats_glb)}), using blue: {p_from_blue}, total={len(track_pts)}")
            else:
                if cand_stats_glb:
                    last_pt = track_pts[-1]
                    pool_left = [c for c in cand_stats_glb if c["pt"][0] < last_pt[0] - config.min_dx]
                    pool = pool_left
                    
                    # ✅ Y 方向约束逻辑（与原版一致）
                    STRICT_Y_DIRECTION = True
                    if pool and config.use_y_direction and y_dir is not None:
                        if y_dir < 0:
                            pool_y = [c for c in pool if c["pt"][1] <= last_pt[1] + config.y_tol]
                        else:
                            pool_y = [c for c in pool if c["pt"][1] >= last_pt[1] - config.y_tol]
                        pool_y = [c for c in pool_y if abs(c["pt"][1] - last_pt[1]) <= config.y_max_step]
                        
                        if pool_y:
                            pool = pool_y
                        else:
                            # ✅ 原版逻辑：严格模式下找不到就放弃
                            pool = [] if STRICT_Y_DIRECTION else pool_left
                    
                    if pool:
                        pred = this_blue_xy
                        best = min(pool, key=lambda c: np.linalg.norm(np.array(c["pt"], dtype=np.float32) - pred))
                        z = best["pt"]
                        kf.update(z)
                        track_pts.append((int(z[0]), int(z[1])))
                        
                        if config.use_y_direction and y_dir is None and len(track_pts) >= 3:
                            p0_, p1_, p2_ = track_pts[0], track_pts[1], track_pts[2]
                            dy = p2_[1] - p0_[1]
                            if abs(dy) >= 2:
                                y_dir = 1 if dy > 0 else -1
                            print(f"📌 y_dir set = {y_dir} (dy={dy})")
        
        # Output video
        if writer is not None:
            out_vis = frame.copy()
            out_vis = draw_traj_overlay_only(
                out_vis,
                track_pts,
                pn=config.draw_traj_until_pn,
                color_bgr=config.traj_color_bgr,
                alpha=config.traj_alpha,
                thickness=config.traj_thickness,
                draw_from_p0=config.traj_draw_from_p0,
                min_points=config.traj_min_points,
            )
            # 应用输出旋转 
            if config.out_rotate_mode == 4:
                out_vis = cv2.rotate(out_vis, cv2.ROTATE_90_CLOCKWISE)
            elif config.out_rotate_mode == 5:
                out_vis = cv2.rotate(out_vis, cv2.ROTATE_90_COUNTERCLOCKWISE)
            elif config.out_rotate_mode == 6:
                out_vis = cv2.rotate(out_vis, cv2.ROTATE_180)
            writer.write(out_vis)
        
        # UI display
        if config.show_main:
            cv2.imshow("Tracking (preview)", frame)
            if step_mode_active and state == 2:
                while True:
                    k = cv2.waitKey(0) & 0xFF
                    if k in config.enter_keys:
                        break
                    if k == config.esc_key:
                        break
                if k == config.esc_key:
                    break
            else:
                k = cv2.waitKey(30) & 0xFF
                if k == config.esc_key:
                    break
        
        prev_gray = gray
    
    cap.release()
    if writer is not None:
        writer.release()
    
    if config.show_main or config.show_debug_roi:
        cv2.destroyAllWindows()
    
    if config.export_video and out_path and Path(out_path).exists():
        print("✅ Video saved:", out_path)
        return out_path
    
    print("✅ Done (no video output)")
    return None


def run_ball_tracking(config: BallTrackingConfig) -> Optional[List[str]]:
    """Main entry point for ball tracking"""
    
    # Auto-disable UI in batch mode
    if config.batch_mode and config.auto_disable_ui_in_batch:
        config.show_main = False
        config.show_debug_roi = False
        config.detect_cfg_base["show_debug"] = False
    
    results = []
    
    if config.batch_mode:
        in_dir = Path(config.input_dir)
        if not in_dir.exists():
            print("❌ INPUT_DIR not found:", config.input_dir)
            return None
        
        vids = sorted([p for p in in_dir.glob("*.mp4")])
        print(f"📂 Batch mode: {config.input_dir}")
        print(f"🔍 Found {len(vids)} mp4 files")
        
        if len(vids) == 0:
            return None
        
        out_dir = config.output_dir
        if out_dir is not None:
            Path(out_dir).mkdir(parents=True, exist_ok=True)
            print(f"💾 Batch output to: {out_dir}")
        
        for vp in vids:
            result = process_one_video(str(vp), config)
            if result:
                results.append(result)
    else:
        result = process_one_video(config.video_path, config)
        if result:
            results.append(result)
    
    return results if results else None

if __name__ == "__main__":
    # 示例：單支影片追蹤
    config = BallTrackingConfig(
        batch_mode=False,
        video_path=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip_stabilized_pose_phase.mp4",
        output_dir=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41",
        show_main=False,  # 禁用主窗口
        show_debug_roi=False,  # 禁用调试窗口
    )
    # 禁用检测调试显示
    config.detect_cfg_base["show_debug"] = False
    
    result = run_ball_tracking(config)
    print(f"\n✅ 追蹤結果：{result}")