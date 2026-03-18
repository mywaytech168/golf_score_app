import os, glob, shutil, time as ti
import numpy as np
import pandas as pd
import librosa, soundfile as sf
from scipy.fft import fft, fftfreq
from moviepy.editor import VideoFileClip
import matplotlib.pyplot as plt
from matplotlib import rcParams
import cv2
from matplotlib.animation import FuncAnimation
from scipy.spatial.transform import Rotation as R

# =========================
# 參數設定區（可調整）
# =========================

BATCH_DIR = r'Z:\Data\golf\20260126\cut\stabilized'  # 批次處理資料夾路徑

# —— 流程開關 ——
RUN_OPENPOSE     = False   # 是否執行 OpenPose
RUN_IMU_ANIM     = False   # 是否輸出 IMU 3D 動畫
SAVE_SEGMENT_PNG = False   # 是否存每段擊球對應影像（.png）
SAVE_ANALYSIS_FIG= False   # 是否輸出波形＋頻譜分析圖（png）
OUTPUT_RAW_CSV   = False   # 是否輸出 raw_summary.csv

# —— 音量尺度（同裝置跨影片建議用 dBFS） ——
# 'dbfs'：輸出 peak_dbfs / rms_dbfs；'raw'：輸出 max_amp / rms（0~1 尺度，不縮放）
LOUDNESS_MODE = 'dbfs'

# —— 偵測/切片參數 ——
PEAK_REL_STRENGTH = 0.8    # 只保留 >= 最大強度 80% 的峰
SEARCH_WIN_SEC    = 0.01   # 峰強度評估的 ±時間窗 (秒)
RMS_FRAME_SEC     = 0.02   # RMS 框長
RMS_HOP_SEC       = 0.01   # RMS hop
MAD_K             = 4.0    # RMS+MAD 門檻倍率
MIN_DIST_SEC      = 0.35   # 最小擊球間距 (秒)
PRE_TIME          = 0.10   # 擊球前取樣時長 (秒)
POST_TIME         = 0.10   # 擊球後取樣時長 (秒)

# —— 多峰處理：只取最接近目標時間的一筆 ——
TARGET_HIT_SEC   = 3.0     # 目標擊球時間（秒）
TARGET_TOL_SEC   = 0.5     # 允許誤差（秒），必須落在 [2.5, 3.5]

# —— 背景/去噪參數 ——
BG_PERCENTILE     = 25     # 取低百分位做背景幀
SS_BETA           = 1.0    # Spectral Subtraction β
SS_FLOOR          = 1e-6   # 頻譜減法地板值

# —— 頻帶特徵參數 ——
BAND_STEP_HZ      = 1000   # 每 1000 Hz 取區間峰值
BAND_MAX_HZ       = 8000   # 頻帶特徵上限（0~8k）

# —— 跨段統計分數（0~1）尺度 —— #
AGREE_CV_TARGET   = 0.20   # 一致度：MAD/median ≈ 0.2 → 約 0.5

# —— IMU 名稱（若 RUN_IMU_ANIM=True 才會用到） ——
IMU1_NAME = "CodiRightHand"
IMU2_NAME = "CodiWaist"

# —— 其他 ——
FONT_PATH = r'C:/Windows/Fonts/msjh.ttc'
rcParams['font.family'] = 'Microsoft JhengHei'
rcParams['axes.unicode_minus'] = False

# ========================= 欄位順序（兩份彙整檔共用，無前綴） =========================
META_COLS = [
    "title","idx","start_time","end_time","peak_time",
    "audio_file","bg_file","denoised_file"
]
BAND_ORDER = [(0,1),(1,2),(2,3),(3,4),(4,5),(5,6),(6,7),(7,8)]

LOUDNESS_COLS = (["peak_dbfs","rms_dbfs"] if LOUDNESS_MODE=='dbfs' else ["max_amp","rms"])
METRIC_COLS = LOUDNESS_COLS + [
    "spectral_centroid","sharpness_hfxloud","zcr",
] + [f"band_{lo}k_{hi}k_peak_freq" for lo,hi in BAND_ORDER] \
  + [f"band_{lo}k_{hi}k_peak_amp"  for lo,hi in BAND_ORDER] \
  + [f"mfcc{i}" for i in range(1,14)]

SUMMARY_COLS = META_COLS + METRIC_COLS

# ========================= 小工具（只在寫檔用的 normalize） =========================
def normalize_for_saving(y):
    if y is None or len(y) == 0:
        return y
    y = librosa.util.normalize(y.astype(float))
    y = np.clip(y, -1.0, 1.0)
    return y

# ========================= 音訊處理工具 =========================
def frame_rms(y, sr, frame_len=0.02, hop_len=0.01):
    n_fft = int(frame_len*sr)
    hop = int(hop_len*sr)
    rms = librosa.feature.rms(y=y, frame_length=n_fft, hop_length=hop, center=True)[0]
    t = np.arange(len(rms))*hop/sr
    return rms, t, n_fft, hop

def pick_background_mask(rms, percentile=25):
    thr = np.percentile(rms, percentile)
    return rms < thr, thr

def estimate_noise_spectrum(y, sr, bg_mask, n_fft, hop):
    S = librosa.stft(y, n_fft=n_fft, hop_length=hop, window="hann", center=True)
    mag = np.abs(S)
    if bg_mask.sum() < 3:
        noise_ref = np.minimum(mag, np.percentile(mag, 20, axis=1, keepdims=True))
    else:
        noise_ref = mag[:, bg_mask].mean(axis=1, keepdims=True)
    return noise_ref

def spectral_subtraction(segment, sr, noise_mag_ref, n_fft, hop, beta=1.0, floor=1e-6):
    # 回傳 RAW（不 normalize），供特徵；寫檔時才 normalize
    S = librosa.stft(segment, n_fft=n_fft, hop_length=hop, window="hann", center=True)
    mag = np.abs(S)
    phase = np.angle(S)
    clean_mag = np.maximum(mag - beta*noise_mag_ref, floor)
    S_clean = clean_mag * np.exp(1j*phase)
    y_out = librosa.istft(S_clean, hop_length=hop, window="hann", length=len(segment))
    return y_out

# ========================= 擊球偵測 =========================
def dynamic_peak_detection(y, sr, win=0.02, hop=0.01, k=4.0, min_dist=0.35):
    rms, t, n_fft, hop_samp = frame_rms(y, sr, win, hop)
    med = np.median(rms)
    mad = np.median(np.abs(rms - med)) + 1e-12
    thr = med + k*mad

    S = np.abs(librosa.stft(y, n_fft=n_fft, hop_length=hop_samp, window="hann"))
    flux = np.diff(S, axis=1)
    flux = np.maximum(flux, 0).sum(axis=0)
    flux = np.pad(flux, (1,0))

    score_mask = (rms > thr) & (flux > np.median(flux))
    cand_idx = np.where(score_mask)[0]
    if cand_idx.size == 0:
        return np.array([], dtype=int), (rms, t, n_fft, hop_samp)

    peaks, min_hop, last = [], int(min_dist / hop), -9999
    for i in cand_idx:
        if i - last >= min_hop:
            peaks.append(i)
            last = i
    return (np.array(peaks)*hop_samp).astype(int), (rms, t, n_fft, hop_samp)

def filter_top_peaks_by_strength(peak_samples, y, sr, rel_thresh=0.99, search_win=0.01):
    if len(peak_samples) == 0:
        return peak_samples
    half_w = int(search_win * sr)
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

# ========================= 特徵（RAW，不做 normalize） =========================
def band_peak_features(freqs, yf, step_hz=1000, max_hz=8000):
    out = {}
    if len(freqs) == 0 or len(yf) == 0:
        for lo, hi in BAND_ORDER:
            out[f"band_{lo}k_{hi}k_peak_freq"] = np.nan
            out[f"band_{lo}k_{hi}k_peak_amp"]  = np.nan
        return out

    hi = int(min(max_hz, float(freqs[-1])))
    for lo in range(0, hi, step_hz):
        hi_band = lo + step_hz
        key_base = f"band_{lo//1000}k_{hi_band//1000}k"
        mask = (freqs >= lo) & (freqs < hi_band)
        if np.any(mask):
            local = np.where(mask)[0]
            idx = local[np.argmax(yf[mask])]
            out[f"{key_base}_peak_freq"] = float(freqs[idx])
            out[f"{key_base}_peak_amp"]  = float(yf[idx])
        else:
            out[f"{key_base}_peak_freq"] = np.nan
            out[f"{key_base}_peak_amp"]  = np.nan
    return out

def feature_pack(y_seg_raw, sr):
    y_seg = y_seg_raw.astype(float)
    if len(y_seg) > 0:
        peak = float(np.max(np.abs(y_seg)))
        rms_val = float(np.sqrt(np.mean(y_seg**2)))
    else:
        peak, rms_val = 0.0, 0.0

    out = {}
    if LOUDNESS_MODE == 'dbfs':
        out["peak_dbfs"] = float(20*np.log10(peak + 1e-12))
        out["rms_dbfs"]  = float(20*np.log10(rms_val + 1e-12))
    else:
        out["max_amp"] = peak
        out["rms"]     = rms_val

    # 頻譜
    N = len(y_seg)
    if N == 0:
        freqs = np.array([])
        Y = np.array([])
    else:
        Y = np.abs(fft(y_seg))[:N//2]
        freqs = fftfreq(N, 1/sr)[:N//2]

    out["spectral_centroid"] = float(np.mean(librosa.feature.spectral_centroid(y=y_seg, sr=sr))) if N else np.nan

    total_energy = float(np.sum(Y) + 1e-12)
    ear_mask  = (freqs >= 1000) & (freqs <= 5000)
    high_mask = (freqs > 3000)
    ear_energy  = float(np.sum(Y[ear_mask])) if len(Y)>0 else 0.0
    high_energy = float(np.sum(Y[high_mask])) if len(Y)>0 else 0.0
    loudness_sone = 10.0 * (ear_energy / total_energy) if total_energy>0 else 0.0
    out["sharpness_hfxloud"] = (high_energy / total_energy) * loudness_sone if total_energy>0 else 0.0

    out["zcr"] = float(np.mean(librosa.feature.zero_crossing_rate(y_seg)[0])) if N else np.nan
    out.update(band_peak_features(freqs, Y, step_hz=BAND_STEP_HZ, max_hz=BAND_MAX_HZ))

    if N > 0:
        mfccs = librosa.feature.mfcc(y=y_seg, sr=sr, n_mfcc=13)
        out.update({f"mfcc{i+1}": float(np.mean(mfccs[i])) for i in range(13)})
    else:
        out.update({f"mfcc{i+1}": np.nan for i in range(13)})

    return out

# ========================= 跨段統計：__mean__/__std__/__icc__/__agreement__ =========================
def _robust_cv(values):
    x = np.asarray(values, float)
    x = x[~np.isnan(x)]
    n = x.size
    if n == 0:
        return np.nan
    med = np.median(x)
    eps = 1e-12
    scale_base = abs(med) + eps
    if n < 4:
        std = np.std(x, ddof=1) if n >= 2 else 0.0
        return float(std / scale_base)
    mad = np.median(np.abs(x - med))
    iqr = np.percentile(x, 75) - np.percentile(x, 25)
    std = np.std(x, ddof=1)
    spread = max(mad, iqr * 0.5, std * 0.6745)
    return float(spread / scale_base)

def agreement_within_series_0_1(values, cv_target=0.20):
    cv = _robust_cv(values)
    if np.isnan(cv):
        return 0.0
    return float(np.exp(-cv / (cv_target + 1e-12)))

def icc_1way_random(values):
    x = np.asarray(values, float)
    x = x[~np.isnan(x)]
    n = len(x)
    if n < 2:
        return np.nan
    mean_total = np.mean(x)
    cv = np.std(x, ddof=1) / (abs(mean_total) + 1e-12)
    icc_val = 1.0 / (1.0 + cv ** 2)
    return float(np.clip(icc_val, 0.0, 1.0))

def append_within_series_stats(df):
    stat_labels = ["__mean__", "__std__", "__icc__", "__agreement__"]
    stat_rows = [{c: np.nan for c in df.columns} for _ in stat_labels]
    for r, label in zip(stat_rows, stat_labels):
        r["title"] = label
    for metric in METRIC_COLS:
        vals = pd.to_numeric(df[metric], errors="coerce").to_numpy()
        vals = vals[~np.isnan(vals)]
        if len(vals) == 0:
            continue
        stat_rows[0][metric] = float(np.mean(vals))
        stat_rows[1][metric] = float(np.std(vals, ddof=1)) if len(vals) > 1 else 0.0
        stat_rows[2][metric] = icc_1way_random(vals) if len(vals) > 1 else 0.0
        stat_rows[3][metric] = agreement_within_series_0_1(vals)
    return pd.concat([df, pd.DataFrame(stat_rows)], ignore_index=True)

# ========================= 圖表輸出 =========================
def amp_spectrum(y, sr):
    if y is None or len(y) == 0:
        return np.array([]), np.array([])
    N = len(y)
    Y = np.abs(fft(y))[:N//2]
    F = fftfreq(N, 1/sr)[:N//2]
    return F, Y

def save_analysis_figure(seg_dir, seg_name, y_hit_raw, y_den_raw, y_bg_raw, sr):
    if not SAVE_ANALYSIS_FIG:
        return

    # 左：Raw 波形；右：頻譜（Raw/Den/Background），Peak 用 Den 來標
    t_hit = np.linspace(0, len(y_hit_raw)/sr, len(y_hit_raw)) if len(y_hit_raw)>0 else np.array([])
    f_hit, Y_hit = amp_spectrum(y_hit_raw, sr)
    f_den, Y_den = amp_spectrum(y_den_raw, sr)
    f_bg,  Y_bg  = amp_spectrum(y_bg_raw,  sr) if y_bg_raw is not None else (np.array([]), np.array([]))

    fig, axes = plt.subplots(1, 2, figsize=(12, 3))

    # 波形
    if len(t_hit)>0:
        axes[0].plot(t_hit, y_hit_raw, label='Raw')
    if y_bg_raw is not None and len(y_bg_raw)>0:
        t_bg = np.linspace(0, len(y_bg_raw)/sr, len(y_bg_raw))
        axes[0].plot(t_bg, y_bg_raw, linestyle='--', alpha=0.6, label='Background')
    if len(y_den_raw)>0:
        t_den = np.linspace(0, len(y_den_raw)/sr, len(y_den_raw))
        axes[0].plot(t_den, y_den_raw, alpha=0.9, label='Denoised')

    axes[0].set_title(f"擊球片段波形圖 - {seg_name}")
    axes[0].set_xlabel("時間（秒）")
    axes[0].set_ylabel("振幅")
    axes[0].grid(True)
    axes[0].legend()

    # 頻譜
    if len(Y_hit)>0:
        axes[1].plot(f_hit, Y_hit, label='Raw')
    if len(Y_bg )>0:
        axes[1].plot(f_bg,  Y_bg,  linestyle='--', label='Background')
    if len(Y_den)>0:
        axes[1].plot(f_den, Y_den, label='Denoised')
        pidx = int(np.argmax(Y_den))
        axes[1].scatter([f_den[pidx]], [Y_den[pidx]], s=40)
        axes[1].set_title(f"頻譜 (Peak={f_den[pidx]:.0f} Hz)")
    else:
        axes[1].set_title("頻譜")

    axes[1].set_xlim(0, BAND_MAX_HZ)
    axes[1].set_xlabel("頻率 (Hz)")
    axes[1].set_ylabel("幅值")
    axes[1].grid(True)
    axes[1].legend()

    plt.tight_layout()
    out_png = os.path.join(seg_dir, f"sound_analysis_{seg_name}.png")
    fig.savefig(out_png, dpi=300, bbox_inches='tight')
    plt.close(fig)

# ========================= OpenPose/IMU（可關閉） =========================
def run_openpose(pose_script, video_path, out_path):
    if not RUN_OPENPOSE:
        return
    if os.path.isfile(pose_script):
        import subprocess
        try:
            subprocess.run(["python", pose_script, "--input", video_path, "--output", out_path, "--rotation", '1'],
                           check=True)
            print(f"🎬 已輸出骨架分析結果影片: {out_path}")
        except Exception as e:
            print(f"⚠️ 執行 {pose_script} 失敗：{e}")
    else:
        print(f"⚠️ 找不到 {pose_script}，略過 OpenPose。")

def imu_anim_from_csv(folder, video_id, imu_name):
    if not RUN_IMU_ANIM:
        return
    track_csv_path = os.path.join(folder, f"{video_id}_{imu_name}.csv")
    track_video_path = os.path.join(folder, f"{video_id}_{imu_name}.mp4")
    if not os.path.isfile(track_csv_path):
        print(f"⚠️ 找不到 {track_csv_path}，略過 {imu_name} 動畫。")
        return

    df_imu = pd.read_csv(track_csv_path)
    quat_cols = None
    for cands in [['X','Y','Z','w'], ['x','y','z','w'], ['qx','qy','qz','qw']]:
        if all(col in df_imu.columns for col in cands):
            quat_cols = cands
            break
    if quat_cols is None:
        print('Cannot detect quaternion columns, columns are:', df_imu.columns)
        return

    qx, qy, qz, qw = [df_imu[c] for c in quat_cols]
    quats = np.stack([qx, qy, qz, qw], axis=1)
    rot = R.from_quat(quats)
    body_x = np.tile(np.array([1,0,0]), (len(df_imu),1))
    dirs = rot.apply(body_x)

    N = len(df_imu)
    T = 5.0
    times = np.linspace(0, T, N)
    arrow_tips = dirs

    fig = plt.figure()
    ax = fig.add_subplot(111, projection='3d')
    ax.set_xlim([-1,1]); ax.set_ylim([-1,1]); ax.set_zlim([-1,1])
    ax.set_xlabel('X'); ax.set_ylabel('Y'); ax.set_zlabel('Z')
    ax.set_title(imu_name + ' Orientation Animation')

    arrow = [None]
    ttext = [None]
    trail_all, = ax.plot(arrow_tips[:,0], arrow_tips[:,1], arrow_tips[:,2], color='b', linewidth=1, alpha=0.2)
    trail_active, = ax.plot([], [], [], color='r', linewidth=2)

    def update(frame):
        if arrow[0] is not None:
            arrow[0].remove()
        v = arrow_tips[frame]
        arrow[0] = ax.quiver(0,0,0, v[0], v[1], v[2], length=1.0, color='b',
                             arrow_length_ratio=0.15, linewidth=2)
        if ttext[0] is not None:
            ttext[0].remove()
        ttext[0] = ax.text2D(0.05, 0.95, f'Time: {times[frame]:.2f} s', transform=ax.transAxes, fontsize=12)
        trail_active.set_data(arrow_tips[:frame+1,0], arrow_tips[:frame+1,1])
        trail_active.set_3d_properties(arrow_tips[:frame+1,2])
        return arrow[0], ttext[0], trail_active

    ani = FuncAnimation(fig, update, frames=N, interval=T*1000/N, blit=False, repeat=False)
    ani.save(track_video_path, writer='ffmpeg', fps=N/T)
    plt.close(fig)
    print(f"🎥 已輸出 {imu_name} 方向動畫：{track_video_path}")

# ========================= 主流程 =========================
def build_segment_row_base(title, idx, start_t, end_t, peak_t, audio_fn, bg_fn, den_fn):
    return {
        "title": title, "idx": idx, "start_time": start_t, "end_time": end_t,
        "peak_time": peak_t, "audio_file": audio_fn, "bg_file": bg_fn, "denoised_file": den_fn
    }

def ensure_order_and_cols(df):
    for c in SUMMARY_COLS:
        if c not in df.columns:
            df[c] = np.nan
    return df[SUMMARY_COLS]

def main():
    start = ti.time()
    mp4_list = sorted(glob.glob(os.path.join(BATCH_DIR, "*.mp4")))
    if not mp4_list:
        raise FileNotFoundError(f"在 {BATCH_DIR} 找不到任何 .mp4")
    print(f"🔎 將處理 {len(mp4_list)} 個檔案：", [os.path.basename(p) for p in mp4_list])

    all_rows_raw, all_rows_den = [], []

    for video_path in mp4_list:
        base_dir  = os.path.dirname(video_path)
        video_name = os.path.basename(video_path)
        vid = os.path.splitext(video_name)[0]
        OUTPUT_DIR = base_dir
        audio_path = os.path.join(OUTPUT_DIR, f"{vid}_temp_audio.wav")
        segments_dir = os.path.join(OUTPUT_DIR, f"segments_{vid}")
        if os.path.exists(segments_dir):
            shutil.rmtree(segments_dir)
        os.makedirs(segments_dir, exist_ok=True)

        print(f"\n=== ▶ 處理：{video_name} ===")

        # 1) 擷取音訊
        clip = VideoFileClip(video_path)
        clip.audio.write_audiofile(audio_path, fps=48000, verbose=False, logger=None)

        # 2) 讀取音訊（librosa 即是 float）
        y_float, sr = librosa.load(audio_path, sr=None)

        # 3) 偵測 + 強度過濾
        peak_samples, frame_ctx = dynamic_peak_detection(
            y_float, sr, win=RMS_FRAME_SEC, hop=RMS_HOP_SEC, k=MAD_K, min_dist=MIN_DIST_SEC
        )
        rms_series, t_rms, n_fft, hop_samp = frame_ctx
        peak_samples = filter_top_peaks_by_strength(
            peak_samples, y_float, sr, rel_thresh=PEAK_REL_STRENGTH, search_win=SEARCH_WIN_SEC
        )
        peaks_sec = (peak_samples / sr).astype(float)
        print(f"偵測到 {len(peaks_sec)} 個擊球（{int(PEAK_REL_STRENGTH*100)}% 門檻）")

        # ========== 多峰處理：只取最接近 TARGET_HIT_SEC 的那一筆 ==========
        if len(peaks_sec) == 0:
            print("⚠️ 本影片未偵測到任何擊球峰值 → 視為沒有擊球，略過。")
            continue

        peaks_sec = np.asarray(peaks_sec, dtype=float)
        best_idx = int(np.argmin(np.abs(peaks_sec - TARGET_HIT_SEC)))
        best_peak = float(peaks_sec[best_idx])
        best_dt = abs(best_peak - TARGET_HIT_SEC)

        if best_dt > TARGET_TOL_SEC:
            print(f"⚠️ 最接近 {TARGET_HIT_SEC:.2f}s 的峰在 {best_peak:.3f}s（Δ={best_dt:.3f}s）> {TARGET_TOL_SEC:.2f}s → 視為沒有擊球，略過。")
            continue

        peaks_sec = np.array([best_peak], dtype=float)
        print(f"✅ 多峰偵測：保留最接近 {TARGET_HIT_SEC:.2f}s 的擊球峰 = {best_peak:.3f}s（Δ={best_dt:.3f}s）")

        # 3.5) 背景估計（去噪用）
        bg_mask, bg_thr = pick_background_mask(rms_series, percentile=BG_PERCENTILE)
        noise_mag_ref = estimate_noise_spectrum(y_float, sr, bg_mask, n_fft, hop_samp)
        print(f"背景門檻(RMS {BG_PERCENTILE}th) = {bg_thr:.6f}，背景幀數 = {int(bg_mask.sum())}")

        # 4) 切片、去噪、特徵（逐段）
        cap = cv2.VideoCapture(video_path)
        fps = cap.get(cv2.CAP_PROP_FPS)

        for i, peak_t in enumerate(peaks_sec, start=1):
            s_idx = int(max(0, (peak_t - PRE_TIME) * sr))
            e_idx = int(min(len(y_float), (peak_t + POST_TIME) * sr))
            y_hit_raw = y_float[s_idx:e_idx]

            # 背景片段
            bg_a = max(0, int((peak_t - 0.6)*sr))
            bg_b = min(len(y_float), int((peak_t - 0.4)*sr))
            if (bg_b - bg_a) >= int(0.05*sr):
                y_bg_raw = y_float[bg_a:bg_b]
                y_bg_save = normalize_for_saving(y_bg_raw)
                bg_wav = f"{vid}_hit_{i:02d}_bg.wav"
                sf.write(os.path.join(segments_dir, bg_wav), y_bg_save, sr)
            else:
                y_bg_raw = None
                bg_wav = ""

            # 去噪（回 raw；存檔才 normalize）
            y_den_raw = spectral_subtraction(
                y_hit_raw, sr, noise_mag_ref, n_fft, hop_samp,
                beta=SS_BETA, floor=SS_FLOOR
            )
            y_hit_save = normalize_for_saving(y_hit_raw)
            y_den_save = normalize_for_saving(y_den_raw)

            # 檔名與寫檔
            hit_wav = f"{vid}_hit_{i:02d}.wav"
            den_wav = f"{vid}_hit_{i:02d}_den.wav"
            sf.write(os.path.join(segments_dir, hit_wav), y_hit_save, sr)
            sf.write(os.path.join(segments_dir, den_wav), y_den_save, sr)

            # 擊球畫面存圖
            if SAVE_SEGMENT_PNG:
                frame_idx = int(float(peak_t) * fps)
                cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
                ret, frame = cap.read()
                if ret and frame is not None:
                    frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
                    cv2.imwrite(os.path.join(segments_dir, f"{vid}_hit_{i:02d}.png"), frame)

            # 分析圖
            if SAVE_ANALYSIS_FIG:
                save_analysis_figure(segments_dir, hit_wav, y_hit_raw, y_den_raw, y_bg_raw, sr)

            # 特徵（raw / den）
            feats_raw = feature_pack(y_hit_raw, sr)
            feats_den = feature_pack(y_den_raw, sr)

            base = build_segment_row_base(
                title=vid, idx=i,
                start_t=s_idx/sr, end_t=e_idx/sr, peak_t=float(peak_t),
                audio_fn=hit_wav, bg_fn=bg_wav, den_fn=den_wav
            )
            row_raw = dict(base); row_raw.update(feats_raw)
            row_den = dict(base); row_den.update(feats_den)
            all_rows_raw.append(row_raw)
            all_rows_den.append(row_den)

        cap.release()

        # OpenPose/IMU（可關閉）
        if RUN_OPENPOSE:
            run_openpose("video_openpose_V04.py", video_path,
                         os.path.join(OUTPUT_DIR, f"{vid}_pose.mp4"))
        if RUN_IMU_ANIM:
            imu_anim_from_csv(OUTPUT_DIR, vid, IMU1_NAME)
            imu_anim_from_csv(OUTPUT_DIR, vid, IMU2_NAME)

    # 5) 建兩份彙整（同欄位順序、無前綴）
    raw_df = ensure_order_and_cols(pd.DataFrame(all_rows_raw))
    den_df = ensure_order_and_cols(pd.DataFrame(all_rows_den))

    # 6) 在各自檔案最後加上四列：__mean__/__std__/__icc__/__agreement__
    raw_out = append_within_series_stats(raw_df.copy())
    den_out = append_within_series_stats(den_df.copy())

    raw_path = os.path.join(BATCH_DIR, "raw_summary.csv")
    den_path = os.path.join(BATCH_DIR, "denoised_summary.csv")
    if OUTPUT_RAW_CSV:
        raw_out.to_csv(raw_path, index=False)

    den_out.to_csv(den_path, index=False)
    print(f"📄 raw_summary.csv：{raw_path}")
    print(f"📄 denoised_summary.csv：{den_path}")
    print("✅ 完成，耗時:", f"{ti.time()-start:.2f}", "秒")

if __name__ == "__main__":
    main()

