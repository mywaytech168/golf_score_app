import os
import sys
import cv2
import subprocess
import numpy as np
import csv
import pandas as pd
from pathlib import Path

# ================== 使用者設定 ==================
INPUT_DIR = r"Z:\Data\golf\20260126\cut\stabilized"
ROTATION_90_CLOCKWISE = 0   # 0=不旋轉, 1=順時針 90 度

# 是否額外儲存這三個輸出（預設 False）
SAVE_POSE_VIDEO       = False   # phase 之外，另存一份骨架影片 xxx_pose.mp4
SAVE_POSE_CSV         = False   # xxx_pose.csv
SAVE_POSE_PHASE_CSV   = False   # xxx_pose_phase.csv

# ================== 其他參數 ==================
MIN_TOTAL_CONF = 0.30          # 全身平均置信度下限

BASELINE_FRAMES = 10           # ✅ 建議拉高：baseline 太短很容易一開始就觸發 backswing
SPEED_STD_FACTOR = 2.0         # baseline 平均 + k*std

WRIST_SMOOTH_WINDOW = 5        # 右手腕平滑 window

LOW_AROUND_IMPACT_PRE_FRAMES  = 5   # 擊球前視窗（frame）
LOW_AROUND_IMPACT_POST_FRAMES = 10  # 擊球後視窗（frame）

# ================== ✅ address 放寬（避免一開始 backswing） ==================
MIN_START_SEC = 0.5           # ✅ 至少過了這秒數才允許進 backswing（建議 0.2~0.4）
START_CONSEC_FRAMES = 5        # ✅ 需要連續幾幀超過門檻才算開始 backswing

# ================== ✅ HIT 顯示設定 ==================
HIT_SHOW_WINDOW = 2            # impact_frame ± 這個範圍顯示 HIT（1 = 3 幀內）
HIT_COLOR = (0, 255, 255)      # 黃色 (BGR)

# ================== ✅ Good/Bad 標註設定（右上角） ==================
SHOW_RULE_LABEL = True
RULE_LABEL_FILENAME = "rule_scoring_results.csv"
RULE_NULL_TEXT = "Null"
RULE_TEXT_SCALE = 0.9
RULE_TEXT_THICKNESS = 3
RULE_MARGIN = 10

# ================== OpenPose 載入 ==================
# dir_path = os.path.dirname(os.path.abspath(__file__))
dir_path = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
pyd_path = os.path.join(dir_path, "openpose", "build", "python", "openpose", "Release")
if os.path.exists(pyd_path):
    os.add_dll_directory(pyd_path)
    sys.path.append(pyd_path)
import pyopenpose as op  # type: ignore

# BODY_25 index
NOSE        = 0
NECK        = 1
R_SHOULDER  = 2
R_ELBOW     = 3
R_WRIST     = 4
L_SHOULDER  = 5
L_ELBOW     = 6
L_WRIST     = 7
MID_HIP     = 8
R_HIP       = 9
L_HIP       = 12

params = {
    "model_folder": os.path.join(dir_path, "openpose", "models"),
    "model_pose": "BODY_25",
    "hand": False,
    "face": False,
    "disable_blending": False,
    "number_people_max": 1,
}

opWrapper = op.WrapperPython()
opWrapper.configure(params)
opWrapper.start()

# ================== 工具函式 ==================
def line_angle_deg(x1, y1, x2, y2):
    """計算 (x1,y1)->(x2,y2) 相對水平線角度 (deg)，影像座標 y 向下，因此用 -dy。"""
    vals = [x1, y1, x2, y2]
    if any(np.isnan(v) for v in vals):
        return np.nan
    dx = x2 - x1
    dy = -(y2 - y1)
    if dx == 0 and dy == 0:
        return np.nan
    return float(np.degrees(np.arctan2(dy, dx)))

def merge_audio(video_in, audio_src, video_out):
    """用 ffmpeg 把 audio_src 的音訊合併到 video_in 的影片上。"""
    cmd = [
        "ffmpeg",
        "-y",
        "-i", video_in,
        "-i", audio_src,
        "-c:v", "copy",
        "-map", "0:v:0",
        "-map", "1:a:0?",
        "-shortest",
        video_out,
    ]
    print(f"🎵 ffmpeg 合併音訊 -> {video_out}")
    subprocess.run(cmd, check=True)

def first_index_with_consecutive_true(mask, consec):
    """回傳第一個起點 index，使得 mask[i:i+consec] 全為 True；找不到回傳 None。"""
    if consec <= 1:
        idxs = np.where(mask)[0]
        return int(idxs[0]) if len(idxs) else None
    m = np.asarray(mask, dtype=bool)
    if len(m) < consec:
        return None
    for i in range(0, len(m) - consec + 1):
        if m[i:i+consec].all():
            return int(i)
    return None

def _normalize_video_key(name: str) -> str:
    """把 'hit_001.mp4' / 'hit_001' 之類統一成 key。"""
    if name is None:
        return ""
    s = str(name).strip()
    s = s.replace("\\", "/").split("/")[-1]   # 只留檔名
    if s.lower().endswith(".mp4"):
        s = s[:-4]
    return s

def load_rule_labels_from_dir(input_dir: Path) -> dict:
    """
    讀取 input_dir/rule_scoring_results.csv
    欄位固定：
      - video_key (不含 .mp4)
      - pred_goodbad (good/bad)
    回傳 dict: {video_stem: 'Good'/'Bad'/...}
    """
    csv_path = input_dir / RULE_LABEL_FILENAME
    if not csv_path.exists():
        print(f"ℹ️ 找不到 {RULE_LABEL_FILENAME}，將全部顯示 {RULE_NULL_TEXT}")
        return {}

    try:
        df_rule = pd.read_csv(csv_path, encoding="utf-8-sig")
    except Exception:
        try:
            df_rule = pd.read_csv(csv_path, encoding="utf-8")
        except Exception as e:
            print(f"⚠️ 讀取 {csv_path} 失敗：{e}，將全部顯示 {RULE_NULL_TEXT}")
            return {}

    if df_rule.empty:
        print(f"⚠️ {RULE_LABEL_FILENAME} 是空的，將全部顯示 {RULE_NULL_TEXT}")
        return {}

    # ✅ 固定欄位名
    if "video_key" not in df_rule.columns or "pred_goodbad" not in df_rule.columns:
        print(f"⚠️ {RULE_LABEL_FILENAME} 欄位不符合預期，需包含 video_key / pred_goodbad")
        print(f"   目前欄位: {list(df_rule.columns)}")
        return {}

    # ✅ 轉字串 + 去空白（避免 NaN/空白害你 mapped 很少）
    keys = df_rule["video_key"].astype(str).str.strip()
    vals = df_rule["pred_goodbad"].astype(str).str.strip()

    mapping = {}
    for k, v in zip(keys, vals):
        k_norm = _normalize_video_key(k)  # 已經不含.mp4也沒關係
        if not k_norm:
            continue

        low = v.lower()
        if low == "good":
            vv2 = "Good"
        elif low == "bad":
            vv2 = "Bad"
        else:
            vv2 = RULE_NULL_TEXT  # 不在 good/bad 就給 Null

        mapping[k_norm] = vv2

    # ✅ 多印一些 debug 幫你立刻驗證有沒有對上 hit_001
    sample_keys = list(mapping.keys())[:10]
    print(f"📄 已載入 rule 標註：{csv_path}  (rows={len(df_rule)}, mapped={len(mapping)})")
    print(f"   sample keys: {sample_keys}")

    return mapping

def draw_top_right_label(frame, text: str):
    """在右上角畫出 Good/Bad/Null。"""
    if text is None or str(text).strip() == "":
        text = RULE_NULL_TEXT

    t = str(text).strip()
    t_low = t.lower()

    # 顏色（你沒要求，但這樣一眼可辨）
    if t_low == "good":
        color = (0, 255, 0)
    elif t_low == "bad":
        color = (0, 0, 255)
    else:
        color = (200, 200, 200)

    font = cv2.FONT_HERSHEY_SIMPLEX
    scale = RULE_TEXT_SCALE
    thick = RULE_TEXT_THICKNESS

    (tw, th), baseline = cv2.getTextSize(t, font, scale, thick)
    h, w = frame.shape[:2]
    x = w - RULE_MARGIN - tw
    y = RULE_MARGIN + th

    # 背景框（黑底半透明感用實心矩形）
    pad = 6
    x1 = max(0, x - pad)
    y1 = max(0, y - th - pad)
    x2 = min(w - 1, x + tw + pad)
    y2 = min(h - 1, y + baseline + pad)

    cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 0, 0), -1)

    # 外框（黑）+ 內字（彩色）
    cv2.putText(frame, t, (x, y), font, scale, (0, 0, 0), thick + 2, cv2.LINE_AA)
    cv2.putText(frame, t, (x, y), font, scale, color, thick, cv2.LINE_AA)

# ================== 主流程 ==================
INPUT_DIR = Path(INPUT_DIR)
if not INPUT_DIR.exists():
    print(f"❌ 找不到資料夾：{INPUT_DIR}")
    sys.exit(1)

# ✅ 先載入 rule_scoring_results.csv（只做一次）
rule_map = load_rule_labels_from_dir(INPUT_DIR) if SHOW_RULE_LABEL else {}

mp4_list = sorted([p for p in INPUT_DIR.iterdir() if p.suffix.lower() == ".mp4"])
if not mp4_list:
    print(f"⚠️ 資料夾內沒有 .mp4：{INPUT_DIR}")
    sys.exit(0)

print(f"📂 目標資料夾：{INPUT_DIR}")
print(f"🔍 發現 {len(mp4_list)} 支 .mp4 影片\n")

for video_path in mp4_list:
    print("=" * 80)
    print(f"▶️ 處理影片: {video_path.name}")
    try:
        # 準備路徑
        base_name = video_path.stem
        video_dir = video_path.parent
        phase_dir = video_dir / "phase"
        phase_dir.mkdir(parents=True, exist_ok=True)

        tmp_pose_video_path  = phase_dir / f"{base_name}_tmp_pose.mp4"
        tmp_phase_video_path = phase_dir / f"{base_name}_tmp_phase.mp4"

        pose_video_path      = phase_dir / f"{base_name}_pose.mp4"
        pose_csv_path        = phase_dir / f"{base_name}_pose.csv"
        pose_phase_csv_path  = phase_dir / f"{base_name}_pose_phase.csv"
        phase_video_path     = phase_dir / f"{base_name}_pose_phase.mp4"

        # ✅ 取得此影片對應的 Good/Bad/Null（找不到就 Null）
        rule_label = rule_map.get(_normalize_video_key(base_name), RULE_NULL_TEXT)

        # ---------- 第 1 階段：跑 OpenPose，輸出暫存骨架影片 + pose rows ----------
        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            print(f"❌ 影片無法開啟，略過：{video_path}")
            continue

        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        fps = cap.get(cv2.CAP_PROP_FPS)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))

        if ROTATION_90_CLOCKWISE == 1:
            writer_pose = cv2.VideoWriter(str(tmp_pose_video_path), fourcc, fps, (height, width))
            print("🔄 輸出畫面將順時針旋轉 90 度")
        else:
            writer_pose = cv2.VideoWriter(str(tmp_pose_video_path), fourcc, fps, (width, height))

        rows = []
        frame_idx = 0

        print("⛳ 正在逐 frame 分析骨架與角度...")

        while True:
            ret, frame = cap.read()
            if not ret:
                break

            if ROTATION_90_CLOCKWISE == 1:
                frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)

            datum = op.Datum()
            datum.cvInputData = frame
            datums = op.VectorDatum()
            datums.append(datum)
            opWrapper.emplaceAndPop(datums)

            poseKeypoints = datum.poseKeypoints

            # 預設為 NaN
            shoulder_angle = np.nan
            hip_angle = np.nan
            x_factor = np.nan
            mean_conf = np.nan

            neck_x = neck_y = np.nan
            ls_x = ls_y = rs_x = rs_y = np.nan
            lh_x = lh_y = rh_x = rh_y = np.nan
            lw_x = lw_y = rw_x = rw_y = np.nan

            if poseKeypoints is not None and poseKeypoints.shape[0] > 0:
                pts = poseKeypoints[0]  # (25,3)
                confs = pts[:, 2]
                mean_conf = float(np.mean(confs))

                if mean_conf >= MIN_TOTAL_CONF:
                    def get_xy(idx, conf_th=0.1):
                        x, y, c = pts[idx]
                        if c < conf_th:
                            return np.nan, np.nan
                        return float(x), float(y)

                    neck_x, neck_y = get_xy(NECK)
                    ls_x, ls_y = get_xy(L_SHOULDER)
                    rs_x, rs_y = get_xy(R_SHOULDER)
                    lh_x, lh_y = get_xy(L_HIP)
                    rh_x, rh_y = get_xy(R_HIP)
                    lw_x, lw_y = get_xy(L_WRIST)
                    rw_x, rw_y = get_xy(R_WRIST)

                    shoulder_angle = line_angle_deg(ls_x, ls_y, rs_x, rs_y)
                    hip_angle = line_angle_deg(lh_x, lh_y, rh_x, rh_y)
                    if not (np.isnan(shoulder_angle) or np.isnan(hip_angle)):
                        x_factor = shoulder_angle - hip_angle

            out_frame = datum.cvOutputData.copy()

            overlay_text = []
            overlay_text.append(f"Shoulder: {shoulder_angle:6.1f} deg" if not np.isnan(shoulder_angle) else "Shoulder: ---")
            overlay_text.append(f"Hip:      {hip_angle:6.1f} deg" if not np.isnan(hip_angle) else "Hip:      ---")
            overlay_text.append(f"X-factor: {x_factor:6.1f} deg" if not np.isnan(x_factor) else "X-factor: ---")

            y0 = 30
            dy = 25
            for i, txt in enumerate(overlay_text):
                cv2.putText(out_frame, txt, (10, y0 + i * dy),
                            cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2, cv2.LINE_AA)

            # ✅ 右上角 Good/Bad/Null（在骨架暫存影片也加，方便你檢查）
            if SHOW_RULE_LABEL:
                draw_top_right_label(out_frame, rule_label)

            writer_pose.write(out_frame)

            t_sec = frame_idx / fps if fps > 0 else 0.0

            rows.append([
                frame_idx,
                t_sec,
                mean_conf,
                shoulder_angle,
                hip_angle,
                x_factor,
                neck_x, neck_y,
                ls_x, ls_y,
                rs_x, rs_y,
                lh_x, lh_y,
                rh_x, rh_y,
                lw_x, lw_y,
                rw_x, rw_y,
            ])

            frame_idx += 1

        cap.release()
        writer_pose.release()

        if not rows:
            print("⚠️ 沒有任何 frame 資料，略過這支影片")
            tmp_pose_video_path.unlink(missing_ok=True)
            continue

        # ---------- 建立 DataFrame ----------
        cols = [
            "frame",
            "time_sec",
            "mean_conf",
            "shoulder_angle_deg",
            "hip_angle_deg",
            "x_factor_deg",
            "neck_x", "neck_y",
            "ls_x", "ls_y",
            "rs_x", "rs_y",
            "lh_x", "lh_y",
            "rh_x", "rh_y",
            "lw_x", "lw_y",
            "rw_x", "rw_y",
        ]
        df = pd.DataFrame(rows, columns=cols)

        if SAVE_POSE_CSV:
            df.to_csv(pose_csv_path, index=False, encoding="utf-8-sig")
            print(f"📄 已輸出 pose CSV: {pose_csv_path}")

        # ---------- 第 2 階段：揮桿階段分析，產生 df['phase'] ----------
        if len(df) < 5:
            print("⚠️ frame 太少，全部標記為 unknown")
            df["phase"] = "unknown"
        else:
            dt = df.loc[1, "time_sec"] - df.loc[0, "time_sec"]
            fps_est = 1.0 / dt if dt > 0 else fps
            print(f"推算 FPS ≈ {fps_est:.2f}")

            s_rad = np.deg2rad(df["shoulder_angle_deg"].ffill().bfill())
            h_rad = np.deg2rad(df["hip_angle_deg"].ffill().bfill())
            s_unwrap = np.unwrap(s_rad)
            h_unwrap = np.unwrap(h_rad)
            x_unwrap = s_unwrap - h_unwrap
            df["x_factor_unwrap_deg"] = np.rad2deg(x_unwrap)

            rw_x = df["rw_x"]
            rw_y = df["rw_y"]

            rw_x_f = rw_x.interpolate().bfill().ffill()
            rw_y_f = rw_y.interpolate().bfill().ffill()

            rw_x_s = rw_x_f.rolling(window=WRIST_SMOOTH_WINDOW, min_periods=1, center=True).mean()
            rw_y_s = rw_y_f.rolling(window=WRIST_SMOOTH_WINDOW, min_periods=1, center=True).mean()
            df["rw_y_smooth"] = rw_y_s

            dx = rw_x_s.diff()
            dy = rw_y_s.diff()
            df["rw_speed"] = np.sqrt(dx**2 + dy**2) * fps_est

            if not df["rw_speed"].notna().any():
                print("⚠️ 無法取得有效速度資訊，全部標記為 unknown")
                df["phase"] = "unknown"
            else:
                baseline_len = min(BASELINE_FRAMES, max(3, len(df) // 3))
                baseline = df["rw_speed"].iloc[:baseline_len]
                th = baseline.mean() + SPEED_STD_FACTOR * baseline.std()

                min_start_frame = int(round(MIN_START_SEC * fps_est))
                eligible = df["frame"].values >= min_start_frame

                over_th = (df["rw_speed"].values > th) & eligible

                start_i = first_index_with_consecutive_true(over_th, START_CONSEC_FRAMES)
                if start_i is None:
                    start_i = 0
                    start_frame = int(df["frame"].iloc[0])
                    print("⚠️ 找不到明確 backswing 起點，start_frame 回退為 0")
                else:
                    start_frame = int(df.loc[start_i, "frame"])

                print(f"start_frame = {start_frame}  (address → backswing)  [min_start_frame={min_start_frame}, consec={START_CONSEC_FRAMES}]")

                mask_from_start = df["frame"] >= start_frame
                impact_idx = df.loc[mask_from_start, "rw_speed"].idxmax()
                impact_frame = int(df.loc[impact_idx, "frame"])
                impact_i = impact_idx
                print(f"impact_frame = {impact_frame}  (近似擊球瞬間)")

                lo_top = min(start_i, impact_i)
                hi_top = max(start_i, impact_i)
                top_sub = df.iloc[lo_top:hi_top+1]
                if len(top_sub) == 0:
                    top_i = impact_i
                else:
                    top_i = top_sub["rw_y_smooth"].idxmin()
                top_frame = int(df.loc[top_i, "frame"])
                print(f"top_frame   = {top_frame}  (上桿頂點：手最高)")

                lo_low_i = max(impact_i - LOW_AROUND_IMPACT_PRE_FRAMES, 0)
                hi_low_i = min(impact_i + LOW_AROUND_IMPACT_POST_FRAMES, len(df) - 1)
                low_sub = df.iloc[lo_low_i:hi_low_i+1]
                if len(low_sub) == 0:
                    low_i = impact_i
                else:
                    low_i = low_sub["rw_y_smooth"].idxmax()
                low_frame = int(df.loc[low_i, "frame"])
                print(f"low_frame   = {low_frame}  (downswing 底部：手最低)")

                def label_phase(f):
                    if f < start_frame:
                        return "address"
                    elif f < top_frame:
                        return "backswing"
                    elif f <= low_frame:
                        return "downswing"
                    else:
                        return "follow_through"

                df["phase"] = df["frame"].apply(label_phase)
                df["start_frame"]  = start_frame
                df["top_frame"]    = top_frame
                df["impact_frame"] = impact_frame
                df["low_frame"]    = low_frame

        if SAVE_POSE_PHASE_CSV:
            df.to_csv(pose_phase_csv_path, index=False, encoding="utf-8-sig")
            print(f"📄 已輸出 pose_phase CSV: {pose_phase_csv_path}")

        # ---------- 第 3 階段：產生附帶階段標籤的影片（暫存） ----------
        print("🎥 產生附帶階段文字標籤的暫存影片 ...")

        phase_by_frame = dict(zip(df["frame"].values, df["phase"].values))

        impact_frame_value = -999999
        if "impact_frame" in df.columns and df["impact_frame"].notna().any():
            impact_frame_value = int(df["impact_frame"].dropna().iloc[0])

        cap2 = cv2.VideoCapture(str(tmp_pose_video_path))
        if not cap2.isOpened():
            print("❌ 無法開啟暫存骨架影片，略過這支")
            tmp_pose_video_path.unlink(missing_ok=True)
            continue

        width2 = int(cap2.get(cv2.CAP_PROP_FRAME_WIDTH))
        height2 = int(cap2.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps2 = cap2.get(cv2.CAP_PROP_FPS)

        writer_phase = cv2.VideoWriter(str(tmp_phase_video_path), fourcc, fps2, (width2, height2))

        frame_idx2 = 0
        while True:
            ret, frame = cap2.read()
            if not ret:
                break

            phase = phase_by_frame.get(frame_idx2, "unknown")
            text = f"Phase: {phase}"

            cv2.putText(
                frame,
                text,
                (10, 120),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.8,
                (0, 0, 0),
                2,
                cv2.LINE_AA,
            )

            # ✅ 擊球瞬間顯示 HIT（黃色）
            if abs(frame_idx2 - impact_frame_value) <= HIT_SHOW_WINDOW:
                cv2.putText(
                    frame,
                    "HIT",
                    (10, 170),
                    cv2.FONT_HERSHEY_SIMPLEX,
                    1.2,
                    HIT_COLOR,
                    3,
                    cv2.LINE_AA,
                )

            # ✅ 右上角 Good/Bad/Null（最終 phase 影片也加）
            if SHOW_RULE_LABEL:
                draw_top_right_label(frame, rule_label)

            writer_phase.write(frame)
            frame_idx2 += 1

        cap2.release()
        writer_phase.release()

        # ---------- 第 4 階段：合併音訊 ----------
        merge_audio(str(tmp_phase_video_path), str(video_path), str(phase_video_path))
        print(f"✅ 已輸出 phase 影片: {phase_video_path}")

        if SAVE_POSE_VIDEO:
            merge_audio(str(tmp_pose_video_path), str(video_path), str(pose_video_path))
            print(f"✅ 已輸出 pose 影片:  {pose_video_path}")

        tmp_phase_video_path.unlink(missing_ok=True)
        tmp_pose_video_path.unlink(missing_ok=True)

    except Exception as e:
        print(f"❌ 處理 {video_path.name} 發生錯誤: {e}")

print("\n🎉 全部影片處理完成！")
