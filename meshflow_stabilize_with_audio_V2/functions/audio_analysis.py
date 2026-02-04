"""
步驟3：Audio Analysis and Classification - 生產級函數庫
功能：分析單一影片的擊球音頻特徵，提取音訊指標

API 概述：
  - AudioAnalysisConfig: 配置類（20+ 參數，預設值完善）
  - extract_audio_from_video(): 從視頻提取音訊
  - dynamic_peak_detection(): 自動檢測擊球峰值
  - compute_audio_features(): 計算完整音訊特徵（13 個 MFCC + 音量/頻譜/ZCR 等）
  - process_audio_analysis(): 完整工作流（單一影片）
  - run_audio_analysis(): 命令行/程序入口

使用示例：
  from functions.audio_analysis import AudioAnalysisConfig, run_audio_analysis
  config = AudioAnalysisConfig(
      video_path="path/to/video.mp4",
      output_dir="path/to/output"
  )
  result = run_audio_analysis(config)
"""

import os
import glob
import shutil
import time as ti
from pathlib import Path
from typing import Dict, Tuple, Optional, List, Any
from dataclasses import dataclass, field
import numpy as np
import pandas as pd

# 可選依賴
try:
    import librosa
    LIBROSA_AVAILABLE = True
except ImportError:
    LIBROSA_AVAILABLE = False

try:
    import soundfile as sf
    SOUNDFILE_AVAILABLE = True
except ImportError:
    SOUNDFILE_AVAILABLE = False

try:
    from scipy.fft import fft, fftfreq
    SCIPY_AVAILABLE = True
except ImportError:
    SCIPY_AVAILABLE = False

try:
    from moviepy import VideoFileClip
    MOVIEPY_AVAILABLE = True
except ImportError:
    MOVIEPY_AVAILABLE = False

try:
    import cv2
    CV2_AVAILABLE = True
except ImportError:
    CV2_AVAILABLE = False

try:
    import tqdm
    TQDM_AVAILABLE = True
except ImportError:
    TQDM_AVAILABLE = False


# =============================================================================
# 配置類
# =============================================================================

@dataclass
class AudioAnalysisConfig:
    """Audio Analysis 配置類
    
    包含 20+ 可配置參數，控制音訊分析的各個方面。
    所有參數都有合理的默認值。
    """
    # ========== 輸入輸出 ==========
    video_path: str = ""            # 單一影片路徑（必需）
    output_dir: str = ""
    
    # ========== 音量尺度 ==========
    loudness_mode: str = "dbfs"  # 'dbfs' 或 'raw'
    
    # ========== 峰值檢測參數 ==========
    peak_rel_strength: float = 0.8      # 相對強度閾值
    search_win_sec: float = 0.01        # 搜索窗口（秒）
    rms_frame_sec: float = 0.02         # RMS 幀長
    rms_hop_sec: float = 0.01           # RMS hop
    mad_k: float = 4.0                  # RMS+MAD 係數
    min_dist_sec: float = 0.35          # 最小擊球間距
    
    # ========== 時間參數 ==========
    pre_time_sec: float = 0.10          # 擊球前取樣
    post_time_sec: float = 0.10         # 擊球後取樣
    target_hit_sec: float = 3.0         # 目標擊球時間
    target_tol_sec: float = 0.5         # 允許誤差
    
    # ========== 背景/去噪參數 ==========
    bg_percentile: int = 25             # 背景百分位
    ss_beta: float = 1.0                # 頻譜減法係數
    ss_floor: float = 1e-6              # 頻譜減法地板值
    
    # ========== 頻帶特徵參數 ==========
    band_step_hz: int = 1000            # 頻帶步長
    band_max_hz: int = 8000             # 頻帶上限
    agree_cv_target: float = 0.20       # 一致度目標
    
    # ========== 流程開關 ==========
    save_segment_audio: bool = True     # 保存段音訊
    save_segment_png: bool = False      # 保存段圖像
    save_analysis_fig: bool = False     # 保存分析圖
    output_raw_csv: bool = False        # 輸出原始 CSV
    
    def __post_init__(self):
        """驗證配置參數"""
        if not self.video_path:
            raise ValueError("video_path 不能為空")
        if not Path(self.video_path).exists():
            raise FileNotFoundError(f"影片不存在：{self.video_path}")
        if self.loudness_mode not in ("dbfs", "raw"):
            raise ValueError("loudness_mode 必須是 'dbfs' 或 'raw'")


# =============================================================================
# 輔助函數 - 依賴檢查
# =============================================================================

def _check_dependencies():
    """檢查必需依賴"""
    missing = []
    for name, available in [
        ("librosa", LIBROSA_AVAILABLE),
        ("soundfile", SOUNDFILE_AVAILABLE),
        ("scipy", SCIPY_AVAILABLE),
        ("moviepy", MOVIEPY_AVAILABLE),
        ("cv2", CV2_AVAILABLE),
    ]:
        if not available:
            missing.append(name)
    
    if missing:
        raise ImportError(
            f"缺少必需的依賴：{', '.join(missing)}。"
            f"請運行：pip install {' '.join(missing)}"
        )


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

def extract_audio_from_video(video_path: str, output_audio_path: str, sr: int = 48000) -> bool:
    """從視頻提取音訊
    
    Args:
        video_path: 視頻文件路徑
        output_audio_path: 輸出音訊路徑（.wav）
        sr: 採樣率
        
    Returns:
        True 成功
        
    Raises:
        FileNotFoundError: 視頻不存在
        RuntimeError: 音訊提取失敗
    """
    if not Path(video_path).exists():
        raise FileNotFoundError(f"視頻不存在：{video_path}")
    
    try:
        clip = VideoFileClip(video_path)
        clip.audio.write_audiofile(output_audio_path, fps=sr)
        clip.close()
        return True
    except Exception as e:
        raise RuntimeError(f"音訊提取失敗：{e}")


def normalize_for_saving(y: np.ndarray) -> np.ndarray:
    """為保存而標準化音訊
    
    Args:
        y: 音訊數組
        
    Returns:
        標準化後的音訊（-1.0 到 1.0）
    """
    if y is None or len(y) == 0:
        return y
    
    y = librosa.util.normalize(y.astype(float))
    y = np.clip(y, -1.0, 1.0)
    return y


# =============================================================================
# 核心函數 - 峰值檢測
# =============================================================================

def compute_frame_rms(
    y: np.ndarray,
    sr: int,
    frame_len_sec: float = 0.02,
    hop_len_sec: float = 0.01
) -> Tuple[np.ndarray, np.ndarray, int, int]:
    """計算幀 RMS 值
    
    Args:
        y: 音訊信號
        sr: 採樣率
        frame_len_sec: 幀長（秒）
        hop_len_sec: hop 長（秒）
        
    Returns:
        (rms_values, time_axis, n_fft, hop_samples)
    """
    n_fft = int(frame_len_sec * sr)
    hop = int(hop_len_sec * sr)
    rms = librosa.feature.rms(y=y, frame_length=n_fft, hop_length=hop, center=True)[0]
    t = np.arange(len(rms)) * hop / sr
    return rms, t, n_fft, hop


def pick_background_mask(
    rms_values: np.ndarray,
    percentile: int = 25
) -> Tuple[np.ndarray, float]:
    """挑選背景幀掩碼
    
    Args:
        rms_values: RMS 值
        percentile: 百分位（低於此值視為背景）
        
    Returns:
        (背景掩碼布爾數組, 閾值)
    """
    thr = np.percentile(rms_values, percentile)
    return rms_values < thr, thr


def estimate_noise_spectrum(
    y: np.ndarray,
    sr: int,
    bg_mask: np.ndarray,
    n_fft: int,
    hop: int
) -> np.ndarray:
    """估計噪聲頻譜
    
    Args:
        y: 音訊信號
        sr: 採樣率
        bg_mask: 背景掩碼
        n_fft: FFT 大小
        hop: hop 大小
        
    Returns:
        噪聲幅度參考
    """
    S = librosa.stft(y, n_fft=n_fft, hop_length=hop, window="hann", center=True)
    mag = np.abs(S)
    
    if bg_mask.sum() < 3:
        noise_ref = np.minimum(mag, np.percentile(mag, 20, axis=1, keepdims=True))
    else:
        noise_ref = mag[:, bg_mask].mean(axis=1, keepdims=True)
    
    return noise_ref


def spectral_subtraction(
    segment: np.ndarray,
    sr: int,
    noise_mag_ref: np.ndarray,
    n_fft: int,
    hop: int,
    beta: float = 1.0,
    floor: float = 1e-6
) -> np.ndarray:
    """頻譜減法去噪
    
    Args:
        segment: 音訊段
        sr: 採樣率
        noise_mag_ref: 噪聲幅度參考
        n_fft: FFT 大小
        hop: hop 大小
        beta: 去噪強度
        floor: 地板值
        
    Returns:
        去噪後的音訊
    """
    S = librosa.stft(segment, n_fft=n_fft, hop_length=hop, window="hann", center=True)
    mag = np.abs(S)
    phase = np.angle(S)
    
    clean_mag = np.maximum(mag - beta * noise_mag_ref, floor)
    S_clean = clean_mag * np.exp(1j * phase)
    y_out = librosa.istft(S_clean, hop_length=hop, window="hann", length=len(segment))
    
    return y_out


def dynamic_peak_detection(
    y: np.ndarray,
    sr: int,
    win_sec: float = 0.02,
    hop_sec: float = 0.01,
    k: float = 4.0,
    min_dist_sec: float = 0.35
) -> Tuple[np.ndarray, Tuple]:
    """動態峰值檢測
    
    Args:
        y: 音訊信號
        sr: 採樣率
        win_sec: RMS 幀長
        hop_sec: RMS hop
        k: MAD 係數
        min_dist_sec: 最小峰間距
        
    Returns:
        (peak_samples, (rms, t, n_fft, hop))
    """
    rms, t, n_fft, hop_samp = compute_frame_rms(y, sr, win_sec, hop_sec)
    
    med = np.median(rms)
    mad = np.median(np.abs(rms - med)) + 1e-12
    thr = med + k * mad
    
    S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop_samp, window="hann"))
    flux = np.diff(S, axis=1)
    flux = np.maximum(flux, 0).sum(axis=0)
    flux = np.pad(flux, (1, 0))
    
    score_mask = (rms > thr) & (flux > np.median(flux))
    cand_idx = np.where(score_mask)[0]
    
    if cand_idx.size == 0:
        return np.array([], dtype=int), (rms, t, n_fft, hop_samp)
    
    peaks, min_hop, last = [], int(min_dist_sec / (hop_sec)), -9999
    for i in cand_idx:
        if i - last >= min_hop:
            peaks.append(i)
            last = i
    
    return (np.array(peaks) * hop_samp).astype(int), (rms, t, n_fft, hop_samp)


def filter_top_peaks_by_strength(
    peak_samples: np.ndarray,
    y: np.ndarray,
    sr: int,
    rel_thresh: float = 0.99,
    search_win_sec: float = 0.01
) -> np.ndarray:
    """按強度過濾峰值
    
    Args:
        peak_samples: 峰值樣本索引
        y: 音訊信號
        sr: 採樣率
        rel_thresh: 相對強度閾值
        search_win_sec: 搜索窗口
        
    Returns:
        過濾後的峰值
    """
    if len(peak_samples) == 0:
        return peak_samples
    
    half_w = int(search_win_sec * sr)
    strengths = []
    
    for ps in peak_samples:
        a = max(0, ps - half_w)
        b = min(len(y), ps + half_w + 1)
        strengths.append(float(np.max(np.abs(y[a:b]))))
    
    strengths = np.array(strengths)
    max_s = float(np.max(strengths)) if strengths.size else 0.0
    keep = strengths >= (rel_thresh * max_s)
    
    if not np.any(keep) and strengths.size:
        keep = strengths == max_s
    
    return peak_samples[keep]


# =============================================================================
# 核心函數 - 特徵提取
# =============================================================================

def compute_audio_features(
    y_segment: np.ndarray,
    sr: int,
    loudness_mode: str = "dbfs",
    band_step_hz: int = 1000,
    band_max_hz: int = 8000
) -> Dict[str, float]:
    """計算完整音訊特徵
    
    包含：
    - 音量（peak_dbfs / rms_dbfs 或 max_amp / rms）
    - 頻譜特徵（spectral_centroid, sharpness, ZCR）
    - 頻帶特徵（8 個頻帶的峰值頻率和幅度）
    - MFCC（13 個係數）
    
    Args:
        y_segment: 音訊段
        sr: 採樣率
        loudness_mode: "dbfs" 或 "raw"
        band_step_hz: 頻帶步長
        band_max_hz: 頻帶上限
        
    Returns:
        特徵字典
    """
    y_seg = y_segment.astype(float)
    out = {}
    
    # 音量特徵
    if len(y_seg) > 0:
        peak = float(np.max(np.abs(y_seg)))
        rms_val = float(np.sqrt(np.mean(y_seg ** 2)))
    else:
        peak, rms_val = 0.0, 0.0
    
    if loudness_mode == "dbfs":
        out["peak_dbfs"] = float(20 * np.log10(peak + 1e-12))
        out["rms_dbfs"] = float(20 * np.log10(rms_val + 1e-12))
    else:
        out["max_amp"] = peak
        out["rms"] = rms_val
    
    # 頻譜特徵
    N = len(y_seg)
    if N == 0:
        freqs = np.array([])
        Y = np.array([])
    else:
        Y = np.abs(fft(y_seg))[:N // 2]
        freqs = fftfreq(N, 1 / sr)[:N // 2]
    
    out["spectral_centroid"] = float(
        np.mean(librosa.feature.spectral_centroid(y=y_seg, sr=sr))
    ) if N else np.nan
    
    # Sharpness（基於能量分布）
    total_energy = float(np.sum(Y) + 1e-12)
    ear_mask = (freqs >= 1000) & (freqs <= 5000)
    high_mask = (freqs > 3000)
    ear_energy = float(np.sum(Y[ear_mask])) if len(Y) > 0 else 0.0
    high_energy = float(np.sum(Y[high_mask])) if len(Y) > 0 else 0.0
    loudness_sone = 10.0 * (ear_energy / total_energy) if total_energy > 0 else 0.0
    out["sharpness_hfxloud"] = (
        (high_energy / total_energy) * loudness_sone if total_energy > 0 else 0.0
    )
    
    # ZCR（過零率）
    out["zcr"] = float(np.mean(librosa.feature.zero_crossing_rate(y_seg)[0])) if N else np.nan
    
    # 頻帶特徵
    band_order = [(i, i + 1) for i in range(0, 8)]
    for lo, hi in band_order:
        lo_hz, hi_hz = lo * band_step_hz, hi * band_step_hz
        key_base = f"band_{lo}k_{hi}k"
        mask = (freqs >= lo_hz) & (freqs < hi_hz)
        
        if np.any(mask):
            local = np.where(mask)[0]
            idx = local[np.argmax(Y[mask])]
            out[f"{key_base}_peak_freq"] = float(freqs[idx])
            out[f"{key_base}_peak_amp"] = float(Y[idx])
        else:
            out[f"{key_base}_peak_freq"] = np.nan
            out[f"{key_base}_peak_amp"] = np.nan
    
    # MFCC（13 係數）
    if N > 0:
        mfccs = librosa.feature.mfcc(y=y_seg, sr=sr, n_mfcc=13)
        out.update({f"mfcc{i+1}": float(np.mean(mfccs[i])) for i in range(13)})
    else:
        out.update({f"mfcc{i+1}": np.nan for i in range(13)})
    
    return out


# =============================================================================
# 完整工作流
# =============================================================================

def process_audio_analysis(config: AudioAnalysisConfig) -> Dict[str, Any]:
    """完整的音頻分析工作流（單一影片）
    
    流程：
    1. 驗證影片文件
    2. 提取音訊
    3. 檢測擊球峰值
    4. 估計背景噪聲
    5. 逐段提取特徵（原始和去噪）
    6. 生成摘要 CSV
    7. 返回詳細結果
    
    Args:
        config: AudioAnalysisConfig 配置
        
    Returns:
        {'status': 'success', 'video': str, 'hits_detected': int,
         'raw_summary_path': str, 'denoised_summary_path': str, 'elapsed_time': float}
    """
    _check_dependencies()
    
    print("\n" + "="*80)
    print("🔊 步驟 3/6：Audio Analysis and Classification")
    print("="*80)
    print(f"影片路徑：{config.video_path}")
    print(f"輸出目錄：{config.output_dir}")
    
    Path(config.output_dir).mkdir(parents=True, exist_ok=True)
    start_time = ti.time()
    
    video_path = config.video_path
    video_name = Path(video_path).stem
    
    print(f"✅ 開始處理：{video_name}")
    
    # 1. 提取音訊
    audio_path = os.path.join(config.output_dir, f"{video_name}_audio.wav")
    try:
        extract_audio_from_video(video_path, audio_path, sr=48000)
        print(f"✅ 已提取音訊：{audio_path}")
    except Exception as e:
        print(f"❌ 無法提取音訊：{e}")
        raise
    
    # 2. 讀取音訊
    try:
        y_float, sr = librosa.load(audio_path, sr=None)
        print(f"✅ 已讀取音訊：{sr} Hz, {len(y_float)} 樣本")
    except Exception as e:
        print(f"❌ 無法讀取音訊：{e}")
        raise
    
    # 3. 檢測峰值
    print("🔍 檢測擊球峰值...")
    peak_samples, frame_ctx = dynamic_peak_detection(
        y_float, sr,
        win_sec=config.rms_frame_sec,
        hop_sec=config.rms_hop_sec,
        k=config.mad_k,
        min_dist_sec=config.min_dist_sec
    )
    
    peak_samples = filter_top_peaks_by_strength(
        peak_samples, y_float, sr,
        rel_thresh=config.peak_rel_strength,
        search_win_sec=config.search_win_sec
    )
    
    peaks_sec = (peak_samples / sr).astype(float)
    print(f"✅ 檢測到 {len(peaks_sec)} 個峰值")
    
    if len(peaks_sec) == 0:
        print("⚠️ 未偵測到擊球峰值")
        return {
            "status": "no_peaks",
            "video": video_name,
            "hits_detected": 0,
            "elapsed_time": ti.time() - start_time,
        }
    
    # 4. 篩選最接近目標時間的峰
    peaks_sec_arr = np.asarray(peaks_sec, dtype=float)
    best_idx = int(np.argmin(np.abs(peaks_sec_arr - config.target_hit_sec)))
    best_peak = float(peaks_sec_arr[best_idx])
    best_dt = abs(best_peak - config.target_hit_sec)
    
    print(f"最近峰值：{best_peak:.3f} s（目標 {config.target_hit_sec:.1f} s，誤差 {best_dt:.3f} s）")
    
    if best_dt > config.target_tol_sec:
        print(f"⚠️ 誤差超過 {config.target_tol_sec} s，視為未偵測到擊球")
        return {
            "status": "peak_out_of_range",
            "video": video_name,
            "hits_detected": 0,
            "elapsed_time": ti.time() - start_time,
        }
    
    peaks_sec = np.array([best_peak], dtype=float)
    
    # 5. 背景估計
    rms_series, _, n_fft, hop_samp = frame_ctx
    bg_mask, bg_thr = pick_background_mask(rms_series, percentile=config.bg_percentile)
    noise_mag_ref = estimate_noise_spectrum(y_float, sr, bg_mask, n_fft, hop_samp)
    print(f"✅ 背景估計完成（RMS 門檻 = {bg_thr:.6f}）")
    
    # 6. 創建段輸出目錄
    segments_dir = os.path.join(config.output_dir, f"segments_{video_name}")
    if os.path.exists(segments_dir):
        shutil.rmtree(segments_dir)
    os.makedirs(segments_dir, exist_ok=True)
    
    # 7. 逐段處理
    all_rows_raw, all_rows_den = [], []
    
    for i, peak_t in enumerate(peaks_sec, start=1):
        print(f"\n處理擊球段 {i}/{len(peaks_sec)}...")
        
        s_idx = int(max(0, (peak_t - config.pre_time_sec) * sr))
        e_idx = int(min(len(y_float), (peak_t + config.post_time_sec) * sr))
        y_hit_raw = y_float[s_idx:e_idx]
        
        # 背景片段
        bg_a = max(0, int((peak_t - 0.6) * sr))
        bg_b = min(len(y_float), int((peak_t - 0.4) * sr))
        if (bg_b - bg_a) >= int(0.05 * sr):
            y_bg_raw = y_float[bg_a:bg_b]
            y_bg_save = normalize_for_saving(y_bg_raw)
            bg_wav = f"{video_name}_hit_{i:02d}_bg.wav"
            sf.write(os.path.join(segments_dir, bg_wav), y_bg_save, sr)
        else:
            y_bg_raw = None
            bg_wav = ""
        
        # 去噪
        y_den_raw = spectral_subtraction(
            y_hit_raw, sr, noise_mag_ref, n_fft, hop_samp,
            beta=config.ss_beta, floor=config.ss_floor
        )
        
        # 保存音訊
        if config.save_segment_audio:
            y_hit_save = normalize_for_saving(y_hit_raw)
            y_den_save = normalize_for_saving(y_den_raw)
            
            hit_wav = f"{video_name}_hit_{i:02d}.wav"
            den_wav = f"{video_name}_hit_{i:02d}_den.wav"
            sf.write(os.path.join(segments_dir, hit_wav), y_hit_save, sr)
            sf.write(os.path.join(segments_dir, den_wav), y_den_save, sr)
            print(f"  ✅ 已保存音訊：{hit_wav}, {den_wav}")
        else:
            hit_wav = ""
            den_wav = ""
        
        # 提取特徵
        feats_raw = compute_audio_features(y_hit_raw, sr, config.loudness_mode)
        feats_den = compute_audio_features(y_den_raw, sr, config.loudness_mode)
        
        # 構建行記錄
        base = {
            "title": video_name,
            "idx": i,
            "start_time": s_idx / sr,
            "end_time": e_idx / sr,
            "peak_time": float(peak_t),
            "audio_file": hit_wav,
            "bg_file": bg_wav,
            "denoised_file": den_wav,
        }
        
        row_raw = dict(base)
        row_raw.update(feats_raw)
        row_den = dict(base)
        row_den.update(feats_den)
        
        all_rows_raw.append(row_raw)
        all_rows_den.append(row_den)
    
    # 8. 生成摘要 CSV
    raw_df = pd.DataFrame(all_rows_raw) if all_rows_raw else pd.DataFrame()
    den_df = pd.DataFrame(all_rows_den) if all_rows_den else pd.DataFrame()
    
    raw_path = os.path.join(config.output_dir, f"{video_name}_raw_summary.csv")
    den_path = os.path.join(config.output_dir, f"{video_name}_denoised_summary.csv")
    
    if config.output_raw_csv and not raw_df.empty:
        raw_df.to_csv(raw_path, index=False)
        print(f"📄 已保存原始摘要：{raw_path}")
    
    if not den_df.empty:
        den_df.to_csv(den_path, index=False)
        print(f"📄 已保存去噪摘要：{den_path}")
    
    elapsed = ti.time() - start_time
    
    print("\n" + "="*80)
    print(f"✅ 完成，耗時：{elapsed:.2f} 秒")
    print(f"   影片：{video_name}")
    print(f"   擊球段數：{len(all_rows_den)}")
    print("="*80)
    
    return {
        "status": "success",
        "video": video_name,
        "hits_detected": len(all_rows_den),
        "raw_summary_path": raw_path if config.output_raw_csv else None,
        "denoised_summary_path": den_path,
        "segments_dir": segments_dir,
        "elapsed_time": elapsed,
    }


# =============================================================================
# 公開 API
# =============================================================================

def run_audio_analysis(config: Optional[AudioAnalysisConfig] = None) -> Dict[str, Any]:
    """Audio Analysis 的命令行和程序入口（單一影片處理）
    
    如果未提供配置，使用默認值。
    
    Args:
        config: AudioAnalysisConfig 配置，或 None 使用默認值
        
    Returns:
        {'status': str, 'video': str, 'hits_detected': int,
         'denoised_summary_path': str, 'elapsed_time': float}
        
    使用示例：
        config = AudioAnalysisConfig(
            video_path="path/to/video.mp4",
            output_dir="path/to/output",
            loudness_mode="dbfs"
        )
        result = run_audio_analysis(config)
    """
    if config is None:
        config = AudioAnalysisConfig()
    
    try:
        result = process_audio_analysis(config)
        return result
    except Exception as e:
        print(f"\n❌ 錯誤：{e}")
        raise


# =============================================================================
# 主函數（測試用）
# =============================================================================

if __name__ == "__main__":
    # 測試配置：處理單一影片
    config = AudioAnalysisConfig(
        video_path=r"\\10.1.1.101\TekSwing\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip_stabilized.mp4",
        output_dir=r"\\10.1.1.101\TekSwing\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41"
    )
    result = run_audio_analysis(config)
    print(result)
