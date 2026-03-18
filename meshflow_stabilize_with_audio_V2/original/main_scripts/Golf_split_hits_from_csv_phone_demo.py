from __future__ import annotations

from typing import Optional
import subprocess
import numpy as np
import pandas as pd
from scipy.signal import find_peaks
from moviepy.editor import VideoFileClip
from pathlib import Path
from datetime import datetime

# === 新增：畫圖 ===
import matplotlib.pyplot as plt

# ================= 使用者設定 =================


REC_TS = "20251231100806"
BASE_DIR = Path(r"Z:\Data\golf\20260126") 

VIDEO_PATH = BASE_DIR / f"REC_{REC_TS}.mp4"
CSV_CODI1  = BASE_DIR / f"REC_{REC_TS}_CHEST.csv"
CSV_CODI2  = BASE_DIR / f"REC_{REC_TS}_RIGHT_WRIST.csv"  # RIGHT_WRIST -> Codi2


OUT_DIR_NAME = "cut"
DETECT_FROM = "Codi2"  # "Codi1" or "Codi2"

WINDOW_SEC_BEFORE = 3.0
WINDOW_SEC_AFTER  = 3.0

SMOOTH_WIN_SEC     = 0.05
THRESH_ACC_G       = 20.0
MIN_SWING_INTERVAL = 1.0

# ✅ prominence：越大越嚴格（峰越少）
PEAK_PROMINENCE_G = None  # e.g. 0.2 / 0.3 / 0.5；不用就 None

# === 畫 |acc| 圖 ===
PLOT_ACC_MAG = True
PLOT_SAVE    = True
PLOT_SHOW    = False
PLOT_DPI     = 200

# === ffmpeg 切片參數（可自行調整）===
FFMPEG_CRF    = "18"          # 越小越清晰、檔案越大（18~23 常用）
FFMPEG_PRESET = "veryfast"    # ultrafast/superfast/veryfast/faster/fast/medium...
FORCE_SAR_1   = True          # ✅ 強制 setsar=1，修正變形常見原因

# =================================================


def make_unique_outdir(base_dir: Path, name: str) -> Path:
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
    支援：
      CODI_RAW_V1
      Device:...
      ElapsedSec,QuatI,...,AccelZ
      ...
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
    if "ElapsedSec" not in df.columns:
        raise KeyError(f"CSV 缺少 ElapsedSec 欄位：{df.columns.tolist()}")
    df = df.copy()
    df["ElapsedSec"] = df["ElapsedSec"].astype(float)
    df["Time"] = df["ElapsedSec"] - float(df["ElapsedSec"].iloc[0])
    return df


def acc_magnitude(df: pd.DataFrame) -> np.ndarray:
    need = ["AccelX", "AccelY", "AccelZ"]
    miss = [c for c in need if c not in df.columns]
    if miss:
        raise KeyError(f"CSV 缺少欄位：{miss}\n目前欄位：{df.columns.tolist()}")
    ax = df["AccelX"].astype(float).values
    ay = df["AccelY"].astype(float).values
    az = df["AccelZ"].astype(float).values
    return np.sqrt(ax**2 + ay**2 + az**2)


def detect_swings_from_df(df: pd.DataFrame):
    """從 df 的 AccelX/Y/Z 偵測擊球時間（Time, 秒）。"""
    if "Time" not in df.columns:
        raise KeyError("缺少 Time 欄位，請先 normalize_time()")

    t = df["Time"].astype(float).values
    acc_mag = acc_magnitude(df)

    if len(t) > 1 and (t.max() - t.min()) > 0:
        dt_est = (t.max() - t.min()) / (len(t) - 1)
    else:
        dt_est = 1.0 / 200.0

    win_samples = max(1, int(SMOOTH_WIN_SEC / dt_est))
    acc_smooth = (
        pd.Series(acc_mag)
        .rolling(win_samples, center=True)
        .mean()
        .bfill()
        .ffill()
        .values
    )

    min_dist_samples = max(1, int(MIN_SWING_INTERVAL / dt_est))
    peak_kwargs = dict(height=THRESH_ACC_G, distance=min_dist_samples)
    if PEAK_PROMINENCE_G is not None:
        peak_kwargs["prominence"] = PEAK_PROMINENCE_G

    peaks, _ = find_peaks(acc_smooth, **peak_kwargs)
    hit_times = t[peaks]
    hit_heights = acc_smooth[peaks]

    order = np.argsort(hit_times)
    return hit_times[order], hit_heights[order]


def plot_acc_mag(df: pd.DataFrame, title: str, save_path: Optional[Path], hit_times=None):
    t = df["Time"].astype(float).values
    acc_mag = acc_magnitude(df)

    plt.figure(figsize=(16, 6))
    plt.plot(t, acc_mag)
    if hit_times is not None:
        for th in hit_times:
            plt.axvline(float(th), linestyle="--", alpha=0.4)
    plt.title(title)
    plt.xlabel("Time (s)")
    plt.ylabel("|acc| (g)")
    plt.grid(True)
    plt.tight_layout()

    if save_path is not None:
        plt.savefig(str(save_path), dpi=PLOT_DPI)
    if PLOT_SHOW:
        plt.show()
    plt.close()


def cut_csv_segment(df: pd.DataFrame, start_t: float, end_t: float, t_hit: float) -> pd.DataFrame:
    seg = df[(df["Time"] >= start_t) & (df["Time"] <= end_t)].copy()
    seg["Time_rel"] = seg["Time"] - t_hit
    return seg


def cut_video_ffmpeg(src: Path, dst: Path, start_t: float, end_t: float):
    """
    ✅ 解法 B：用 ffmpeg 切片，並強制修正 SAR 避免輸出長寬比變形
    - 精準切：-ss 放在 -i 後（會重編碼）
    """
    if not src.exists():
        raise FileNotFoundError(f"找不到影片：{src}")

    dur = max(0.001, float(end_t) - float(start_t))

    vf = []
    if FORCE_SAR_1:
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
        "-preset", FFMPEG_PRESET,
        "-crf", str(FFMPEG_CRF),
        "-c:a", "aac",
        "-movflags", "+faststart",
        str(dst),
    ]

    try:
        subprocess.run(cmd, check=True)
    except FileNotFoundError:
        raise RuntimeError("找不到 ffmpeg：請先安裝並確認 ffmpeg 在 PATH（cmd 能跑 ffmpeg -version）")
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"ffmpeg 切片失敗（returncode={e.returncode}）")


def main():
    if not VIDEO_PATH.exists():
        raise FileNotFoundError(f"找不到影片：{VIDEO_PATH}")
    if not CSV_CODI2.exists():
        raise FileNotFoundError(f"找不到 CSV：{CSV_CODI2}")

    df2 = normalize_time(load_codi_raw_v1_csv(CSV_CODI2))
    out_dir = make_unique_outdir(VIDEO_PATH.parent, OUT_DIR_NAME)

    print(f"🎬 VIDEO: {VIDEO_PATH}")
    print(f"📄 Codi2(RIGHT_WRIST): {CSV_CODI2}")
    print(f"📦 OUT: {out_dir}")

    print("🔎 偵測擊球中...")
    df_detect = df2  # 目前你只開 Codi2
    hit_times, hit_heights = detect_swings_from_df(df_detect)
    print(f"✅ 偵測到 {len(hit_times)} 次：{np.array2string(hit_times, precision=3, separator=', ')}")

    if len(hit_times) == 0:
        print("（沒有偵測到峰值，請調 THRESH_ACC_G / PEAK_PROMINENCE_G / MIN_SWING_INTERVAL）")
        return

    # === 畫綜合加速度圖 ===
    if PLOT_ACC_MAG:
        p2 = (out_dir / "IMU_Codi2_AccelMag.png") if PLOT_SAVE else None
        plot_acc_mag(df2, "IMU Codi2 - Acceleration Magnitude", p2,
                     hit_times if DETECT_FROM.lower() == "codi2" else None)
        print("📈 已輸出 |acc| 圖（PNG）")

    # 只拿 duration 來 clamp 時間（不拿來輸出影片，避免 MoviePy 變形問題）
    clip = VideoFileClip(str(VIDEO_PATH))
    video_duration = float(clip.duration)
    clip.close()
    print(f"⏱️ 影片長度：{video_duration:.3f} s")

    summary = []
    for idx, (t_hit, h) in enumerate(zip(hit_times, hit_heights), start=1):
        start_t = max(0.0, float(t_hit) - WINDOW_SEC_BEFORE)
        end_t   = min(video_duration, float(t_hit) + WINDOW_SEC_AFTER)

        tag = f"hit_{idx:03d}"
        mp4_out = out_dir / f"{tag}.mp4"

        print(f"\n🎬 [{tag}] {start_t:.3f} ~ {end_t:.3f} (center {t_hit:.3f})")

        # ✅ 解法 B：用 ffmpeg 切影片（避免輸出變形）
        cut_video_ffmpeg(VIDEO_PATH, mp4_out, start_t, end_t)

        # CSV
        seg2 = cut_csv_segment(df2, start_t, end_t, float(t_hit))
        seg2.to_csv(out_dir / f"{tag}_Codi2.csv", index=False, encoding="utf-8-sig")
        print(f"📄 [{tag}] {tag}_Codi2.csv ({len(seg2)} rows)")

        summary.append({
            "hit": tag,
            "t_hit": float(t_hit),
            "start_t": float(start_t),
            "end_t": float(end_t),
            "peak_smooth": float(h),
            "detect_from": DETECT_FROM,
        })

    pd.DataFrame(summary).to_csv(out_dir / "hits_summary.csv", index=False, encoding="utf-8-sig")
    print(f"\n✅ 完成切分：{out_dir}")


if __name__ == "__main__":
    main()
