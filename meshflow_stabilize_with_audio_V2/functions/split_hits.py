"""
步驟1：Split Hits from CSV and Video
功能：根據IMU加速度偵測擊球時間點，切分影片和CSV數據

此模組提供完整的擊球檢測和視頻切分功能，包括：
- CSV 數據加載和預處理
- 基於加速度的擊球時間檢測
- 影片和 CSV 段落切分
- 加速度圖形可視化
"""

from __future__ import annotations
from typing import Optional, Tuple, List, Dict
import subprocess
import numpy as np
import pandas as pd
from scipy.signal import find_peaks
from pathlib import Path
from datetime import datetime

# 可選的導入
try:
    from moviepy import VideoFileClip
    MOVIEPY_AVAILABLE = True
except ImportError:
    MOVIEPY_AVAILABLE = False
    print("警告：moviepy 不可用，視頻相關功能將被禁用")

try:
    import matplotlib.pyplot as plt
    MATPLOTLIB_AVAILABLE = True
except ImportError:
    MATPLOTLIB_AVAILABLE = False
    print("警告：matplotlib 不可用，圖表相關功能將被禁用")


# ==================== 配置類 ====================
class SplitHitsConfig:
    """擊球檢測和切分的配置"""
    
    def __init__(
        self,
        base_dir: str = r"\\10.1.1.101\TekSwing\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\d474e14c-fe9a-4078-9eff-a22928ef14fb",
        out_dir_name: str = "cut",
        detect_from: str = "Codi2",
        window_sec_before: float = 3.0,
        window_sec_after: float = 3.0,
        smooth_win_sec: float = 0.05,
        thresh_acc_g: float = 20.0,
        min_swing_interval: float = 1.0,
        peak_prominence_g: Optional[float] = None,
        plot_acc_mag: bool = True,
        plot_save: bool = True,
        plot_show: bool = False,
        plot_dpi: int = 200,
        ffmpeg_crf: str = "18",
        ffmpeg_preset: str = "veryfast",
        force_sar_1: bool = True,
    ):
        """初始化配置"""
        self.base_dir = Path(base_dir)
        self.video_path = self.base_dir / f"original.mp4"
        self.csv_codi1 = self.base_dir / f"chest.csv"
        self.csv_codi2 = self.base_dir / f"right_wrist.csv"
        
        self.out_dir_name = out_dir_name
        self.detect_from = detect_from
        self.window_sec_before = window_sec_before
        self.window_sec_after = window_sec_after
        self.smooth_win_sec = smooth_win_sec
        self.thresh_acc_g = thresh_acc_g
        self.min_swing_interval = min_swing_interval
        self.peak_prominence_g = peak_prominence_g
        
        self.plot_acc_mag = plot_acc_mag
        self.plot_save = plot_save
        self.plot_show = plot_show
        self.plot_dpi = plot_dpi
        
        self.ffmpeg_crf = ffmpeg_crf
        self.ffmpeg_preset = ffmpeg_preset
        self.force_sar_1 = force_sar_1


# ==================== 核心函數 ====================

def make_unique_outdir(base_dir: Path, name: str) -> Path:
    """
    創建唯一的輸出目錄
    
    Args:
        base_dir: 基礎目錄
        name: 目錄名稱
        
    Returns:
        創建或找到的目錄路徑
    """
    out_dir = base_dir / name
    if not out_dir.exists():
        out_dir.mkdir(parents=True, exist_ok=True)
        return out_dir
    if out_dir.is_dir() and not any(out_dir.iterdir()):
        return out_dir
    
    for i in range(1, 100):
        cand = base_dir / f"{name}_{i:02d}"
        if not cand.exists():
            cand.mkdir(parents=True, exist_ok=True)
            return cand
    
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    cand = base_dir / f"{name}_{ts}"
    cand.mkdir(parents=True, exist_ok=True)
    return cand


def load_codi_raw_v1_csv(path: Path) -> pd.DataFrame:
    """
    加載 CODI RAW V1 格式的 CSV 檔案
    
    支援以下格式：
      CODI_RAW_V1
      Device:...
      ElapsedSec,QuatI,...,AccelZ
      ...
    
    Args:
        path: CSV 檔案路徑
        
    Returns:
        包含 IMU 數據的 DataFrame
        
    Raises:
        FileNotFoundError: 如果檔案不存在
        ValueError: 如果找不到適當的標題行
    """
    if not path.exists():
        raise FileNotFoundError(f"找不到 CSV：{path}")

    header_idx = None
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i in range(80):
            line = f.readline()
            if not line:
                break
            s = line.strip()
            if s.startswith("ElapsedSec,") and "AccelX" in s and "AccelY" in s and "AccelZ" in s:
                header_idx = i
                break

    if header_idx is None:
        raise ValueError(f"無法在 {path.name} 前 80 行找到 header（ElapsedSec, ... AccelZ）")

    return pd.read_csv(path, skiprows=header_idx)


def normalize_time(df: pd.DataFrame) -> pd.DataFrame:
    """
    標準化時間欄位，使其從 0 開始
    
    Args:
        df: 包含 ElapsedSec 欄位的 DataFrame
        
    Returns:
        添加了 Time 欄位的 DataFrame（從 0 開始的相對時間）
        
    Raises:
        KeyError: 如果缺少 ElapsedSec 欄位
    """
    if "ElapsedSec" not in df.columns:
        raise KeyError(f"CSV 缺少 ElapsedSec 欄位：{df.columns.tolist()}")
    
    df = df.copy()
    df["ElapsedSec"] = df["ElapsedSec"].astype(float)
    df["Time"] = df["ElapsedSec"] - float(df["ElapsedSec"].iloc[0])
    return df


def acc_magnitude(df: pd.DataFrame) -> np.ndarray:
    """
    計算加速度的幅度 sqrt(Ax^2 + Ay^2 + Az^2)
    
    Args:
        df: 包含 AccelX, AccelY, AccelZ 欄位的 DataFrame
        
    Returns:
        加速度幅度的 numpy 陣列
        
    Raises:
        KeyError: 如果缺少加速度欄位
    """
    need = ["AccelX", "AccelY", "AccelZ"]
    miss = [c for c in need if c not in df.columns]
    if miss:
        raise KeyError(f"CSV 缺少欄位：{miss}\n目前欄位：{df.columns.tolist()}")
    
    ax = df["AccelX"].astype(float).values
    ay = df["AccelY"].astype(float).values
    az = df["AccelZ"].astype(float).values
    return np.sqrt(ax**2 + ay**2 + az**2)


def detect_swings_from_df(
    df: pd.DataFrame,
    smooth_win_sec: float = 0.05,
    thresh_acc_g: float = 20.0,
    min_swing_interval: float = 1.0,
    peak_prominence_g: Optional[float] = None,
) -> Tuple[np.ndarray, np.ndarray]:
    """
    從 IMU 加速度數據中偵測擊球時間
    
    Args:
        df: 包含 Time 和 AccelX/Y/Z 的 DataFrame
        smooth_win_sec: 平滑窗口的時間長度（秒）
        thresh_acc_g: 加速度閾值（g）
        min_swing_interval: 最小擊球間距（秒）
        peak_prominence_g: 峰值突出度（可選）
        
    Returns:
        (hit_times, hit_heights) - 擊球時間和峰值高度
        
    Raises:
        KeyError: 如果缺少必要的欄位
    """
    if "Time" not in df.columns:
        raise KeyError("缺少 Time 欄位，請先調用 normalize_time()")

    t = df["Time"].astype(float).values
    acc_mag = acc_magnitude(df)

    # 估計採樣間隔
    if len(t) > 1 and (t.max() - t.min()) > 0:
        dt_est = (t.max() - t.min()) / (len(t) - 1)
    else:
        dt_est = 1.0 / 200.0

    # 平滑加速度
    win_samples = max(1, int(smooth_win_sec / dt_est))
    acc_smooth = (
        pd.Series(acc_mag)
        .rolling(win_samples, center=True)
        .mean()
        .bfill()
        .ffill()
        .values
    )

    # 偵測峰值
    min_dist_samples = max(1, int(min_swing_interval / dt_est))
    peak_kwargs = dict(height=thresh_acc_g, distance=min_dist_samples)
    if peak_prominence_g is not None:
        peak_kwargs["prominence"] = peak_prominence_g

    peaks, _ = find_peaks(acc_smooth, **peak_kwargs)
    hit_times = t[peaks]
    hit_heights = acc_smooth[peaks]

    order = np.argsort(hit_times)
    return hit_times[order], hit_heights[order]


def plot_acc_mag(
    df: pd.DataFrame,
    title: str,
    save_path: Optional[Path] = None,
    hit_times: Optional[np.ndarray] = None,
    plot_show: bool = False,
    plot_dpi: int = 200,
) -> None:
    """
    繪製加速度幅度圖形
    
    Args:
        df: 包含 Time 和加速度欄位的 DataFrame
        title: 圖形標題
        save_path: 保存路徑（如果為 None 則不保存）
        hit_times: 擊球時間點（可選，將在圖上顯示）
        plot_show: 是否顯示圖形
        plot_dpi: 圖形 DPI
    """
    if not MATPLOTLIB_AVAILABLE:
        print("⚠️  matplotlib 不可用，跳過圖表生成")
        return
    
    t = df["Time"].astype(float).values
    acc_mag = acc_magnitude(df)

    plt.figure(figsize=(16, 6))
    plt.plot(t, acc_mag, linewidth=1.5)
    
    if hit_times is not None:
        for th in hit_times:
            plt.axvline(float(th), linestyle="--", alpha=0.4, color='red')
    
    plt.title(title, fontsize=14, fontweight='bold')
    plt.xlabel("Time (s)", fontsize=12)
    plt.ylabel("|acc| (g)", fontsize=12)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()

    if save_path is not None:
        plt.savefig(str(save_path), dpi=plot_dpi)
        print(f"   📊 已保存圖形：{save_path.name}")
    
    if plot_show:
        plt.show()
    
    plt.close()


def cut_csv_segment(
    df: pd.DataFrame,
    start_t: float,
    end_t: float,
    t_hit: float,
) -> pd.DataFrame:
    """
    切分 CSV 數據段落
    
    Args:
        df: 原始 DataFrame
        start_t: 開始時間
        end_t: 結束時間
        t_hit: 擊球時間（用於計算相對時間）
        
    Returns:
        切分後的 DataFrame，包含相對時間欄位 Time_rel
    """
    seg = df[(df["Time"] >= start_t) & (df["Time"] <= end_t)].copy()
    seg["Time_rel"] = seg["Time"] - t_hit
    return seg


def cut_video_ffmpeg(
    src: Path,
    dst: Path,
    start_t: float,
    end_t: float,
    ffmpeg_preset: str = "veryfast",
    ffmpeg_crf: str = "18",
    force_sar_1: bool = True,
) -> None:
    """
    使用 ffmpeg 切分視頻
    
    Args:
        src: 源視頻路徑
        dst: 目標視頻路徑
        start_t: 開始時間（秒）
        end_t: 結束時間（秒）
        ffmpeg_preset: ffmpeg preset (ultrafast/superfast/veryfast/faster/fast/medium...)
        ffmpeg_crf: 品質參數 (18~23)
        force_sar_1: 是否強制設置 SAR=1 以避免變形
        
    Raises:
        FileNotFoundError: 如果找不到視頻或 ffmpeg
        RuntimeError: 如果 ffmpeg 執行失敗
    """
    if not src.exists():
        raise FileNotFoundError(f"找不到影片：{src}")

    dur = max(0.001, float(end_t) - float(start_t))

    vf = []
    if force_sar_1:
        vf.append("setsar=1")
    vf_str = ",".join(vf) if vf else None

    cmd = [
        "ffmpeg", "-y",
        "-ss", f"{start_t:.6f}",
        "-i", str(src),
        "-t", f"{dur:.6f}",
    ]

    if vf_str:
        cmd += ["-vf", vf_str]

    cmd += [
        "-c:v", "libx264",
        "-preset", ffmpeg_preset,
        "-crf", str(ffmpeg_crf),
        "-c:a", "aac",
        "-movflags", "+faststart",
        str(dst),
    ]

    try:
        subprocess.run(cmd, check=True, capture_output=True)
    except FileNotFoundError:
        raise RuntimeError("找不到 ffmpeg：請先安裝並確認 ffmpeg 在 PATH")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"ffmpeg 切片失敗（returncode={e.returncode}）")


# ==================== 主處理函數 ====================

def process_split_hits(config: SplitHitsConfig) -> Dict:
    """
    執行完整的擊球檢測和切分流程
    
    Args:
        config: SplitHitsConfig 配置對象
        
    Returns:
        包含結果和統計的字典
        
    Raises:
        FileNotFoundError: 如果缺少必要的輸入檔案
    """
    # 驗證輸入檔案
    if not config.video_path.exists():
        raise FileNotFoundError(f"找不到影片：{config.video_path}")
    
    csv_path = config.csv_codi2 if config.detect_from.lower() == "codi2" else config.csv_codi1
    if not csv_path.exists():
        raise FileNotFoundError(f"找不到 CSV：{csv_path}")

    # 加載和預處理 CSV
    print(f"📄 加載 CSV：{csv_path.name}")
    df = normalize_time(load_codi_raw_v1_csv(csv_path))
    
    # 創建輸出目錄
    out_dir = make_unique_outdir(config.video_path.parent, config.out_dir_name)
    
    print(f"🎬 VIDEO: {config.video_path}")
    print(f"📄 CSV ({config.detect_from}): {csv_path}")
    print(f"📦 OUTPUT: {out_dir}")

    # 偵測擊球
    print("\n🔎 偵測擊球中...")
    hit_times, hit_heights = detect_swings_from_df(
        df,
        smooth_win_sec=config.smooth_win_sec,
        thresh_acc_g=config.thresh_acc_g,
        min_swing_interval=config.min_swing_interval,
        peak_prominence_g=config.peak_prominence_g,
    )
    
    print(f"✅ 偵測到 {len(hit_times)} 次擊球")
    if len(hit_times) > 0:
        print(f"   時間點：{np.array2string(hit_times, precision=3, separator=', ')}")

    if len(hit_times) == 0:
        print("⚠️  沒有偵測到峰值，請調整參數")
        return {
            "success": False,
            "hit_count": 0,
            "output_dir": str(out_dir),
        }

    # 繪製加速度圖
    if config.plot_acc_mag:
        print("\n📊 繪製加速度圖...")
        plot_path = out_dir / f"IMU_{config.detect_from}_AccelMag.png" if config.plot_save else None
        plot_acc_mag(
            df,
            f"IMU {config.detect_from} - Acceleration Magnitude",
            plot_path,
            hit_times,
            config.plot_show,
            config.plot_dpi,
        )

    # 獲取視頻時長
    print("\n🎥 獲取視頻信息...")
    if MOVIEPY_AVAILABLE:
        clip = VideoFileClip(str(config.video_path))
        video_duration = float(clip.duration)
        clip.close()
        print(f"   長度：{video_duration:.3f} s")
    else:
        print("⚠️  moviepy 不可用，跳過視頻時長檢測")
        print("   假設視頻長度足夠...")
        video_duration = float(1e6)  # 假設很長的視頻

    # 切分擊球段落
    print(f"\n✂️  切分 {len(hit_times)} 個擊球段落...\n")
    summary = []
    
    for idx, (t_hit, h) in enumerate(zip(hit_times, hit_heights), start=1):
        start_t = max(0.0, float(t_hit) - config.window_sec_before)
        end_t = min(video_duration, float(t_hit) + config.window_sec_after)

        tag = f"hit_{idx:03d}"
        
        # 切分視頻
        mp4_out = out_dir / f"{tag}.mp4"
        print(f"🎬 [{tag}] {start_t:.3f}~{end_t:.3f}s (center {t_hit:.3f}s)")
        cut_video_ffmpeg(
            config.video_path,
            mp4_out,
            start_t,
            end_t,
            config.ffmpeg_preset,
            config.ffmpeg_crf,
            config.force_sar_1,
        )

        # 切分 CSV
        seg = cut_csv_segment(df, start_t, end_t, float(t_hit))
        csv_out = out_dir / f"{tag}_{config.detect_from}.csv"
        seg.to_csv(csv_out, index=False, encoding="utf-8-sig")
        print(f"   ✅ 保存：{tag}.mp4 ({seg.shape[0]} rows CSV)")

        summary.append({
            "hit": tag,
            "t_hit": float(t_hit),
            "start_t": float(start_t),
            "end_t": float(end_t),
            "peak_smooth": float(h),
            "detect_from": config.detect_from,
        })

    # 保存摘要
    summary_df = pd.DataFrame(summary)
    summary_path = out_dir / "hits_summary.csv"
    summary_df.to_csv(summary_path, index=False, encoding="utf-8-sig")

    print(f"\n✅ 完成切分：{out_dir}")
    print(f"   - 擊球段落：{len(hit_times)} 個")
    print(f"   - 摘要文件：{summary_path.name}")
    
    return {
        "success": True,
        "hit_count": len(hit_times),
        "output_dir": str(out_dir),
        "summary": summary_df,
    }


# ==================== 公開 API ====================

def run_split_hits(config: Optional[SplitHitsConfig] = None) -> Dict:
    """
    執行 split hits 步驟（命令行入口）
    
    Args:
        config: 配置對象（如果為 None 使用默認值）
        
    Returns:
        處理結果字典
    """
    print("\n" + "="*80)
    print("📊 步驟 1/6：Split Hits from CSV and Video")
    print("="*80)
    print("功能：根據IMU加速度偵測擊球，切分影片和CSV數據\n")
    
    try:
        if config is None:
            config = SplitHitsConfig()
        
        result = process_split_hits(config)
        
        if result["success"]:
            print("\n✅ Split Hits 完成")
        else:
            print("\n⚠️  Split Hits 完成，但沒有檢測到擊球")
        
        return result
        
    except Exception as e:
        print(f"\n❌ 錯誤：{e}")
        raise


if __name__ == "__main__":
    result = run_split_hits()
    print(f"\n結果：{result}")
