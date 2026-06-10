# =============================================================================
# OpenCV Affine Stabilization Module
# =============================================================================
"""
OpenCV 特徵匹配 + Affine 變換穩定化

架構：
    1. 特徵檢測：ORB/SIFT 找關鍵點
    2. 特徵匹配：BFMatcher 連接相鄰幀特徵
    3. Affine 計算：cv2.estimateAffinePartial2D 或 cv2.getAffineTransform
    4. 軌跡平滑：簡單移動平均或 Kalman 濾波
    5. 幀變形：cv2.warpAffine 補償運動
    6. 音訊合成：ffmpeg 合併音訊
    
特點：
    - 自動檢測晃動段落（可選）
    - 支持手動選擇穩定化區域
    - 高速處理（相比 MeshFlow）
    - 靈活的特徵檢測器選擇
"""

import os
import subprocess
import math
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Tuple, Dict, Optional, Any
import json

import numpy as np
import cv2

# 可選依賴
try:
    import tqdm
    TQDM_AVAILABLE = True
except ImportError:
    TQDM_AVAILABLE = False


# =============================================================================
# 配置類 (dataclass)
# =============================================================================

@dataclass
class OpenCVAffineConfig:
    """OpenCV Affine 穩定化配置
    
    特徵檢測：
        - detector: "ORB", "AKAZE", "SIFT"（需要 opencv-contrib）
        - max_features: 每幀最多特徵數
        - match_threshold: 特徵匹配距離閾值（0.7-0.8）
    
    變換估計：
        - use_ransac: 使用 RANSAC 過濾異常匹配
        - ransac_threshold: 像素距離閾值
    
    軌跡平滑：
        - smooth_window: 移動平均窗口（幀數）
        - use_kalman: 是否使用 Kalman 濾波（替代移動平均）
    
    自動晃動檢測：
        - auto_shake_segment: 自動檢測晃動區域
        - shake_threshold_k: 晃動檢測敏感度（σ的倍數）
        - min_segment_frames: 最小段落幀數
    
    輸出/控制：
        - skip_stabilization: True 跳過穩定化，只檢測
        - export_matrices: 匯出幀級變換矩陣 (.json)
        - output_color: 輸出幀顏色（"BGR" 或 "RGB"）
    """
    
    # 路徑
    input_path: str = "input.mp4"
    output_path: str = "output_stabilized.mp4"
    
    # 特徵檢測參數
    detector: str = "ORB"  # "ORB", "AKAZE", "SIFT"
    max_features: int = 500
    match_threshold: float = 0.75
    
    # 變換估計
    use_ransac: bool = True
    ransac_threshold: float = 5.0
    
    # 軌跡平滑
    smooth_window: int = 21  # 移動平均窗口
    use_kalman: bool = False  # Kalman 濾波
    kalman_process_variance: float = 0.01
    kalman_measure_variance: float = 0.1
    
    # 自動晃動檢測
    auto_shake_segment: bool = False
    shake_threshold_k: float = 3.0  # 3σ
    min_segment_frames: int = 10
    
    # 輸出控制
    skip_stabilization: bool = False
    export_matrices: bool = False
    output_color: str = "BGR"
    
    def __post_init__(self):
        """驗證配置"""
        self.input_path = str(self.input_path)
        self.output_path = str(self.output_path)
        
        if not Path(self.input_path).exists():
            raise FileNotFoundError(f"輸入視頻不存在：{self.input_path}")
        
        if self.detector not in ("ORB", "AKAZE", "SIFT"):
            raise ValueError(f"不支持的特徵檢測器：{self.detector}")
        
        if not (0.5 <= self.match_threshold <= 1.0):
            raise ValueError(f"匹配閾值應在 0.5-1.0：{self.match_threshold}")


# =============================================================================
# 工具函數
# =============================================================================

def _get_tqdm_wrapper(iterable, description: str = "", total: Optional[int] = None):
    """統一的 tqdm 包裝器（優雅降級）"""
    if TQDM_AVAILABLE:
        if hasattr(iterable, '__iter__') and not isinstance(iterable, (list, tuple)):
            return tqdm.tqdm(iterable, desc=description, total=total)
        else:
            return tqdm.tqdm(iterable, desc=description)
    else:
        return iterable


def smooth_1d_signal(signal: np.ndarray, win: int = 11) -> np.ndarray:
    """1D 信號移動平均平滑
    
    Args:
        signal: 1D 數組
        win: 窗口大小（奇數）
        
    Returns:
        平滑後的信號
    """
    if win <= 1:
        return signal.copy()
    
    win = max(1, win // 2) * 2 + 1  # 確保是奇數
    kernel = np.ones(win) / win
    
    # 邊界填充
    padded = np.pad(signal, (win // 2, win // 2), mode='edge')
    smoothed = np.convolve(padded, kernel, mode='valid')
    
    return smoothed[:len(signal)]


def create_feature_detector(detector_type: str, max_features: int):
    """建立特徵檢測器
    
    Args:
        detector_type: "ORB", "AKAZE", "SIFT"
        max_features: 最大特徵數
        
    Returns:
        OpenCV 特徵檢測器物件
    """
    if detector_type == "ORB":
        return cv2.ORB_create(nfeatures=max_features)
    elif detector_type == "AKAZE":
        return cv2.AKAZE_create(nfeatures=max_features)
    elif detector_type == "SIFT":
        return cv2.SIFT_create(nfeatures=max_features)
    else:
        raise ValueError(f"未知的特徵檢測器：{detector_type}")


def detect_and_match_features(
    detector,
    matcher,
    prev_frame: np.ndarray,
    curr_frame: np.ndarray,
    match_threshold: float
) -> Tuple[List[cv2.DMatch], np.ndarray, np.ndarray]:
    """檢測幀中的特徵並進行匹配
    
    Args:
        detector: 特徵檢測器
        matcher: 特徵匹配器
        prev_frame: 上一幀 (灰度)
        curr_frame: 當前幀 (灰度)
        match_threshold: 匹配距離閾值比例
        
    Returns:
        (good_matches, kp1, kp2) 匹配點、上幀關鍵點、當前幀關鍵點
    """
    kp1, des1 = detector.detectAndCompute(prev_frame, None)
    kp2, des2 = detector.detectAndCompute(curr_frame, None)
    
    if des1 is None or des2 is None or len(kp1) < 3 or len(kp2) < 3:
        return [], kp1, kp2
    
    # Brute Force Matcher
    if des1.dtype == np.uint8:  # ORB, AKAZE
        matches = matcher.knnMatch(des1, des2, k=2)
    else:  # SIFT (float32)
        matches = matcher.knnMatch(des1, des2, k=2)
    
    # Lowe's ratio test
    good = []
    for m_list in matches:
        if len(m_list) == 2:
            m, n = m_list
            if m.distance < match_threshold * n.distance:
                good.append(m)
    
    return good, kp1, kp2


def estimate_affine_from_matches(
    matches: List[cv2.DMatch],
    kp1: np.ndarray,
    kp2: np.ndarray,
    use_ransac: bool = True,
    ransac_threshold: float = 5.0
) -> Tuple[np.ndarray, int]:
    """從特徵匹配估計 Affine 變換矩陣
    
    Args:
        matches: 特徵匹配列表
        kp1: 上幀關鍵點
        kp2: 當前幀關鍵點
        use_ransac: 是否使用 RANSAC
        ransac_threshold: RANSAC 閾值 (像素)
        
    Returns:
        (affine_matrix (2x3), num_inliers) 或 (None, 0) 如果失敗
    """
    if len(matches) < 3:
        return None, 0
    
    src_pts = np.float32([kp1[m.queryIdx].pt for m in matches]).reshape(-1, 1, 2)
    dst_pts = np.float32([kp2[m.trainIdx].pt for m in matches]).reshape(-1, 1, 2)
    
    if use_ransac:
        M, mask = cv2.estimateAffinePartial2D(src_pts, dst_pts, method=cv2.RANSAC, 
                                               ransacReprojThreshold=ransac_threshold)
        inliers = int(np.sum(mask)) if mask is not None else 0
        return M, inliers
    else:
        M = cv2.estimateAffinePartial2D(src_pts, dst_pts, method=cv2.LMEDS)
        if M[0] is None:
            return None, len(matches)
        return M[0], len(matches)


# =============================================================================
# 核心函數 - 輸入/輸出
# =============================================================================

def load_video_frames(video_path: str) -> Tuple[List[np.ndarray], int, float]:
    """讀取視頻文件的所有幀
    
    Args:
        video_path: 視頻文件路徑
        
    Returns:
        (frames, num_frames, fps) 幀列表、幀數、幀率
        
    Raises:
        IOError: 無法打開視頻或幀讀取失敗
    """
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise IOError(f"無法打開視頻：{video_path}")
    
    num_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps = float(cap.get(cv2.CAP_PROP_FPS))
    
    frames = []
    for i in _get_tqdm_wrapper(range(num_frames), f"讀取視頻 <{Path(video_path).name}>", num_frames):
        ok, frame = cap.read()
        if not ok or frame is None:
            raise IOError(f"視頻缺幀 {i}/{num_frames}")
        frames.append(frame)
    
    cap.release()
    return frames, num_frames, fps


def write_video_with_audio_copy(
    input_path: str,
    output_path: str,
    fps: float,
    frames_bgr: List[np.ndarray]
) -> bool:
    """寫出視頻並複製音訊
    
    流程：
    1. OpenCV 寫臨時 AVI（無音訊，MJPG/XVID）
    2. ffmpeg：臨時視頻 + 原音訊 → mp4
    
    Args:
        input_path: 原輸入視頻路徑（用於提取音訊）
        output_path: 最終輸出 mp4 路徑
        fps: 幀率
        frames_bgr: BGR 幀列表
        
    Returns:
        True 成功，False 失敗
    """
    in_path = Path(input_path)
    out_path = Path(output_path)
    
    out_path.parent.mkdir(parents=True, exist_ok=True)
    
    if out_path.suffix.lower() != ".mp4":
        raise ValueError("output_path 必須是 .mp4 格式")
    
    temp_avi = out_path.with_suffix(".tmp_video_only.avi")
    
    h, w = frames_bgr[0].shape[:2]
    fps_use = float(fps) if fps and fps > 1e-6 else 30.0
    
    # 寫臨時 AVI
    fourcc = cv2.VideoWriter_fourcc(*"MJPG")
    writer = cv2.VideoWriter(str(temp_avi), fourcc, fps_use, (w, h))
    
    if not writer.isOpened():
        fourcc2 = cv2.VideoWriter_fourcc(*"XVID")
        writer = cv2.VideoWriter(str(temp_avi), fourcc2, fps_use, (w, h))
        if not writer.isOpened():
            raise IOError(f"OpenCV VideoWriter 打開失敗：{temp_avi}")
    
    for i in _get_tqdm_wrapper(range(len(frames_bgr)), f"寫臨時視頻 <{temp_avi.name}>", len(frames_bgr)):
        writer.write(frames_bgr[i])
    writer.release()
    
    # ffmpeg 合成（視頻 + 音訊）
    cmd_with_audio = [
        "ffmpeg", "-y",
        "-i", str(temp_avi),
        "-i", str(in_path),
        "-map", "0:v:0",
        "-map", "1:a:0",
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
        "-c:a", "copy",
        "-shortest",
        str(out_path),
    ]
    cmd_no_audio = [
        "ffmpeg", "-y",
        "-i", str(temp_avi),
        "-c:v", "libx264", "-preset", "veryfast", "-crf", "18",
        "-an",
        str(out_path),
    ]
    
    try:
        p = subprocess.run(cmd_with_audio, capture_output=True, text=True)
        if p.returncode != 0:
            p2 = subprocess.run(cmd_no_audio, capture_output=True, text=True)
            if p2.returncode != 0:
                raise RuntimeError(f"ffmpeg 失敗")
    finally:
        try:
            if temp_avi.exists():
                temp_avi.unlink()
        except Exception:
            pass
    
    return True


# =============================================================================
# 核心函數 - Affine 變換估計
# =============================================================================

def estimate_all_affine_matrices(
    frames_gray: List[np.ndarray],
    config: OpenCVAffineConfig
) -> Tuple[List[np.ndarray], np.ndarray]:
    """估計所有相鄰幀間的 Affine 變換矩陣
    
    Args:
        frames_gray: 灰度幀列表
        config: OpenCVAffineConfig 配置
        
    Returns:
        (affine_matrices, motion_scores)
            - affine_matrices: [(2x3) 矩陣, ...] 長度 = len(frames) - 1
            - motion_scores: [float, ...] 長度 = len(frames) - 1
    """
    num_frames = len(frames_gray)
    affine_matrices = []
    motion_scores = np.zeros((num_frames - 1,), dtype=np.float32)
    
    # 建立檢測器和匹配器
    detector = create_feature_detector(config.detector, config.max_features)
    
    if config.detector == "SIFT":
        matcher = cv2.BFMatcher(cv2.NORM_L2, crossCheck=False)
    else:
        matcher = cv2.BFMatcher(cv2.NORM_HAMMING, crossCheck=False)
    
    # 特徵匹配
    print(f"🔍 特徵檢測與匹配 ({config.detector}) ...")
    for i in _get_tqdm_wrapper(range(num_frames - 1), f"Affine 估計", num_frames - 1):
        prev_gray = frames_gray[i]
        curr_gray = frames_gray[i + 1]
        
        # 檢測與匹配
        matches, kp1, kp2 = detect_and_match_features(
            detector, matcher, prev_gray, curr_gray,
            config.match_threshold
        )
        
        if len(matches) < 3:
            # 使用單位矩陣（無變換）
            affine_matrices.append(np.eye(2, 3, dtype=np.float32))
            motion_scores[i] = 0.0
            continue
        
        # 估計 Affine 矩陣
        M, inliers = estimate_affine_from_matches(
            matches, kp1, kp2,
            use_ransac=config.use_ransac,
            ransac_threshold=config.ransac_threshold
        )
        
        if M is None:
            affine_matrices.append(np.eye(2, 3, dtype=np.float32))
            motion_scores[i] = 0.0
        else:
            affine_matrices.append(M)
            
            # 計算運動得分（平移量 + 旋轉/縮放量）
            tx = float(M[0, 2])
            ty = float(M[1, 2])
            trans = math.sqrt(tx * tx + ty * ty)
            
            A = M.copy()
            A[:, 2] = 0
            aff = float(np.sqrt(np.sum(A * A)))
            
            motion_scores[i] = trans + 0.7 * aff
    
    return affine_matrices, motion_scores


def accumulate_trajectory(
    affine_matrices: List[np.ndarray]
) -> np.ndarray:
    """計算累積運動軌跡
    
    將相鄰幀變換累積成絕對位置軌跡。
    
    Args:
        affine_matrices: 幀間 Affine 矩陣列表
        
    Returns:
        累積平移軌跡 (num_frames, 2)，第 0 幀為 [0, 0]
    """
    num_frames = len(affine_matrices) + 1
    trajectory = np.zeros((num_frames, 2), dtype=np.float32)
    
    for i in range(len(affine_matrices)):
        M = affine_matrices[i]
        if M is not None:
            # 累加平移（M 是 frame_i -> frame_{i+1} 的變換）
            trajectory[i + 1] = trajectory[i] + np.array([M[0, 2], M[1, 2]], dtype=np.float32)
        else:
            trajectory[i + 1] = trajectory[i]
    
    return trajectory


def smooth_trajectory(
    affine_matrices: List[np.ndarray],
    config: OpenCVAffineConfig
) -> Tuple[List[np.ndarray], np.ndarray]:
    """計算並平滑運動軌跡，生成補償變換
    
    正確的方法：
        1. 累積幀間變換 → 絕對軌跡
        2. 平滑絕對軌跡（移動平均）
        3. 補償 = 平滑軌跡 - 原軌跡（這就是要補正的運動）
    
    Args:
        affine_matrices: 幀間 Affine 矩陣列表
        config: 配置
        
    Returns:
        (compensation_matrices, smooth_trajectory) 
            補償矩陣列表和平滑後的軌跡
    """
    num_frames = len(affine_matrices) + 1
    
    # 1. 計算累積軌跡
    trajectory = accumulate_trajectory(affine_matrices)
    
    # 2. 平滑軌跡
    smooth_traj_x = smooth_1d_signal(trajectory[:, 0], win=config.smooth_window)
    smooth_traj_y = smooth_1d_signal(trajectory[:, 1], win=config.smooth_window)
    smooth_traj = np.column_stack([smooth_traj_x, smooth_traj_y])
    
    # 3. 計算補償（平滑軌跡 - 原軌跡 = 要補正的移動）
    compensation = smooth_traj - trajectory
    
    # 4. 轉換成幀級變換矩陣
    compensation_matrices = []
    for i in range(len(affine_matrices)):
        comp_matrix = np.eye(2, 3, dtype=np.float32)
        comp_matrix[0, 2] = compensation[i + 1, 0]
        comp_matrix[1, 2] = compensation[i + 1, 1]
        compensation_matrices.append(comp_matrix)
    
    return compensation_matrices, smooth_traj


def apply_compensation_to_frames(
    frames_bgr: List[np.ndarray],
    compensation_matrices: List[np.ndarray],
    start_frame: int,
    end_frame: int
) -> List[np.ndarray]:
    """應用補償變換穩定化視頻
    
    注意：補償矩陣已經是正向的（平滑軌跡 - 原軌跡），
    直接 warpAffine 應用即可。
    
    Args:
        frames_bgr: 原始 BGR 幀
        compensation_matrices: 補償矩陣
        start_frame: 開始幀
        end_frame: 結束幀
        
    Returns:
        補償後的幀列表
    """
    stabilized = frames_bgr.copy()
    h, w = frames_bgr[0].shape[:2]
    
    for i in _get_tqdm_wrapper(range(start_frame, min(end_frame, len(frames_bgr))), 
                               f"應用穩定化", end_frame - start_frame):
        if i == 0:
            continue
        
        comp = compensation_matrices[i - 1]
        
        # 應用補償（直接平移，不涉及複雜反演）
        stabilized[i] = cv2.warpAffine(
            frames_bgr[i],
            comp,
            (w, h),
            flags=cv2.INTER_LINEAR,
            borderMode=cv2.BORDER_REPLICATE
        )
    
    return stabilized


# =============================================================================
# 核心函數 - 晃動檢測
# =============================================================================

def detect_shake_segment(
    motion_scores: np.ndarray,
    config: OpenCVAffineConfig
) -> Optional[Tuple[int, int]]:
    """自動檢測晃動段落
    
    基於運動得分的統計特性（平均值 + 標準差）自動選擇。
    
    Args:
        motion_scores: 運動評分數組
        config: 配置
        
    Returns:
        (start_frame, end_frame) 或 None 如果沒有明顯晃動
    """
    if len(motion_scores) < config.min_segment_frames:
        return None
    
    mean = float(np.mean(motion_scores))
    std = float(np.std(motion_scores))
    threshold = mean + config.shake_threshold_k * std
    
    # 找超過閾值的連續幀
    shaky = motion_scores > threshold
    
    if not np.any(shaky):
        return None
    
    # 找最長的連續段
    runs = []
    start = None
    for i in range(len(shaky)):
        if shaky[i]:
            if start is None:
                start = i
        else:
            if start is not None:
                runs.append((start, i))
                start = None
    
    if start is not None:
        runs.append((start, len(shaky)))
    
    if not runs:
        return None
    
    longest = max(runs, key=lambda x: x[1] - x[0])
    
    if longest[1] - longest[0] >= config.min_segment_frames:
        return longest
    
    return None


# =============================================================================
# 公開 API
# =============================================================================

def process_opencv_affine_stabilization(config: OpenCVAffineConfig) -> Dict[str, Any]:
    """OpenCV Affine 穩定化的完整處理流程
    
    流程：
        1. 讀取視頻幀
        2. 估計相鄰幀的 Affine 變換
        3. 平滑軌跡
        4. 自動檢測晃動段落（可選）
        5. 應用補償變換
        6. 合成視頻並附加音訊
    
    Args:
        config: OpenCVAffineConfig 配置
        
    Returns:
        {'mode': str, 'segment': tuple or None, 'output': str}
    """
    try:
        print(f"\n📹 OpenCV Affine 穩定化")
        print(f"   輸入：{Path(config.input_path).name}")
        print(f"   特徵檢測器：{config.detector}")
        print(f"   平滑窗口：{config.smooth_window}")
        
        # 1. 讀取視頻
        frames_bgr, num_frames, fps = load_video_frames(config.input_path)
        frames_gray = [cv2.cvtColor(f, cv2.COLOR_BGR2GRAY) for f in frames_bgr]
        
        print(f"   幀數：{num_frames}，FPS：{fps:.2f}")
        
        # 2. 估計 Affine 變換
        affine_matrices, motion_scores = estimate_all_affine_matrices(frames_gray, config)
        
        # 3. 平滑軌跡
        print(f"📊 平滑軌跡...")
        compensation_matrices, smooth_traj = smooth_trajectory(affine_matrices, config)
        
        # 4. 自動檢測晃動段落
        detected_segment = None
        if config.auto_shake_segment:
            print(f"🔎 檢測晃動段落...")
            detected_segment = detect_shake_segment(motion_scores, config)
            if detected_segment:
                print(f"   找到晃動段：幀 {detected_segment[0]}-{detected_segment[1]}")
            else:
                print(f"   未檢測到明顯晃動")
        
        # 決定穩定化範圍
        if config.auto_shake_segment and detected_segment:
            start_frame, end_frame = detected_segment
        else:
            start_frame, end_frame = 0, len(frames_bgr)
        
        # 5. 應用補償變換
        if config.skip_stabilization:
            print(f"⏭️  跳過穩定化（配置）")
            stabilized_frames = frames_bgr
        else:
            print(f"🔄 應用補償變換...")
            stabilized_frames = apply_compensation_to_frames(
                frames_bgr, compensation_matrices,
                start_frame, end_frame
            )
        
        # 6. 寫視頻
        print(f"💾 寫輸出視頻...")
        write_video_with_audio_copy(
            config.input_path,
            config.output_path,
            fps,
            stabilized_frames
        )
        
        # 可選：匯出變換矩陣
        if config.export_matrices:
            matrices_json = {
                "num_frames": num_frames,
                "fps": fps,
                "affine_matrices": [
                    M.tolist() if M is not None else None
                    for M in affine_matrices
                ],
                "compensation_matrices": [
                    M.tolist() if M is not None else None
                    for M in compensation_matrices
                ],
                "smooth_trajectory": smooth_traj.tolist(),
                "motion_scores": motion_scores.tolist()
            }
            export_path = Path(config.output_path).with_suffix(".json")
            with open(export_path, 'w') as f:
                json.dump(matrices_json, f, indent=2)
            print(f"   軌跡已匯出：{export_path}")
        
        return {
            "mode": "segment_opencv_affine",
            "segment": (start_frame, end_frame),
            "output": str(config.output_path),
        }
    
    except Exception as e:
        print(f"\n❌ 錯誤：{e}")
        raise


def run_opencv_affine_stabilization(config: Optional[OpenCVAffineConfig] = None) -> Dict[str, Any]:
    """OpenCV Affine 穩定化的命令行和程序入口
    
    如果未提供配置，使用默認值。
    
    Args:
        config: OpenCVAffineConfig 配置，或 None 使用默認值
        
    Returns:
        {'mode': str, 'segment': tuple, 'output': str}
        
    使用示例：
        # 默認配置
        result = run_opencv_affine_stabilization(
            OpenCVAffineConfig(
                input_path="input.mp4",
                output_path="output_stabilized.mp4"
            )
        )
        
        # ORB 特徵 + RANSAC + 自動晃動檢測
        config = OpenCVAffineConfig(
            input_path="input.mp4",
            output_path="output.mp4",
            detector="ORB",
            max_features=500,
            use_ransac=True,
            auto_shake_segment=True,
            shake_threshold_k=3.0,
        )
        result = run_opencv_affine_stabilization(config)
    """
    if config is None:
        config = OpenCVAffineConfig()
    
    try:
        result = process_opencv_affine_stabilization(config)
        print("\n✅ OpenCV Affine 穩定化完成")
        print(f"   模式：{result['mode']}")
        if result['segment']:
            print(f"   段：{result['segment']}")
        print(f"   輸出：{result['output']}")
        return result
    except Exception as e:
        print(f"\n❌ 錯誤：{e}")
        raise


# =============================================================================
# 主函數（測試用）
# =============================================================================

if __name__ == "__main__":
    # 測試用例
    config = OpenCVAffineConfig(
        input_path=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip.mp4",
        output_path=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip_stabilized_opencv.mp4",
        detector="SIFT",
        auto_shake_segment=True,
        export_matrices=False,
    )
    result = run_opencv_affine_stabilization(config)
