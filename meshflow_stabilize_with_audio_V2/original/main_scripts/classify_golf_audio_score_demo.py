

import os
import sys
import glob
import time
import math
import shutil
import pandas as pd

# =============== 使用者參數 ===============

TARGET_FOLDER = r'Z:\Data\golf\20260126\cut\stabilized'  # 批次處理資料夾路徑

# 每個特徵通過給幾分（0 或 RULE_SCORE_PER_FEATURE）
RULE_SCORE_PER_FEATURE = 5.0

# 各特徵的評分區間 + 權重
FEATURE_WEIGHTS = {
    "rms_dbfs":           1.0,
    "spectral_centroid":  1.0,
    "sharpness_hfxloud":  1.0,
    "highband_amp":       1.0,
    "peak_dbfs":          1.0,
}

RULE_INTERVALS = {
    # 越負越小聲；good/pro 主體在 -30 ~ -24 之間
    "rms_dbfs": {
        "low":   -30.0,
        "high":  -24.0,
        "weight": FEATURE_WEIGHTS["rms_dbfs"],
    },
    # 頻譜重心；good/pro 約落在 3.8k ~ 4.35k
    "spectral_centroid": {
        "low":   3800.0,
        "high":  4350.0,
        "weight": FEATURE_WEIGHTS["spectral_centroid"],
    },
    # 尖銳度 × loudness；>2 幾乎都是好球
    "sharpness_hfxloud": {
        "low":   2.0,
        "high":  3.0,      # 上限只是為了好看，其實通常不會超過
        "weight": FEATURE_WEIGHTS["sharpness_hfxloud"],
    },
    # highband_amp = (2k~3k + 3k~4k) 頻帶 peak 平均
    "highband_amp": {
        "low":   11.0,
        "high":  32.0,     # 太大多半是雜訊/爆音
        "weight": FEATURE_WEIGHTS["highband_amp"],
    },
    # 峰值音量；good/pro 大多在 -10 ~ -4 dBFS
    "peak_dbfs": {
        "low":   -10.0,
        "high":  -4.0,
        "weight": FEATURE_WEIGHTS["peak_dbfs"],
    },
}

# 至少通過幾「項」當作 good（例如：3 項 → 15 分）
GOOD_BAD_THRESHOLD_FEATURES = 3
GOOD_BAD_THRESHOLD_SCORE = GOOD_BAD_THRESHOLD_FEATURES * RULE_SCORE_PER_FEATURE

# 影片副檔名（會被掃描做索引）
VIDEO_EXTS = (".mp4", ".mov", ".avi", ".mkv")


# =============== 規則式打分 ===============

def rule_based_score_row(row,
                         intervals=RULE_INTERVALS,
                         per_feat_score=RULE_SCORE_PER_FEATURE):
    """
    對單列資料做規則式打分。

    row：一列 pandas Series（包含特徵）
    回傳：
        total_score: 總分
        passes: dict，每個特徵是否通過
    """
    score = 0.0
    passes = {}

    for feat, cfg in intervals.items():
        # highband_amp 是後算出來的特徵
        if feat == "highband_amp":
            val = float(
                row[["band_2k_3k_peak_amp", "band_3k_4k_peak_amp"]].mean()
            )
        else:
            val = float(row[feat])

        low = cfg.get("low", -math.inf)
        high = cfg.get("high", math.inf)
        weight = float(cfg.get("weight", 1.0))

        passed = (not math.isnan(val)) and (low <= val <= high)
        if passed:
            score += per_feat_score * weight

        passes[feat] = passed

    return score, passes


def infer_group_from_string(s: str):
    """
    從任意字串裡找 pro/good/bad：
    - 回傳 "pro" / "good" / "bad" 或 None
    - 不分大小寫
    """
    if not s:
        return None
    s = str(s).lower()

    if "bad" in s:
        return "bad"
    if "good" in s:
        return "good"
    if "pro" in s:
        return "pro"
    return None


def build_video_index(video_root):
    """
    掃描 video_root 底下所有影片檔，建立：
        key = 檔名（不含副檔名，小寫）
        value = 完整路徑
    """
    video_root = os.path.abspath(video_root)
    index = {}
    for ext in VIDEO_EXTS:
        pattern = os.path.join(video_root, f"**/*{ext}")
        for vpath in glob.glob(pattern, recursive=True):
            base = os.path.basename(vpath)
            key = os.path.splitext(base)[0].lower()
            if key not in index:
                index[key] = vpath
    return index


def score_folder(folder,
                 intervals=RULE_INTERVALS,
                 per_feat_score=RULE_SCORE_PER_FEATURE,
                 good_bad_threshold=GOOD_BAD_THRESHOLD_SCORE,
                 video_root=None):
    """
    掃描資料夾中的所有 csv，對每一列做規則式評分。

    每一列：
      - 若有 title 欄位 → 用該 title 當 clip_title
      - 否則 clip_title = csv 檔名（不含副檔名）
      - 真實標籤：優先從 title 推斷（pro/good/bad），再從 csv 檔名補

    影片複製：
      - 先對每個 video_key 累積 good/bad 次數
      - 用 majority vote 決定影片整體標籤
      - 最後一次性複製到 good/ 或 bad/（不會同時出現在兩邊）
    """
    csv_paths = sorted(glob.glob(os.path.join(folder, "*denoised_summary.csv")))
    if not csv_paths:
        raise FileNotFoundError(f"在資料夾中找不到任何 csv：{folder}")

    # --- 影片索引 ---
    video_index = None
    good_dir = bad_dir = None

    if video_root is not None:
        video_root = os.path.abspath(video_root)
        print(f"\n🎥 建立影片索引中：{video_root}")
        video_index = build_video_index(video_root)
        print(f"   → 共找到 {len(video_index)} 支影片可供比對")

        good_dir = os.path.join(video_root, "good")
        bad_dir  = os.path.join(video_root, "bad")
        os.makedirs(good_dir, exist_ok=True)
        os.makedirs(bad_dir, exist_ok=True)

    all_rows = []

    # per-row eval stats
    stats_counts = {
        "TP": 0,   # true good → 預測 good
        "TN": 0,   # true bad  → 預測 bad
        "FP": 0,   # true bad  → 預測 good
        "FN": 0,   # true good → 預測 bad
        "total": 0,
        "copied_good": 0,
        "copied_bad": 0,
        "miss_video_good": 0,
        "miss_video_bad": 0,
    }

    # 每支影片的 good/bad 計數： video_key -> {"good": n, "bad": n}
    video_votes = {}

    for csv_path in csv_paths:
        base = os.path.basename(csv_path)
        base_lower = base.lower()

        df = pd.read_csv(csv_path)

        # 若有 title 欄位，排除以 "__" 開頭的 summary 列
        if "title" in df.columns:
            df = df[~df["title"].astype(str).str.startswith("__")].copy()

        if df.empty:
            continue

        for _, row in df.iterrows():
            # clip_title：優先使用 title 欄位，沒有就用 csv 檔名（去掉副檔名）
            if "title" in row.index:
                clip_title = str(row["title"])
            else:
                clip_title = os.path.splitext(base)[0]

            # video_key：用來對應影片 & 聚合投票
            video_key = os.path.splitext(os.path.basename(clip_title))[0].lower()

            # 先從 title 推真實 group，再從 csv 檔名補
            true_group = infer_group_from_string(clip_title)
            if true_group is None:
                true_group = infer_group_from_string(base_lower)

            if true_group is None:
                true_goodbad_label = None
            else:
                true_goodbad_label = "good" if true_group in ("pro", "good") else "bad"

            # 規則評分
            score, passes = rule_based_score_row(row, intervals, per_feat_score)
            pred_goodbad = "good" if score >= good_bad_threshold else "bad"

            # per-row eval stats
            if true_goodbad_label is not None:
                stats_counts["total"] += 1
                if true_goodbad_label == "good" and pred_goodbad == "good":
                    stats_counts["TP"] += 1
                elif true_goodbad_label == "bad" and pred_goodbad == "bad":
                    stats_counts["TN"] += 1
                elif true_goodbad_label == "bad" and pred_goodbad == "good":
                    stats_counts["FP"] += 1
                elif true_goodbad_label == "good" and pred_goodbad == "bad":
                    stats_counts["FN"] += 1

            # 計算 highband_amp
            highband_amp_val = float(
                row[["band_2k_3k_peak_amp", "band_3k_4k_peak_amp"]].mean()
            )

            # 影片層級票數
            if video_key not in video_votes:
                video_votes[video_key] = {"good": 0, "bad": 0}
            video_votes[video_key][pred_goodbad] += 1

            all_rows.append({
                "source_csv": base,          # 來源 summary 檔名
                "clip_title": clip_title,    # 片段 / 影片名（來自 title）
                "video_key": video_key,      # 用來對應影片檔名
                "true_group": true_group,
                "true_goodbad": true_goodbad_label,
                "pred_goodbad": pred_goodbad,
                "rule_score": score,
                "rule_threshold": good_bad_threshold,
                # 主要特徵
                "rms_dbfs": row["rms_dbfs"],
                "spectral_centroid": row["spectral_centroid"],
                "sharpness_hfxloud": row["sharpness_hfxloud"],
                "highband_amp": highband_amp_val,
                "band_2k_3k_peak_amp": row["band_2k_3k_peak_amp"],
                "band_3k_4k_peak_amp": row["band_3k_4k_peak_amp"],
                "peak_dbfs": row["peak_dbfs"],
                # 各特徵是否通過
                "pass_rms_dbfs": passes["rms_dbfs"],
                "pass_spectral_centroid": passes["spectral_centroid"],
                "pass_sharpness_hfxloud": passes["sharpness_hfxloud"],
                "pass_highband_amp": passes["highband_amp"],
                "pass_peak_dbfs": passes["peak_dbfs"],
            })

    # 轉成 DataFrame
    results_df = pd.DataFrame(all_rows)

    # per-row classification accuracy
    accuracy = None
    if stats_counts["total"] > 0:
        accuracy = (stats_counts["TP"] + stats_counts["TN"]) / stats_counts["total"]

    # === 影片層級 majority vote 決定 final label ===
    video_final_label = {}   # video_key -> "good"/"bad"
    for key, cnt in video_votes.items():
        g = cnt.get("good", 0)
        b = cnt.get("bad", 0)
        if g == 0 and b == 0:
            continue
        if b > g:
            final_label = "bad"
        elif g > b:
            final_label = "good"
        else:
            # 平手 → 保守一點，當 bad
            final_label = "bad"
        video_final_label[key] = final_label

    # 把影片 final label 寫回每一列 (方便檢查)
    if not results_df.empty:
        results_df["video_final_label"] = results_df["video_key"].map(
            lambda k: video_final_label.get(k, None)
        )

    # === 依影片 final label 複製檔案 ===
    video_dst_path = {}  # video_key -> dst path

    if video_index is not None:
        for key, label in video_final_label.items():
            src = video_index.get(key)
            if not src:
                # 有影片 key 但找不到實體檔案
                if label == "good":
                    stats_counts["miss_video_good"] += 1
                else:
                    stats_counts["miss_video_bad"] += 1
                continue

            if label == "good":
                dst_dir = good_dir
            else:
                dst_dir = bad_dir

            dst = os.path.join(dst_dir, os.path.basename(src))
            if not os.path.exists(dst):
                shutil.copy2(src, dst)
                if label == "good":
                    stats_counts["copied_good"] += 1
                else:
                    stats_counts["copied_bad"] += 1

            video_dst_path[key] = dst

        # 把複製後的路徑也寫回每一列
        if not results_df.empty:
            results_df["copied_video_path"] = results_df["video_key"].map(
                lambda k: video_dst_path.get(k, None)
            )

    return results_df, accuracy, stats_counts


# =============== 主程式 ===============

def main():
    t0 = time.time()

    # 允許用命令列覆蓋資料夾路徑
    if len(sys.argv) > 1:
        csv_folder = sys.argv[1]
    else:
        csv_folder = TARGET_FOLDER

    csv_folder = os.path.abspath(csv_folder)

    # 第二個參數：影片根目錄；沒給就用 csv_folder
    if len(sys.argv) > 2:
        video_root = os.path.abspath(sys.argv[2])
    else:
        video_root = csv_folder

    print(f"📂 CSV 資料夾：{csv_folder}")
    print(f"🎥 影片根目錄：{video_root}")
    print(f"🔧 每特徵分數：{RULE_SCORE_PER_FEATURE}")
    print(f"🔧 good/bad 門檻（分數）：{GOOD_BAD_THRESHOLD_SCORE} "
          f"(通過 {GOOD_BAD_THRESHOLD_FEATURES} 個特徵)")

    # 規則設定簡單列一下
    print("\n👉 規則區間：")
    for feat, cfg in RULE_INTERVALS.items():
        print(f"  {feat:18s}: [{cfg.get('low', '-∞')}, {cfg.get('high', '∞')}]  "
              f"weight={cfg.get('weight', 1.0)}")

    results_df, accuracy, stats_counts = score_folder(
        csv_folder,
        intervals=RULE_INTERVALS,
        per_feat_score=RULE_SCORE_PER_FEATURE,
        good_bad_threshold=GOOD_BAD_THRESHOLD_SCORE,
        video_root=video_root,
    )

    out_csv = os.path.join(csv_folder, "rule_scoring_results.csv")
    results_df.to_csv(out_csv, index=False, encoding="utf-8-sig")

    print(f"\n✅ 完成，共評分 {len(results_df)} 筆擊球。")
    print(f"💾 評分結果輸出：{out_csv}")

    if accuracy is not None:
        print("\n📊 依 title / 檔名 推斷真實標籤（pro/good/bad）後的統計（逐筆 row）：")
        print(f"  樣本數 total = {stats_counts['total']}")
        print(f"  --> 準確度 accuracy = {accuracy*100:.2f}%")
        print(f"  TP(true good → pred good) = {stats_counts['TP']}")
        print(f"  TN(true bad  → pred bad ) = {stats_counts['TN']}")
        print(f"  FP(true bad  → pred good) = {stats_counts['FP']}")
        print(f"  FN(true good → pred bad ) = {stats_counts['FN']}")
    else:
        print("\n⚠️ title 和檔名裡都沒有出現 'pro' / 'good' / 'bad'，所以無法計算準確度，只輸出預測結果。")

    print("\n📂 影片複製統計（以影片為單位）：")
    print(f"  複製到 good/ 的影片數量 = {stats_counts['copied_good']}")
    print(f"  複製到 bad/  的影片數量 = {stats_counts['copied_bad']}")
    # print(f"  判為 good 但找不到對應影片 = {stats_counts['miss_video_good']}")
    # print(f"  判為 bad  但找不到對應影片 = {stats_counts['miss_video_bad']}")

    print(f"\n⏱️ 耗時：{time.time() - t0:.2f} 秒")


if __name__ == "__main__":
    main()
