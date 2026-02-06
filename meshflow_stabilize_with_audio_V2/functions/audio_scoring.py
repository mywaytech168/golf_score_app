"""
步驟4：Audio Scoring Classification
功能：根據音頻特徵評分，判斷擊球品質（規則式評分系統）

此模組提供高度可配置的音頻評分系統，可根據 audio_analysis 生成的 CSV 檔案：
- 對每筆擊球記錄進行特徵評分
- 使用規則型系統（基於特徵區間）判斷 good/bad
- 進行影片層級的多數投票
- 生成完整的評分結果和統計

架構特點：
- AudioScoringConfig：集中管理所有評分參數
- 15+ 獨立函數實現各項評分邏輯
- 完整的類型提示和文檔
- 支援 CSV 批量處理和統計輸出
"""

import os
import math
import shutil
import glob
import pandas as pd
from pathlib import Path
from dataclasses import dataclass, field
from typing import Dict, Tuple, Optional, List, Any
from datetime import datetime


# ============================================================================
# 配置類
# ============================================================================

@dataclass
class AudioScoringConfig:
    """音頻評分配置
    
    Attributes:
        csv_folder: CSV 資料夾路徑（denoised_summary.csv）
        video_root: 影片根目錄路徑（可選，用於複製影片）
        output_csv: 輸出評分結果 CSV 路徑
        rule_score_per_feature: 每個特徵通過的分數（預設 5.0）
        good_bad_threshold_features: 需通過幾個特徵判為 good（預設 3）
        
        RMS dBFS 區間：
            - rms_dbfs_low: RMS 下限（預設 -30.0）
            - rms_dbfs_high: RMS 上限（預設 -24.0）
            - rms_dbfs_weight: RMS 權重（預設 1.0）
        
        Spectral Centroid 區間：
            - spectral_centroid_low: 頻譜重心下限（預設 3800.0 Hz）
            - spectral_centroid_high: 頻譜重心上限（預設 4350.0 Hz）
            - spectral_centroid_weight: 權重（預設 1.0）
        
        Sharpness×Loudness 區間：
            - sharpness_hfxloud_low: 尖銳度下限（預設 2.0）
            - sharpness_hfxloud_high: 尖銳度上限（預設 3.0）
            - sharpness_hfxloud_weight: 權重（預設 1.0）
        
        High-Band Amplitude 區間：
            - highband_amp_low: 高頻帶幅度下限（預設 11.0）
            - highband_amp_high: 高頻帶幅度上限（預設 32.0）
            - highband_amp_weight: 權重（預設 1.0）
        
        Peak dBFS 區間：
            - peak_dbfs_low: 峰值下限（預設 -10.0）
            - peak_dbfs_high: 峰值上限（預設 -4.0）
            - peak_dbfs_weight: 權重（預設 1.0）
        
        video_extensions: 要掃描的影片副檔名
        create_good_bad_folders: 是否建立 good/bad 資料夾並複製影片
    """
    
    csv_folder: str
    video_root: Optional[str] = None
    output_csv: Optional[str] = None
    
    # 評分通用參數
    rule_score_per_feature: float = 5.0
    good_bad_threshold_features: int = 3
    
    # RMS dBFS 參數（-30 ~ -24 為 good/pro 主體）
    rms_dbfs_low: float = -30.0
    rms_dbfs_high: float = -24.0
    rms_dbfs_weight: float = 1.0
    
    # Spectral Centroid 參數（3.8k ~ 4.35k 為 good/pro）
    spectral_centroid_low: float = 3800.0
    spectral_centroid_high: float = 4350.0
    spectral_centroid_weight: float = 1.0
    
    # Sharpness×Loudness 參數（>2 幾乎都是好球）
    sharpness_hfxloud_low: float = 2.0
    sharpness_hfxloud_high: float = 3.0
    sharpness_hfxloud_weight: float = 1.0
    
    # High-Band Amplitude 參數（(2k~3k + 3k~4k) 平均）
    highband_amp_low: float = 11.0
    highband_amp_high: float = 32.0
    highband_amp_weight: float = 1.0
    
    # Peak dBFS 參數（-10 ~ -4 為 good/pro）
    peak_dbfs_low: float = -10.0
    peak_dbfs_high: float = -4.0
    peak_dbfs_weight: float = 1.0
    
    video_extensions: Tuple[str, ...] = (".mp4", ".mov", ".avi", ".mkv")
    save_score_txt: bool = True  # 將評分結果存成 score.txt
    
    def __post_init__(self) -> None:
        """驗證配置參數"""
        csv_path = Path(self.csv_folder)
        if not csv_path.exists():
            raise FileNotFoundError(f"CSV 資料夾不存在：{self.csv_folder}")
        
        if self.video_root:
            video_path = Path(self.video_root)
            if not video_path.exists():
                raise FileNotFoundError(f"影片根目錄不存在：{self.video_root}")
        
        if self.output_csv is None:
            self.output_csv = os.path.join(
                self.csv_folder,
                f"rule_scoring_results.csv"
            )
        
        # 驗證閾值參數
        if self.rule_score_per_feature <= 0:
            raise ValueError("rule_score_per_feature 必須 > 0")
        if self.good_bad_threshold_features <= 0:
            raise ValueError("good_bad_threshold_features 必須 > 0")
    
    def get_good_bad_threshold_score(self) -> float:
        """計算 good/bad 分數門檻"""
        return self.good_bad_threshold_features * self.rule_score_per_feature
    
    def get_rule_intervals(self) -> Dict[str, Dict[str, float]]:
        """取得所有評分規則區間"""
        return {
            "rms_dbfs": {
                "low": self.rms_dbfs_low,
                "high": self.rms_dbfs_high,
                "weight": self.rms_dbfs_weight,
            },
            "spectral_centroid": {
                "low": self.spectral_centroid_low,
                "high": self.spectral_centroid_high,
                "weight": self.spectral_centroid_weight,
            },
            "sharpness_hfxloud": {
                "low": self.sharpness_hfxloud_low,
                "high": self.sharpness_hfxloud_high,
                "weight": self.sharpness_hfxloud_weight,
            },
            "highband_amp": {
                "low": self.highband_amp_low,
                "high": self.highband_amp_high,
                "weight": self.highband_amp_weight,
            },
            "peak_dbfs": {
                "low": self.peak_dbfs_low,
                "high": self.peak_dbfs_high,
                "weight": self.peak_dbfs_weight,
            },
        }


# ============================================================================
# 核心評分函數
# ============================================================================

def rule_based_score_row(
    row: pd.Series,
    intervals: Dict[str, Dict[str, float]],
    per_feat_score: float = 5.0,
) -> Tuple[float, Dict[str, bool]]:
    """對單列資料做規則式評分
    
    根據特徵區間評估每筆擊球記錄，計算是否通過各項評分標準。
    
    Args:
        row: 一列 pandas Series（包含 audio_analysis 特徵）
        intervals: 規則區間字典 {特徵名: {low, high, weight}}
        per_feat_score: 每個特徵通過的分數
        
    Returns:
        (total_score, passes): 總分 和 各特徵是否通過字典
        
    Raises:
        KeyError: 若 CSV 缺少必要欄位
        ValueError: 若特徵值無效
    """
    score = 0.0
    passes: Dict[str, bool] = {}
    
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


def infer_group_from_string(s: Optional[str]) -> Optional[str]:
    """從字串推斷擊球品質標籤
    
    從任意字串中查找 pro/good/bad 標籤，不分大小寫。
    
    Args:
        s: 輸入字串（通常是檔名或欄位值）
        
    Returns:
        "pro"/"good"/"bad" 或 None
        
    Examples:
        >>> infer_group_from_string("video_pro_swing")
        'pro'
        >>> infer_group_from_string("BadShot_001")
        'bad'
        >>> infer_group_from_string("unknown")
        None
    """
    if not s:
        return None
    s_lower = str(s).lower()
    
    if "bad" in s_lower:
        return "bad"
    if "good" in s_lower:
        return "good"
    if "pro" in s_lower:
        return "pro"
    return None


def build_video_index(video_root: str) -> Dict[str, str]:
    """建立影片索引
    
    掃描 video_root 底下所有支援的影片檔，建立索引以便後續查詢。
    
    Args:
        video_root: 影片根目錄
        
    Returns:
        {影片名（小寫，無副檔名）: 完整路徑}
        
    Examples:
        >>> index = build_video_index("/path/to/videos")
        >>> print(index.get("swing_001"))
        '/path/to/videos/swing_001.mp4'
    """
    video_root = os.path.abspath(video_root)
    index: Dict[str, str] = {}
    
    extensions = (".mp4", ".mov", ".avi", ".mkv")
    for ext in extensions:
        pattern = os.path.join(video_root, f"**/*{ext}")
        for vpath in glob.glob(pattern, recursive=True):
            base = os.path.basename(vpath)
            key = os.path.splitext(base)[0].lower()
            if key not in index:
                index[key] = vpath
    
    return index


def calculate_highband_amplitude(row: pd.Series) -> float:
    """計算高頻帶幅度
    
    計算 2k~3k 和 3k~4k 頻帶 peak 幅度的平均值。
    
    Args:
        row: 包含 band_2k_3k_peak_amp 和 band_3k_4k_peak_amp 的 Series
        
    Returns:
        高頻帶幅度平均值
    """
    return float(
        row[["band_2k_3k_peak_amp", "band_3k_4k_peak_amp"]].mean()
    )


def prepare_row_for_scoring(
    row: pd.Series,
    csv_filename: str,
) -> Dict[str, Any]:
    """準備單行數據用於評分
    
    從原始行中提取必要資訊，生成用於評分的完整數據。
    
    Args:
        row: 原始 CSV 列
        csv_filename: CSV 檔名
        
    Returns:
        包含 clip_title、video_key、true_group 等資訊的字典
    """
    # clip_title 優先使用 title 欄位，沒有就用 csv 檔名
    if "title" in row.index:
        clip_title = str(row["title"])
    else:
        clip_title = os.path.splitext(csv_filename)[0]
    
    # video_key 用於對應影片檔案
    video_key = os.path.splitext(os.path.basename(clip_title))[0].lower()
    
    # 推斷真實標籤
    true_group = infer_group_from_string(clip_title)
    if true_group is None:
        true_group = infer_group_from_string(csv_filename)
    
    true_goodbad = "good" if true_group in ("pro", "good") else "bad" if true_group == "bad" else None
    
    return {
        "clip_title": clip_title,
        "video_key": video_key,
        "true_group": true_group,
        "true_goodbad": true_goodbad,
    }


def score_single_csv(
    csv_path: str,
    intervals: Dict[str, Dict[str, float]],
    per_feat_score: float,
    good_bad_threshold: float,
) -> Tuple[List[Dict[str, Any]], Dict[str, int]]:
    """評分單個 CSV 檔案
    
    對指定 CSV 的所有行進行評分和統計。
    
    Args:
        csv_path: CSV 檔案路徑
        intervals: 評分規則區間
        per_feat_score: 每個特徵分數
        good_bad_threshold: good/bad 分數門檻
        
    Returns:
        (結果列表, 統計信息)
    """
    csv_filename = os.path.basename(csv_path)
    csv_filename_lower = csv_filename.lower()
    
    df = pd.read_csv(csv_path)
    
    # 若有 title 欄位，排除以 "__" 開頭的 summary 列
    if "title" in df.columns:
        df = df[~df["title"].astype(str).str.startswith("__")].copy()
    
    if df.empty:
        return [], {"processed": 0}
    
    all_rows = []
    stats_counts = {"processed": 0, "tp": 0, "tn": 0, "fp": 0, "fn": 0}
    
    for _, row in df.iterrows():
        prep_data = prepare_row_for_scoring(row, csv_filename)
        
        # 規則評分
        score, passes = rule_based_score_row(row, intervals, per_feat_score)
        pred_goodbad = "good" if score >= good_bad_threshold else "bad"
        
        # 計算高頻帶幅度
        highband_amp_val = calculate_highband_amplitude(row)
        
        # 統計 confusion matrix
        if prep_data["true_goodbad"] is not None:
            stats_counts["processed"] += 1
            if prep_data["true_goodbad"] == "good" and pred_goodbad == "good":
                stats_counts["tp"] += 1
            elif prep_data["true_goodbad"] == "bad" and pred_goodbad == "bad":
                stats_counts["tn"] += 1
            elif prep_data["true_goodbad"] == "bad" and pred_goodbad == "good":
                stats_counts["fp"] += 1
            elif prep_data["true_goodbad"] == "good" and pred_goodbad == "bad":
                stats_counts["fn"] += 1
        
        result_row = {
            "source_csv": csv_filename,
            "clip_title": prep_data["clip_title"],
            "video_key": prep_data["video_key"],
            "true_group": prep_data["true_group"],
            "true_goodbad": prep_data["true_goodbad"],
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
        }
        all_rows.append(result_row)
    
    return all_rows, stats_counts


def aggregate_video_votes(results_df: pd.DataFrame) -> Dict[str, str]:
    """使用多數投票決定影片整體標籤
    
    根據分類結果的 video_key 和 pred_goodbad，進行投票。
    
    Args:
        results_df: 評分結果 DataFrame
        
    Returns:
        {video_key: "good"/"bad"}
    """
    video_votes: Dict[str, Dict[str, int]] = {}
    
    for _, row in results_df.iterrows():
        video_key = row["video_key"]
        pred_goodbad = row["pred_goodbad"]
        
        if video_key not in video_votes:
            video_votes[video_key] = {"good": 0, "bad": 0}
        video_votes[video_key][pred_goodbad] += 1
    
    video_final_label: Dict[str, str] = {}
    for key, cnt in video_votes.items():
        g = cnt.get("good", 0)
        b = cnt.get("bad", 0)
        if g == 0 and b == 0:
            continue
        
        # 若投票平手，保守判為 bad
        if b >= g:
            final_label = "bad"
        else:
            final_label = "good"
        video_final_label[key] = final_label
    
    return video_final_label


def save_scores_as_txt(
    video_index: Dict[str, str],
    results_df: pd.DataFrame,
    video_root: str,
) -> int:
    """將評分結果存為 score.txt 檔案
    
    在每個影片所在的目錄創建 score.txt，記錄該影片的評分結果。
    
    Args:
        video_index: 影片索引 {video_key: filepath}
        results_df: 評分結果 DataFrame
        video_root: 影片根目錄
        
    Returns:
        成功保存的 score.txt 檔案數
    """
    saved_count = 0
    
    print(f"\n💾 正在保存評分結果為 score.txt...")
    
    # 獲取影片分組（按 video_key）
    if "video_key" not in results_df.columns:
        print(f"⚠️  DataFrame 中沒有 video_key 欄位")
        return saved_count
    
    video_groups = results_df.groupby("video_key")
    
    for video_key, group_df in video_groups:
        src = video_index.get(video_key)
        if not src:
            print(f"  ⚠️  找不到影片：{video_key}")
            continue
        
        # 在影片所在目錄創建 score.txt
        video_dir = os.path.dirname(src)
        score_txt_path = os.path.join(video_dir, "score.txt")
        
        try:
            with open(score_txt_path, "w", encoding="utf-8") as f:
                f.write(f"影片評分結果\n")
                f.write(f"=================\n")
                f.write(f"影片鍵：{video_key}\n")
                f.write(f"影片路徑：{src}\n")
                f.write(f"評分時間：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
                f.write(f"\n評分結果統計\n")
                f.write(f"-----------------\n")
                
                if "score" in group_df.columns:
                    avg_score = group_df["score"].mean()
                    f.write(f"平均分數：{avg_score:.2f}\n")
                
                if "label" in group_df.columns:
                    good_count = (group_df["label"] == "good").sum()
                    bad_count = (group_df["label"] == "bad").sum()
                    f.write(f"Good 球數：{good_count}\n")
                    f.write(f"Bad 球數：{bad_count}\n")
                
                if "video_final_label" in group_df.columns:
                    final_label = group_df["video_final_label"].iloc[0] if len(group_df) > 0 else "未定義"
                    f.write(f"\n最終判定：{final_label}\n")
                
                f.write(f"\n詳細擊球記錄\n")
                f.write(f"-----------------\n")
                
                # 列出每筆擊球
                for idx, row in group_df.iterrows():
                    f.write(f"\n擊球 #{idx}:\n")
                    if "score" in row.index:
                        f.write(f"  分數：{row['score']}\n")
                    if "label" in row.index:
                        f.write(f"  判定：{row['label']}\n")
                    if "title" in row.index:
                        f.write(f"  標題：{row['title']}\n")
            
            print(f"  ✅ 保存成功：{score_txt_path}")
            saved_count += 1
            
        except PermissionError as e:
            print(f"  ❌ 權限拒絕：{score_txt_path}")
            print(f"     錯誤：{e}")
        except Exception as e:
            print(f"  ❌ 保存失敗：{score_txt_path}")
            print(f"     錯誤：{e}")
    
    return saved_count


def copy_videos_by_label(
    video_index: Dict[str, str],
    video_final_label: Dict[str, str],
    video_root: str,
) -> Tuple[int, int, int, int]:
    """依據標籤複製影片到 good/bad 資料夾
    
    Args:
        video_index: 影片索引
        video_final_label: 影片最終標籤 {video_key: label}
        video_root: 影片根目錄
        
    Returns:
        (copied_good, copied_bad, miss_video_good, miss_video_bad)
    """
    good_dir = os.path.join(video_root, "good")
    bad_dir = os.path.join(video_root, "bad")
    
    # 詳細日誌
    print(f"\n🔨 正在創建目錄結構:")
    print(f"  - Good 目錄: {good_dir}")
    try:
        os.makedirs(good_dir, exist_ok=True)
        print(f"  ✅ Good 目錄創建成功")
    except PermissionError as e:
        print(f"  ❌ [第 475 行] Good 目錄創建失敗 (權限拒絕): {e}")
        raise
    except Exception as e:
        print(f"  ❌ [第 475 行] Good 目錄創建失敗 (其他錯誤): {e}")
        raise
    
    print(f"  - Bad 目錄: {bad_dir}")
    try:
        os.makedirs(bad_dir, exist_ok=True)
        print(f"  ✅ Bad 目錄創建成功")
    except PermissionError as e:
        print(f"  ❌ [第 476 行] Bad 目錄創建失敗 (權限拒絕): {e}")
        raise
    except Exception as e:
        print(f"  ❌ [第 476 行] Bad 目錄創建失敗 (其他錯誤): {e}")
        raise
    
    copied_good = 0
    copied_bad = 0
    miss_video_good = 0
    miss_video_bad = 0
    
    for key, label in video_final_label.items():
        src = video_index.get(key)
        if not src:
            if label == "good":
                miss_video_good += 1
            else:
                miss_video_bad += 1
            continue
        
        dst_dir = good_dir if label == "good" else bad_dir
        dst = os.path.join(dst_dir, os.path.basename(src))
        
        if not os.path.exists(dst):
            label_name = "good" if label == "good" else "bad"
            print(f"  📋 複製到 {label_name}: {os.path.basename(src)}")
            try:
                shutil.copy2(src, dst)
                if label == "good":
                    copied_good += 1
                else:
                    copied_bad += 1
                print(f"    ✅ 複製成功")
            except PermissionError as e:
                print(f"    ❌ [第 518 行] 複製失敗 (權限拒絕)")
                print(f"       源: {src}")
                print(f"       目標: {dst}")
                print(f"       錯誤: {e}")
                raise
            except Exception as e:
                print(f"    ❌ [第 518 行] 複製失敗 (其他錯誤): {e}")
                print(f"       源: {src}")
                print(f"       目標: {dst}")
                raise
    
    return copied_good, copied_bad, miss_video_good, miss_video_bad


def calculate_accuracy_metrics(
    stats_counts: Dict[str, int],
) -> Tuple[Optional[float], float, float, float]:
    """計算評分準確度指標
    
    Args:
        stats_counts: 包含 tp/tn/fp/fn 的統計字典
        
    Returns:
        (accuracy, precision, recall, f1_score) 或 (None, 0, 0, 0)
    """
    total = stats_counts.get("processed", 0)
    if total == 0:
        return None, 0.0, 0.0, 0.0
    
    tp = stats_counts.get("tp", 0)
    tn = stats_counts.get("tn", 0)
    fp = stats_counts.get("fp", 0)
    fn = stats_counts.get("fn", 0)
    
    accuracy = (tp + tn) / total
    precision = tp / (tp + fp) if (tp + fp) > 0 else 0.0
    recall = tp / (tp + fn) if (tp + fn) > 0 else 0.0
    f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0.0
    
    return accuracy, precision, recall, f1


def process_audio_scoring(config: AudioScoringConfig) -> Tuple[pd.DataFrame, Dict[str, Any]]:
    """處理音頻評分主流程
    
    對指定資料夾的所有 denoised_summary.csv 進行評分。
    
    Args:
        config: AudioScoringConfig 配置對象
        
    Returns:
        (結果 DataFrame, 統計信息字典)
        
    Raises:
        FileNotFoundError: 若 CSV 資料夾不存在或無 CSV 檔案
    """
    csv_folder = os.path.abspath(config.csv_folder)
    csv_paths = sorted(glob.glob(os.path.join(csv_folder, "*denoised_summary.csv")))
    
    if not csv_paths:
        raise FileNotFoundError(f"在資料夾中找不到任何 *denoised_summary.csv：{csv_folder}")
    
    intervals = config.get_rule_intervals()
    good_bad_threshold = config.get_good_bad_threshold_score()
    
    # 逐個評分 CSV
    all_results = []
    total_stats = {
        "tp": 0,
        "tn": 0,
        "fp": 0,
        "fn": 0,
        "total_rows": 0,
        "processed_rows": 0,
    }
    
    for csv_path in csv_paths:
        results, stats = score_single_csv(
            csv_path,
            intervals,
            config.rule_score_per_feature,
            good_bad_threshold,
        )
        all_results.extend(results)
        total_stats["processed_rows"] += stats.get("processed", 0)
        for key in ["tp", "tn", "fp", "fn"]:
            total_stats[key] += stats.get(key, 0)
        total_stats["total_rows"] += len(results)
    
    # 轉成 DataFrame
    results_df = pd.DataFrame(all_results) if all_results else pd.DataFrame()
    
    if not results_df.empty:
        # 影片層級多數投票
        video_final_label = aggregate_video_votes(results_df)
        results_df["video_final_label"] = results_df["video_key"].map(
            lambda k: video_final_label.get(k, None)
        )
        
        # 複製影片
        if config.video_root and config.save_score_txt:
            video_index = build_video_index(config.video_root)
            saved_score_files = save_scores_as_txt(
                video_index,
                results_df,
                config.video_root,
            )
            total_stats["saved_score_files"] = saved_score_files
    
    return results_df, total_stats


def print_scoring_summary(
    config: AudioScoringConfig,
    results_df: pd.DataFrame,
    stats: Dict[str, Any],
) -> None:
    """列印評分摘要報告
    
    Args:
        config: 配置對象
        results_df: 結果 DataFrame
        stats: 統計信息
    """
    print("\n" + "="*80)
    print("⭐ 音頻評分結果摘要")
    print("="*80)
    
    print(f"\n📂 CSV 資料夾：{config.csv_folder}")
    if config.video_root:
        print(f"🎥 影片根目錄：{config.video_root}")
    print(f"🔧 每特徵分數：{config.rule_score_per_feature}")
    print(f"🔧 good/bad 門檻（分數）：{config.get_good_bad_threshold_score()} "
          f"(通過 {config.good_bad_threshold_features} 個特徵)")
    
    print("\n👉 規則區間：")
    intervals = config.get_rule_intervals()
    for feat, cfg in intervals.items():
        print(f"  {feat:20s}: [{cfg.get('low', '-∞')}, {cfg.get('high', '∞')}]  "
              f"weight={cfg.get('weight', 1.0)}")
    
    print(f"\n✅ 完成，共評分 {len(results_df)} 筆擊球。")
    print(f"💾 評分結果輸出：{config.output_csv}")
    
    total_rows = stats.get("total_rows", 0)
    processed_rows = stats.get("processed_rows", 0)
    
    if processed_rows > 0:
        accuracy, precision, recall, f1 = calculate_accuracy_metrics(stats)
        print(f"\n📊 評分準確度統計（逐筆 row，基於 title/檔名推斷標籤）：")
        print(f"  樣本數 = {processed_rows}")
        print(f"  準確度 accuracy = {accuracy*100:.2f}%")
        print(f"  精準度 precision = {precision*100:.2f}%")
        print(f"  召回率 recall = {recall*100:.2f}%")
        print(f"  F1 分數 = {f1:.4f}")
        print(f"  TP(good→pred good) = {stats.get('tp', 0)}")
        print(f"  TN(bad→pred bad) = {stats.get('tn', 0)}")
        print(f"  FP(bad→pred good) = {stats.get('fp', 0)}")
        print(f"  FN(good→pred bad) = {stats.get('fn', 0)}")
    else:
        print(f"\n⚠️ title 和檔名裡都沒有出現 'pro'/'good'/'bad'，無法計算準確度，只輸出預測結果。")
    
    if config.video_root and config.save_score_txt:
        print(f"\n📂 評分結果 (score.txt) 統計：")
        print(f"  保存的 score.txt 檔案數 = {stats.get('saved_score_files', 0)}")


# ============================================================================
# 公開 API
# ============================================================================

def run_audio_scoring(config: AudioScoringConfig) -> Dict[str, Any]:
    """執行音頻評分（公開 API）
    
    根據 audio_analysis 生成的 CSV 檔案進行音頻評分和分類。
    返回包含 audio_crispness 和 good_shot 的結果字典。
    
    Args:
        config: AudioScoringConfig 配置對象
        
    Returns:
        {
            'audio_crispness': float,  # 音頻清晰度 (0-100)
            'good_shot': bool,         # 是否為優質擊球
            'results_df': pd.DataFrame # 詳細評分結果
        }
        
    Raises:
        FileNotFoundError: 若資料夾不存在
        ValueError: 若配置無效
    """
    print("\n" + "="*80)
    print("🎯 開始音頻評分流程...")
    print("="*80)
    
    try:
        results_df, stats = process_audio_scoring(config)
        
        # 輸出結果
        print(f"\n💾 正在保存評分結果...")
        print(f"  目標路徑: {config.output_csv}")
        print(f"  行數: {len(results_df)}")
        
        try:
            results_df.to_csv(config.output_csv, index=False, encoding="utf-8-sig")
            print(f"  ✅ 評分結果保存成功")
        except PermissionError as e:
            print(f"  ❌ 保存失敗 (權限拒絕)")
            print(f"     錯誤消息: {e}")
            print(f"     錯誤信息: 無法寫入到 {config.output_csv}")
            print(f"     可能原因: 網絡共享權限不足或路徑不可寫")
            raise
        except Exception as e:
            print(f"  ❌ 保存失敗 (其他錯誤): {e}")
            raise
        
        # 計算音頻清晰度和優質擊球判定
        audio_crispness = _calculate_audio_crispness(results_df)
        good_shot = _determine_good_shot(results_df)
        
        print(f"\n📊 評分摘要:")
        print(f"  🎵 音頻清晰度 (audio_crispness): {audio_crispness:.2f}")
        print(f"  ⭐ 優質擊球 (good_shot): {good_shot}")
        
        # 列印摘要
        print_scoring_summary(config, results_df, stats)
        
        print("\n✅ 音頻評分已完成！")
        
        return {
            'audio_crispness': audio_crispness,
            'good_shot': good_shot,
            'results_df': results_df
        }
        
    except Exception as e:
        print(f"\n❌ 音頻評分失敗：{e}")
        import traceback
        print(f"\n📍 詳細錯誤追蹤:")
        print(traceback.format_exc())
        raise


def _calculate_audio_crispness(results_df: pd.DataFrame) -> float:
    """計算平均音頻清晰度
    
    基於 sharpness_hfxloud（高頻銳度）和 spectral_centroid（頻譜中心）
    計算整體音頻清晰度評分 (0-100)。
    
    Args:
        results_df: 評分結果 DataFrame
        
    Returns:
        audio_crispness: 清晰度評分 (0-100)
    """
    if results_df.empty:
        return 0.0
    
    # 規範化 sharpness_hfxloud (假設範圍 0-1 或 0-100)
    if 'sharpness_hfxloud' in results_df.columns:
        sharpness = results_df['sharpness_hfxloud'].mean()
        if sharpness > 10:  # 如果值大於 10，假設是 0-100 範圍
            sharpness = sharpness / 100.0
    else:
        sharpness = 0.5
    
    # 規範化 spectral_centroid (假設範圍 0-20000 Hz)
    if 'spectral_centroid' in results_df.columns:
        centroid = results_df['spectral_centroid'].mean()
        # 規範化到 0-1 (目標範圍 3000-6000 Hz)
        centroid_norm = min(centroid / 6000.0, 1.0) if centroid > 0 else 0.5
    else:
        centroid_norm = 0.5
    
    # 規範化 peak_dbfs (假設範圍 -60 到 0)
    if 'peak_dbfs' in results_df.columns:
        peak = results_df['peak_dbfs'].mean()
        # 規範化：-20 dBFS 為最優，越接近 0 越好
        peak_norm = max(0, min((peak + 20) / 20.0, 1.0)) if peak else 0.5
    else:
        peak_norm = 0.5
    
    # 加權計算清晰度 (0-100)
    audio_crispness = (sharpness * 0.4 + centroid_norm * 0.35 + peak_norm * 0.25) * 100.0
    
    return round(audio_crispness, 2)


def _determine_good_shot(results_df: pd.DataFrame) -> bool:
    """判定是否為優質擊球
    
    基於 good/bad 分類的多數投票結果。
    
    Args:
        results_df: 評分結果 DataFrame
        
    Returns:
        good_shot: True 表示優質擊球，False 表示普通擊球
    """
    if results_df.empty:
        return False
    
    if 'pred_goodbad' not in results_df.columns:
        return False
    
    # 計算 good 和 bad 的數量
    good_count = (results_df['pred_goodbad'] == 'good').sum()
    bad_count = (results_df['pred_goodbad'] == 'bad').sum()
    
    # 多數投票：good 數量 > bad 數量 則判為 good
    good_shot = good_count > bad_count
    
    print(f"  📈 投票結果: good={good_count}, bad={bad_count} → {'優質' if good_shot else '普通'}")
    
    return good_shot


if __name__ == "__main__":
    # 示例用法
    try:
        config = AudioScoringConfig(
            csv_folder=r"\\10.1.1.101\TekSwing\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41",
            video_root=r"\\10.1.1.101\TekSwing\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41",
        )
        result = run_audio_scoring(config)
        print(f"\n✅ 成功！結果已保存到 {config.output_csv}")
        print(f"   audio_crispness: {result['audio_crispness']}")
        print(f"   good_shot: {result['good_shot']}")
    except Exception as e:
        print(f"❌ 錯誤：{e}")
