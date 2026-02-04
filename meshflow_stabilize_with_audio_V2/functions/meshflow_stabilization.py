"""
步驟2：MeshFlow Video Stabilization - 生產級函數庫
功能：使用MeshFlow演算法穩定視頻，移除相機晃動，保留音訊

API 概述：
  - MeshFlowConfig: 配置類（20+ 參數，預設值完善）
  - load_video_frames(): 讀取視頻幀
  - compute_shake_scores(): 計算晃動評分
  - detect_shake_segment(): 自動檢測晃動段
  - stabilize_video_segment(): 穩定視頻段
  - process_meshflow_stabilization(): 完整工作流
  - run_meshflow_stabilization(): 命令行/程序入口

使用示例：
  from functions.meshflow_stabilization import MeshFlowConfig, run_meshflow_stabilization
  config = MeshFlowConfig(input_path="input.mp4", output_path="output.mp4")
  result = run_meshflow_stabilization(config)
"""

import cv2
import math
import numpy as np
import statistics
import subprocess
import os
from pathlib import Path
from typing import Dict, Tuple, Optional, List, Any
from dataclasses import dataclass, field
import importlib.util

# 可選依賴
try:
    import tqdm
    TQDM_AVAILABLE = True
except ImportError:
    TQDM_AVAILABLE = False


# =============================================================================
# 配置類
# =============================================================================

@dataclass
class MeshFlowConfig:
    """MeshFlow 視頻穩定化配置類
    
    包含 20+ 可配置參數，控制穩定化算法的各個方面。
    所有參數都有合理的默認值。
    """
    # ========== 輸入輸出 ==========
    input_path: str = ""
    output_path: str = ""
    
    # ========== 網格參數 ==========
    mesh_row_count: int = 16
    mesh_col_count: int = 16
    mesh_outlier_subframe_row_count: int = 4
    mesh_outlier_subframe_col_count: int = 4
    
    # ========== 特徵偵測 ==========
    feature_ellipse_row_count: int = 10
    feature_ellipse_col_count: int = 10
    homography_min_number_corresponding_features: int = 4
    
    # ========== 時間平滑 ==========
    temporal_smoothing_radius: int = 10
    optimization_num_iterations: int = 80
    adaptive_weights_definition: int = 0  # 0=ORIGINAL, 1=FLIPPED, 2=CONSTANT_HIGH, 3=CONSTANT_LOW
    
    # ========== 晃動檢測 ==========
    auto_shake_segment: bool = True
    shake_smooth_win: int = 7
    shake_thresh_k: float = 4.0
    shake_pad_frames: int = 8
    shake_min_seg_len: int = 8
    manual_start: Optional[int] = None
    manual_end: Optional[int] = None
    
    # ========== 跳過模式 ==========
    skip_stabilization: bool = False  # True: 只存檔，不做穩定化
    
    # ========== GPU/CPU 選項 ==========
    use_gpu: bool = False  # True: 使用 GPU 加速版，False: 使用 CPU 版
    gpu_id: int = 0
    
    # ========== 輸出 ==========
    color_outside_image_area_bgr: Tuple[int, int, int] = field(default_factory=lambda: (0, 0, 255))
    visualize: bool = False
    warp_downscale: float = 0.5
    
    def __post_init__(self):
        """驗證配置參數"""
        if not self.input_path:
            raise ValueError("input_path 不能為空")
        if not self.output_path:
            raise ValueError("output_path 不能為空")


# =============================================================================
# 輔助函數 - GPU 檢查
# =============================================================================

def check_cuda_available() -> bool:
    """檢查 CUDA 是否可用"""
    try:
        return cv2.cuda.getCudaEnabledDeviceCount() > 0
    except Exception:
        return False


# =============================================================================
# 輔助函數 - 進度顯示
# =============================================================================

def _get_tqdm_wrapper(iterable, description: str, total: Optional[int] = None):
    """統一的 tqdm 包裝器（優雅降級）"""
    if TQDM_AVAILABLE:
        if hasattr(iterable, '__iter__') and not isinstance(iterable, (list, tuple)):
            return tqdm.tqdm(iterable, desc=description, total=total)
        else:
            return tqdm.tqdm(iterable, desc=description)
    else:
        return iterable


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
        
    Raises:
        ValueError: 輸出路徑不是 .mp4
        IOError: OpenCV VideoWriter 打開失敗
    """
    in_path = Path(input_path)
    out_path = Path(output_path)
    
    # ✅ 確保輸出目錄存在
    out_path.parent.mkdir(parents=True, exist_ok=True)
    
    if out_path.suffix.lower() != ".mp4":
        raise ValueError("output_path 必須是 .mp4 格式")
    
    temp_avi = out_path.with_suffix(".tmp_video_only.avi")
    
    # ✅ 驗證路徑
    if not out_path.parent.exists():
        raise IOError(f"輸出目錄建立失敗或無權限：{out_path.parent}")
    
    h, w = frames_bgr[0].shape[:2]
    fps_use = float(fps) if fps and fps > 1e-6 else 30.0
    
    # ✅ 轉換路徑為字符串（確保編碼正確）
    temp_avi_str = str(temp_avi)
    
    # ✅ 嘗試用 MJPG 寫 AVI
    fourcc = cv2.VideoWriter_fourcc(*"MJPG")
    writer = cv2.VideoWriter(temp_avi_str, fourcc, fps_use, (w, h))
    
    if not writer.isOpened():
        # ✅ 備用 XVID
        fourcc2 = cv2.VideoWriter_fourcc(*"XVID")
        writer = cv2.VideoWriter(temp_avi_str, fourcc2, fps_use, (w, h))
        if not writer.isOpened():
            # ✅ 詳細錯誤信息
            raise IOError(
                f"OpenCV VideoWriter 打開失敗\n"
                f"  路徑：{temp_avi}\n"
                f"  父目錄存在：{out_path.parent.exists()}\n"
                f"  父目錄可寫：{os.access(str(out_path.parent), os.W_OK)}\n"
                f"  編碼：MJPG/XVID"
            )
    
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
            # 原片無音訊時
            p2 = subprocess.run(cmd_no_audio, capture_output=True, text=True)
            if p2.returncode != 0:
                raise RuntimeError(
                    f"ffmpeg 失敗。\n"
                    f"[含音訊 stderr]\n{p.stderr}\n\n"
                    f"[無音訊 stderr]\n{p2.stderr}"
                )
    finally:
        try:
            if temp_avi.exists():
                temp_avi.unlink()
        except Exception:
            pass
    
    return True


# =============================================================================
# 核心函數 - 晃動檢測
# =============================================================================

def compute_shake_scores(
    homographies: np.ndarray,
    frame_width: int,
    frame_height: int
) -> np.ndarray:
    """計算晃動評分
    
    使用高通濾波（高頻能量）來表示晃動的「突然性」。
    
    Args:
        homographies: (num_frames, 3, 3) 單應矩陣數組
        frame_width: 幀寬度
        frame_height: 幀高度
        
    Returns:
        (num_frames,) 晃動評分（0-1 通常，超過 1 表示異常晃動）
    """
    alpha = 0.7
    raw = np.zeros((len(homographies),), dtype=np.float32)
    
    for i, M in enumerate(homographies):
        if M is None:
            continue
        
        M = M.astype(np.float32)
        tx = float(M[0, 2]) / max(frame_width, 1)
        ty = float(M[1, 2]) / max(frame_height, 1)
        trans = math.sqrt(tx * tx + ty * ty)
        
        A = M.copy()
        A[2] = [0, 0, 1]
        d = A - np.eye(3, dtype=np.float32)
        aff = float(np.sqrt(np.sum(d[:2, :2] * d[:2, :2])))
        
        raw[i] = trans + alpha * aff
    
    if len(raw) >= 2:
        raw[-1] = raw[-2]
    
    # 高通：計算高頻能量
    base = smooth_1d_signal(raw, win=9)
    hp = np.abs(raw - base)
    hp_s = smooth_1d_signal(hp, win=7)
    
    return hp_s


def smooth_1d_signal(x: np.ndarray, win: int = 7) -> np.ndarray:
    """1D 中位數平滑
    
    Args:
        x: 輸入信號
        win: 窗口大小（必須是奇數）
        
    Returns:
        平滑後的信號
    """
    win = int(win)
    if win < 3:
        return x
    if win % 2 == 0:
        win += 1
    
    pad = win // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    out = np.empty_like(x)
    
    for i in range(len(x)):
        out[i] = np.median(xp[i : i + win])
    
    return out


def pick_shake_segment(
    scores: np.ndarray,
    pad: int = 10,
    k: float = 4.0,
    min_len: int = 12
) -> Optional[Tuple[int, int]]:
    """從晃動評分中挑選晃動段
    
    使用堅牢統計（Robust Statistics）：
    threshold = median + k * MAD（中位數絕對差）
    
    Args:
        scores: 晃動評分數組
        pad: 段前後擴展的幀數
        k: 堅牢閾值係數
        min_len: 最小段長度
        
    Returns:
        (start, end) 或 None（未檢測到晃動段）
    """
    s = scores.astype(np.float32)
    med = float(np.median(s))
    mad = float(np.median(np.abs(s - med))) + 1e-9
    thr = med + k * mad
    
    mask = s > thr
    if not np.any(mask):
        return None
    
    # 找所有連續區段，取最長的
    idx = np.where(mask)[0]
    segs = []
    start = idx[0]
    prev = idx[0]
    
    for v in idx[1:]:
        if v == prev + 1:
            prev = v
        else:
            segs.append((start, prev))
            start = v
            prev = v
    segs.append((start, prev))
    
    # 取最長段
    segs.sort(key=lambda ab: (ab[1] - ab[0] + 1), reverse=True)
    start, end = segs[0]
    
    start = max(0, start - int(pad))
    end = min(len(s) - 1, end + int(pad))
    
    if (end - start + 1) < int(min_len):
        return None
    
    return start, end


def detect_shake_segment(
    frames: List[np.ndarray],
    homographies: np.ndarray,
    config: MeshFlowConfig
) -> Optional[Tuple[int, int]]:
    """檢測視頻中的晃動段
    
    流程：
    1. 計算晃動評分（基於預先計算的單應矩陣）
    2. 用堅牢統計自動檢測晃動段
    
    Args:
        frames: 視頻幀列表
        homographies: 預先計算的單應矩陣 (num_frames, 3, 3)
        config: MeshFlowConfig 配置
        
    Returns:
        (start_frame, end_frame) 或 None
    """
    h, w = frames[0].shape[:2]
    
    # 計算晃動評分
    scores = compute_shake_scores(homographies, w, h)
    scores_s = smooth_1d_signal(scores, win=config.shake_smooth_win)
    
    # 挑選晃動段
    seg = pick_shake_segment(
        scores_s,
        pad=config.shake_pad_frames,
        k=config.shake_thresh_k,
        min_len=config.shake_min_seg_len,
    )
    
    return seg


# =============================================================================
# 核心函數 - 穩定化
# =============================================================================

def stabilize_video_segment(
    stabilizer: Any,
    frames: List[np.ndarray],
    homographies: np.ndarray,
    unstab_disp: np.ndarray,
    start_frame: int,
    end_frame: int,
    adaptive_weights_def: int = 0
) -> Tuple[List[np.ndarray], Tuple[int, int, int, int]]:
    """穩定視頻的特定段
    
    Args:
        stabilizer: MeshFlowStabilizer 實例
        frames: 全視頻幀列表
        homographies: 單應矩陣
        unstab_disp: 不穩定位移
        start_frame: 段起始幀（包含）
        end_frame: 段末尾幀（包含）
        adaptive_weights_def: 自適應權重定義
        
    Returns:
        (穩定後的幀列表, 裁剪邊界)
    """
    sub_frames = frames[start_frame : end_frame + 1]
    
    # 置零基線
    sub_unstab = unstab_disp[start_frame : end_frame + 1].copy()
    sub_unstab -= sub_unstab[0]
    
    # 切割單應
    sub_H = homographies[start_frame : end_frame + 1].copy()
    sub_H[-1] = np.identity(3, dtype=np.float32)
    
    sub_num = len(sub_frames)
    
    # 計算穩定化位移
    sub_stab = stabilizer._get_stabilized_vertex_displacements(
        sub_num,
        sub_frames,
        adaptive_weights_def,
        sub_unstab,
        sub_H,
    )
    
    # 執行變形並獲得裁剪邊界
    sub_stabilized_uncropped, crop_boundaries = stabilizer._get_stabilized_frames_and_crop_boundaries(
        sub_num,
        sub_frames,
        sub_unstab,
        sub_stab,
    )
    
    return sub_stabilized_uncropped, crop_boundaries


# =============================================================================
# 完整工作流
# =============================================================================

def process_meshflow_stabilization(config: MeshFlowConfig) -> Dict[str, Any]:
    """完整的 MeshFlow 穩定化工作流
    
    流程：
    1. 標準化路徑（UNC → Linux 相容）
    2. 讀取視頻
    3. 計算動作估計（單應、位移）
    4. 自動或手動檢測晃動段
    5. 穩定化晃動段
    6. 編寫輸出視頻（保留音訊）
    7. 返回詳細結果
    
    Args:
        config: MeshFlowConfig 配置
        
    Returns:
        {'mode': str, 'segment': tuple or None, 'crop_boundaries': tuple,
         'output': str, 'result': dict}
    """
    print("\n" + "="*80)
    print("🎬 步驟 2/6：MeshFlow Video Stabilization with Audio")
    print("="*80)
    print(f"輸入：{config.input_path}")
    print(f"輸出：{config.output_path}")
    print(f"加速模式：{'GPU' if config.use_gpu else 'CPU'}")
    
    # 0.5 檢查是否跳過穩定化（只存檔）
    if config.skip_stabilization:
        print("\n⏭️  跳過穩定化，只執行存檔...")
        frames, num_frames, fps = load_video_frames(config.input_path)
        write_video_with_audio_copy(config.input_path, config.output_path, fps, frames)
        print(f"✅ 已複製視頻：{config.output_path}")
        return {
            "mode": "skip_stabilization_archive_only",
            "segment": None,
            "output": str(config.output_path),
        }
    
    # 1. 讀取視頻
    frames, num_frames, fps = load_video_frames(config.input_path)
    h, w = frames[0].shape[:2]
    print(f"✅ 已讀取視頻：{num_frames} 幀，{fps:.2f} fps，{w}x{h}")
    
    # 2. 選擇 CPU 或 GPU 版本
    use_gpu_final = config.use_gpu and check_cuda_available()
    if config.use_gpu and not use_gpu_final:
        print("⚠️  CUDA 不可用，降級到 CPU 模式")
    
    if use_gpu_final:
        # GPU 版本
        print("🚀 使用 GPU 加速版本")
        from meshflow_stabilize_gpu_function import MeshFlowStabilizerGPU
        stabilizer = MeshFlowStabilizerGPU(
            mesh_row_count=config.mesh_row_count,
            mesh_col_count=config.mesh_col_count,
            mesh_outlier_subframe_row_count=config.mesh_outlier_subframe_row_count,
            mesh_outlier_subframe_col_count=config.mesh_outlier_subframe_col_count,
            feature_ellipse_row_count=config.feature_ellipse_row_count,
            feature_ellipse_col_count=config.feature_ellipse_col_count,
            homography_min_number_corresponding_features=config.homography_min_number_corresponding_features,
            temporal_smoothing_radius=config.temporal_smoothing_radius,
            optimization_num_iterations=config.optimization_num_iterations,
            color_outside_image_area_bgr=config.color_outside_image_area_bgr,
            visualize=config.visualize,
            warp_downscale=config.warp_downscale,
            use_cuda=True,
            gpu_id=config.gpu_id,
        )
    else:
        # CPU 版本
        print("⚙️  使用 CPU 版本")
        script_path = Path(__file__).parent / "meshflow_stabilize_function.py"
        spec = importlib.util.spec_from_file_location("meshflow_module", script_path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        
        stabilizer = module.MeshFlowStabilizer(
            mesh_row_count=config.mesh_row_count,
            mesh_col_count=config.mesh_col_count,
            mesh_outlier_subframe_row_count=config.mesh_outlier_subframe_row_count,
            mesh_outlier_subframe_col_count=config.mesh_outlier_subframe_col_count,
            feature_ellipse_row_count=config.feature_ellipse_row_count,
            feature_ellipse_col_count=config.feature_ellipse_col_count,
            homography_min_number_corresponding_features=config.homography_min_number_corresponding_features,
            temporal_smoothing_radius=config.temporal_smoothing_radius,
            optimization_num_iterations=config.optimization_num_iterations,
            color_outside_image_area_bgr=config.color_outside_image_area_bgr,
            visualize=config.visualize,
            warp_downscale=config.warp_downscale,
        )
    
    
    # 4. 計算全片動作估計（一次性，避免重複計算）
    print("計算動作估計...")
    unstab_disp, homographies = stabilizer._get_unstabilized_vertex_displacements_and_homographies(
        num_frames, frames
    )
    print("✅ 計算全片動作估計")
    
    # 5. 檢測晃動段
    if config.auto_shake_segment:
        seg = detect_shake_segment(frames, homographies, config)
        if seg is None:
            print("⚠️  未檢測到明顯晃動，直接複製原視頻")
            write_video_with_audio_copy(config.input_path, config.output_path, fps, frames)
            return {
                "mode": "no_shake_detected_copy_only",
                "segment": None,
                "output": str(config.output_path),
            }
        start, end = seg
    else:
        if config.manual_start is None or config.manual_end is None:
            raise ValueError("auto_shake_segment=False 時，需提供 manual_start / manual_end")
        start = int(max(0, config.manual_start))
        end = int(min(num_frames - 1, config.manual_end))
        if end <= start:
            raise ValueError("manual_end 必須 > manual_start")
    
    print(f"✅ 晃動段：幀 {start} 到 {end}（共 {end - start + 1} 幀）")
    
    # 6. 穩定化晃動段
    sub_stabilized_uncropped, crop_boundaries = stabilize_video_segment(
        stabilizer, frames, homographies, unstab_disp,
        start, end, config.adaptive_weights_definition
    )
    
    print(f"✅ 穩定化晃動段")
    
    # 7. 組回全片
    merged_uncropped = list(frames)
    merged_uncropped[start : end + 1] = sub_stabilized_uncropped
    
    print(f"✅ 組回全片")
    # 8. 裁剪全片
    merged_cropped = stabilizer._crop_frames(merged_uncropped, crop_boundaries)
    
    print(f"✅ 裁剪全片")
    # 9. 寫檔
    write_video_with_audio_copy(config.input_path, config.output_path, fps, merged_cropped)
    print(f"✅ 已寫出視頻：{config.output_path}")
    
    return {
        "mode": "segment_meshflow",
        "segment": (start, end),
        "crop_boundaries": crop_boundaries,
        "output": str(config.output_path),
    }


# =============================================================================
# 公開 API
# =============================================================================

def run_meshflow_stabilization(config: Optional[MeshFlowConfig] = None) -> Dict[str, Any]:
    """MeshFlow 視頻穩定化的命令行和程序入口
    
    如果未提供配置，使用默認值。
    
    Args:
        config: MeshFlowConfig 配置，或 None 使用默認值
        
    Returns:
        {'mode': str, 'segment': tuple or None, 'crop_boundaries': tuple,
         'output': str}
        
    使用示例：
        # 默認配置
        result = run_meshflow_stabilization(
            MeshFlowConfig(
                input_path="input.mp4",
                output_path="output_stabilized.mp4"
            )
        )
        
        # 完全配置
        config = MeshFlowConfig(
            input_path="input.mp4",
            output_path="output.mp4",
            mesh_row_count=16,
            mesh_col_count=16,
            auto_shake_segment=True,
            shake_thresh_k=3.0,
        )
        result = run_meshflow_stabilization(config)
    """
    if config is None:
        config = MeshFlowConfig()
    
    try:
        result = process_meshflow_stabilization(config)
        print("\n✅ MeshFlow 穩定化完成")
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
    config = MeshFlowConfig(
        input_path=r"/data/tekswing/videos/8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9/4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41/clip.mp4",
        output_path=r"/data/tekswing/videos/8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9/4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41/clip_stabilized.mp4"
    )
    result = run_meshflow_stabilization(config)
