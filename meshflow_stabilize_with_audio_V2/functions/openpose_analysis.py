
# pip install mediapipe==0.10.14
"""
步驟5：MediaPipe Pose Analysis（姿勢估計和揮桿動作分析）
功能：使用 MediaPipe 進行姿勢估計，分析高爾夫揮桿動作的各個階段

此模組提供完整的姿勢分析和揮桿動作分析能力：
- 骨架關鍵點檢測（MediaPipe COCO 33 點模型）
- 肩膀角度、髖部角度、X-factor 計算
- 揮桿階段識別（address, backswing, downswing, follow-through）
- 右手腕速度分析和關鍵幀提取
- 與音頻評分結果的整合標註

架構特點：
- MediaPoseConfig：集中管理所有配置參數
- 15+ 獨立函數實現各項分析邏輯
- 完整的類型提示和文檔
- 支援單影片和批量處理
- 輕量級 MediaPipe 框架（易於安裝和部署）
"""

import os
import sys
import cv2
import subprocess
import numpy as np
import pandas as pd
from pathlib import Path
from dataclasses import dataclass, field
from typing import Dict, Tuple, Optional, List, Any, Union
from datetime import datetime
import warnings

# 嘗試導入 MediaPipe
try:
    import mediapipe as mp
    MEDIAPIPE_AVAILABLE = True
except ImportError:
    MEDIAPIPE_AVAILABLE = False
    warnings.warn("警告：MediaPipe 不可用，請執行：pip install mediapipe")


# ============================================================================
# 姿勢關鍵點索引（MediaPipe COCO 33 點模型）
# ============================================================================

POSE_KEYPOINTS = {
    "NOSE": 0,
    "LEFT_EYE_INNER": 1,
    "LEFT_EYE": 2,
    "LEFT_EYE_OUTER": 3,
    "RIGHT_EYE_INNER": 4,
    "RIGHT_EYE": 5,
    "RIGHT_EYE_OUTER": 6,
    "LEFT_EAR": 7,
    "RIGHT_EAR": 8,
    "MOUTH_LEFT": 9,
    "MOUTH_RIGHT": 10,
    "LEFT_SHOULDER": 11,
    "RIGHT_SHOULDER": 12,
    "LEFT_ELBOW": 13,
    "RIGHT_ELBOW": 14,
    "LEFT_WRIST": 15,
    "RIGHT_WRIST": 16,
    "LEFT_PINKY": 17,
    "RIGHT_PINKY": 18,
    "LEFT_INDEX": 19,
    "RIGHT_INDEX": 20,
    "LEFT_THUMB": 21,
    "RIGHT_THUMB": 22,
    "LEFT_HIP": 23,
    "RIGHT_HIP": 24,
    "LEFT_KNEE": 25,
    "RIGHT_KNEE": 26,
    "LEFT_ANKLE": 27,
    "RIGHT_ANKLE": 28,
    "LEFT_HEEL": 29,
    "RIGHT_HEEL": 30,
    "LEFT_FOOT_INDEX": 31,
    "RIGHT_FOOT_INDEX": 32,
}


# ============================================================================
# 配置類
# ============================================================================

@dataclass
class MediaPoseConfig:
    """MediaPipe 姿勢分析配置
    
    Attributes:
        video_path: 單個影片路徑
        output_dir: 輸出目錄
        model_asset_path: MediaPose 模型資產路徑（可選）
        
        基本參數：
            rotation_90_clockwise: 是否順時針旋轉 90 度（0=否, 1=是）
            show_rule_label: 是否在影片中顯示 good/bad 標籤
            rule_label_filename: 包含評分結果的 CSV 檔名
        
        置信度參數：
            min_total_conf: 全身平均置信度下限（預設 0.30）
            keypoint_conf_threshold: 單個關鍵點置信度下限（預設 0.5）
        
        基線和速度參數：
            baseline_frames: 建立基線的幀數（預設 10）
            speed_std_factor: 速度門檻係數（預設 2.0）
            wrist_smooth_window: 右手腕平滑窗口大小（預設 5）
        
        揮桿階段參數：
            min_start_sec: 允許開始 backswing 的最小時間（預設 0.5 秒）
            start_consec_frames: 連續超過門檻的幀數（預設 5）
            low_around_impact_pre_frames: 擊球前視窗（預設 5）
            low_around_impact_post_frames: 擊球後視窗（預設 10）
        
        影片輸出參數：
            save_pose_video: 是否另存骨架影片（預設 False）
            save_pose_csv: 是否保存 pose CSV（預設 False）
            save_pose_phase_csv: 是否保存 pose_phase CSV（預設 False）
            hit_show_window: impact_frame 顯示 HIT 的範圍（預設 2）
    """
    
    video_path: str
    output_dir: Optional[str] = None
    model_asset_path: Optional[str] = None

    
    # 基本參數
    rotation_90_clockwise: int = 0
    show_rule_label: bool = True
    rule_label_filename: str = "rule_scoring_results.csv"
    
    # 置信度參數
    min_total_conf: float = 0.30
    keypoint_conf_threshold: float = 0.5
    
    # 基線和速度參數
    baseline_frames: int = 10
    speed_std_factor: float = 2.0
    wrist_smooth_window: int = 5
    
    # 揮桿階段參數
    min_start_sec: float = 0.5
    start_consec_frames: int = 5
    low_around_impact_pre_frames: int = 5
    low_around_impact_post_frames: int = 10
    
    # 影片輸出參數
    save_pose_video: bool = False
    save_pose_csv: bool = False
    save_pose_phase_csv: bool = False
    hit_show_window: int = 2
    
    def __post_init__(self) -> None:
        """驗證配置參數"""
        video_path = Path(self.video_path)
        if not video_path.exists():
            raise FileNotFoundError(f"影片不存在：{self.video_path}")
        
        if self.output_dir is None:
            self.output_dir = str(video_path.parent)
        
        Path(self.output_dir).mkdir(parents=True, exist_ok=True)
        
        if not (0 <= self.rotation_90_clockwise <= 1):
            raise ValueError("rotation_90_clockwise 必須為 0 或 1")
        
        if not (0 < self.min_total_conf < 1):
            raise ValueError("min_total_conf 必須在 0 和 1 之間")
        
        if self.baseline_frames <= 0:
            raise ValueError("baseline_frames 必須 > 0")
        
        if self.speed_std_factor <= 0:
            raise ValueError("speed_std_factor 必須 > 0")


# ============================================================================
# 工具函數
# ============================================================================

def line_angle_deg(x1: float, y1: float, x2: float, y2: float) -> float:
    """計算角度（度）
    
    計算 (x1,y1)->(x2,y2) 相對水平線的角度。
    因為影像座標 y 向下，所以用 -dy。
    
    Args:
        x1, y1, x2, y2: 兩個點的座標
        
    Returns:
        角度（度），或 NaN 如果不可計算
    """
    vals = [x1, y1, x2, y2]
    if any(np.isnan(v) for v in vals):
        return np.nan
    
    dx = x2 - x1
    dy = -(y2 - y1)
    
    if dx == 0 and dy == 0:
        return np.nan
    
    return float(np.degrees(np.arctan2(dy, dx)))


def first_index_with_consecutive_true(
    mask: Union[List[bool], np.ndarray],
    consec: int,
) -> Optional[int]:
    """尋找第一個連續 True 的起點
    
    Args:
        mask: 布爾值陣列或列表
        consec: 需要連續的個數
        
    Returns:
        第一個起點的索引，或 None 如果找不到
    """
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


def normalize_video_key(name: Optional[str]) -> str:
    """標準化影片鍵值
    
    將 'hit_001.mp4' / 'hit_001' 之類統一成小寫鍵值。
    
    Args:
        name: 影片名稱
        
    Returns:
        標準化後的鍵值
    """
    if name is None:
        return ""
    
    s = str(name).strip()
    s = s.replace("\\", "/").split("/")[-1]
    if s.lower().endswith(".mp4"):
        s = s[:-4]
    
    return s.lower()


def load_rule_labels_from_dir(input_dir: Path) -> Dict[str, str]:
    """從目錄載入評分標籤
    
    讀取包含 audio_scoring 結果的 CSV 檔案。
    
    Args:
        input_dir: 包含 rule_scoring_results.csv 的目錄
        
    Returns:
        {video_key: 'Good'/'Bad'/'Null'}
    """
    csv_path = input_dir / "rule_scoring_results.csv"
    if not csv_path.exists():
        return {}
    
    try:
        df_rule = pd.read_csv(csv_path, encoding="utf-8-sig")
    except Exception:
        try:
            df_rule = pd.read_csv(csv_path, encoding="utf-8")
        except Exception:
            return {}
    
    if df_rule.empty or "video_key" not in df_rule.columns or "pred_goodbad" not in df_rule.columns:
        return {}
    
    mapping = {}
    for _, row in df_rule.iterrows():
        k_norm = normalize_video_key(row["video_key"])
        if not k_norm:
            continue
        
        v_low = str(row["pred_goodbad"]).lower().strip()
        if v_low == "good":
            mapping[k_norm] = "Good"
        elif v_low == "bad":
            mapping[k_norm] = "Bad"
        else:
            mapping[k_norm] = "Null"
    
    return mapping


def draw_top_right_label(frame: np.ndarray, text: str) -> None:
    """在影片右上角繪製標籤
    
    Args:
        frame: 影像幀
        text: 要顯示的文字
    """
    if not text or str(text).strip() == "":
        text = "Null"
    
    text = str(text).strip()
    text_lower = text.lower()
    
    if text_lower == "good":
        color = (0, 255, 0)
    elif text_lower == "bad":
        color = (0, 0, 255)
    else:
        color = (200, 200, 200)
    
    font = cv2.FONT_HERSHEY_SIMPLEX
    scale = 0.9
    thickness = 3
    
    (tw, th), baseline = cv2.getTextSize(text, font, scale, thickness)
    h, w = frame.shape[:2]
    x = w - 10 - tw
    y = 10 + th
    
    pad = 6
    x1 = max(0, x - pad)
    y1 = max(0, y - th - pad)
    x2 = min(w - 1, x + tw + pad)
    y2 = min(h - 1, y + baseline + pad)
    
    cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 0, 0), -1)
    cv2.putText(frame, text, (x, y), font, scale, (0, 0, 0), thickness + 2, cv2.LINE_AA)
    cv2.putText(frame, text, (x, y), font, scale, color, thickness, cv2.LINE_AA)


# MediaPipe COCO 33 點模型的骨架連接
# 參考 OpenPose BODY_25 的視覺風格調整
POSE_CONNECTIONS = [
    # 頭部和軀幹
    (0, 1), (0, 2), (1, 3), (2, 4),  # 鼻子 - 眼睛
    (5, 6), (5, 7), (7, 9),  # 耳朵
    # 軀幹和手臂
    (11, 13), (13, 15),  # 左肩 - 左肘 - 左腕
    (12, 14), (14, 16),  # 右肩 - 右肘 - 右腕
    (11, 12),  # 肩膀連接
    # 手部詳細點
    (15, 17), (15, 19), (15, 21),  # 左腕 - 左手
    (16, 18), (16, 20), (16, 22),  # 右腕 - 右手
    # 軀幹到髖部
    (11, 23), (12, 24),  # 肩膀 - 髖部
    (23, 24),  # 髖部連接
    # 腿部
    (23, 25), (25, 27), (27, 29), (29, 31),  # 左髖 - 左膝 - 左踝 - 左腳
    (24, 26), (26, 28), (28, 30), (30, 32),  # 右髖 - 右膝 - 右踝 - 右腳
]


def draw_pose_skeleton(
    frame: np.ndarray,
    pose_results: Any,
    min_detection_confidence: float = 0.5,
) -> None:
    """在幀上繪製姿勢骨架（參考 OpenPose 視覺風格）
    
    Args:
        frame: 影像幀 (BGR)
        pose_results: MediaPipe 的 pose_results 對象
        min_detection_confidence: 最小置信度閾值
    """
    if pose_results.pose_landmarks is None:
        return
    
    landmarks = pose_results.pose_landmarks.landmark
    h, w = frame.shape[:2]
    
    # OpenPose 風格的顏色方案
    line_color = (0, 255, 255)  # 青色 (BGR)
    point_color = (0, 255, 255)  # 青色
    
    # 繪製連接線（線條粗細和 OpenPose 相似）
    for connection in POSE_CONNECTIONS:
        start_idx, end_idx = connection
        
        if start_idx >= len(landmarks) or end_idx >= len(landmarks):
            continue
        
        start_lm = landmarks[start_idx]
        end_lm = landmarks[end_idx]
        
        if start_lm.visibility < min_detection_confidence or end_lm.visibility < min_detection_confidence:
            continue
        
        start_pos = (int(start_lm.x * w), int(start_lm.y * h))
        end_pos = (int(end_lm.x * w), int(end_lm.y * h))
        
        # 使用抗鋸齒線條，粗細 4 像素
        cv2.line(frame, start_pos, end_pos, line_color, 4, cv2.LINE_AA)
    
    # 計算並繪製虛擬的脖子（NOSE 和肩膀中點）
    nose_lm = landmarks[POSE_KEYPOINTS["NOSE"]]
    l_shoulder_lm = landmarks[POSE_KEYPOINTS["LEFT_SHOULDER"]]
    r_shoulder_lm = landmarks[POSE_KEYPOINTS["RIGHT_SHOULDER"]]
    
    if (nose_lm.visibility >= min_detection_confidence and 
        l_shoulder_lm.visibility >= min_detection_confidence and
        r_shoulder_lm.visibility >= min_detection_confidence):
        
        # 計算脖子位置（兩肩中點）
        neck_x = (l_shoulder_lm.x + r_shoulder_lm.x) / 2 * w
        neck_y = (l_shoulder_lm.y + r_shoulder_lm.y) / 2 * h
        
        # 畫鼻子到脖子
        nose_pos = (int(nose_lm.x * w), int(nose_lm.y * h))
        neck_pos = (int(neck_x), int(neck_y))
        cv2.line(frame, nose_pos, neck_pos, line_color, 4, cv2.LINE_AA)
    
    # 繪製關鍵點圓圈（參考 OpenPose 的點大小）
    for i, landmark in enumerate(landmarks):
        if landmark.visibility < min_detection_confidence:
            continue
        
        x = int(landmark.x * w)
        y = int(landmark.y * h)
        
        # 使用統一的點顏色和大小（類似 OpenPose）
        cv2.circle(frame, (x, y), 6, point_color, -1)


def extract_pose_keypoints(
    frame: np.ndarray,
    pose_detector: Any,
    config: MediaPoseConfig,
) -> Dict[str, Any]:
    """從幀中提取姿勢關鍵點
    
    Args:
        frame: 影像幀 (BGR 格式)
        pose_detector: MediaPipe Pose detector 對象
        config: 配置對象
        
    Returns:
        包含所有關鍵點和角度的字典
    """
    result = {
        "mean_conf": np.nan,
        "shoulder_angle": np.nan,
        "hip_angle": np.nan,
        "x_factor": np.nan,
    }
    
    # 各關鍵點座標
    for key in ["nose", "l_shoulder", "r_shoulder", "l_hip", "r_hip", "l_wrist", "r_wrist"]:
        result[f"{key}_x"] = np.nan
        result[f"{key}_y"] = np.nan
    
    try:
        # 轉換為 RGB（MediaPipe 需要）
        frame_rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        h, w = frame.shape[:2]
        
        # 運行 MediaPipe 檢測
        results = pose_detector.process(frame_rgb)
        
        if results.pose_landmarks is None:
            return result
        
        landmarks = results.pose_landmarks.landmark
        
        # 計算平均置信度
        confidences = [lm.visibility for lm in landmarks if lm.visibility > 0]
        if not confidences:
            return result
        
        mean_conf = float(np.mean(confidences))
        
        if mean_conf < config.min_total_conf:
            return result
        
        result["mean_conf"] = mean_conf
        
        def get_xy(idx: int) -> Tuple[float, float]:
            if idx >= len(landmarks):
                return np.nan, np.nan
            lm = landmarks[idx]
            if lm.visibility < config.keypoint_conf_threshold:
                return np.nan, np.nan
            # MediaPipe 返回歸一化座標，需要轉換回像素座標
            x = lm.x * w
            y = lm.y * h
            return float(x), float(y)
        
        # 提取關鍵點（使用 MediaPipe 索引）
        result["nose_x"], result["nose_y"] = get_xy(POSE_KEYPOINTS["NOSE"])
        result["l_shoulder_x"], result["l_shoulder_y"] = get_xy(POSE_KEYPOINTS["LEFT_SHOULDER"])
        result["r_shoulder_x"], result["r_shoulder_y"] = get_xy(POSE_KEYPOINTS["RIGHT_SHOULDER"])
        result["l_hip_x"], result["l_hip_y"] = get_xy(POSE_KEYPOINTS["LEFT_HIP"])
        result["r_hip_x"], result["r_hip_y"] = get_xy(POSE_KEYPOINTS["RIGHT_HIP"])
        result["l_wrist_x"], result["l_wrist_y"] = get_xy(POSE_KEYPOINTS["LEFT_WRIST"])
        result["r_wrist_x"], result["r_wrist_y"] = get_xy(POSE_KEYPOINTS["RIGHT_WRIST"])
        
        # 計算角度
        shoulder_angle = line_angle_deg(
            result["l_shoulder_x"], result["l_shoulder_y"],
            result["r_shoulder_x"], result["r_shoulder_y"]
        )
        hip_angle = line_angle_deg(
            result["l_hip_x"], result["l_hip_y"],
            result["r_hip_x"], result["r_hip_y"]
        )
        
        result["shoulder_angle"] = shoulder_angle
        result["hip_angle"] = hip_angle
        
        if not (np.isnan(shoulder_angle) or np.isnan(hip_angle)):
            result["x_factor"] = shoulder_angle - hip_angle
        
        # 保存原始 results 用於繪製
        result["_pose_results"] = results
        
    except Exception as e:
        warnings.warn(f"姿勢提取失敗：{e}")
        result["_pose_results"] = None
    
    return result


def analyze_swing_phases(df: pd.DataFrame, config: MediaPoseConfig, fps: float) -> Dict[str, Any]:
    """分析揮桿階段
    
    根據右手腕速度和軌跡分析揮桿的各個階段。
    
    Args:
        df: 包含姿勢數據的 DataFrame
        config: 配置對象
        fps: 幀率
        
    Returns:
        包含階段分析結果的字典
    """
    result = {
        "success": False,
        "df": df,
        "start_frame": None,
        "top_frame": None,
        "impact_frame": None,
        "low_frame": None,
    }
    
    if len(df) < 5:
        df["phase"] = "unknown"
        return result
    
    try:
        # 解包角度
        s_rad = np.deg2rad(df["shoulder_angle"].ffill().bfill())
        h_rad = np.deg2rad(df["hip_angle"].ffill().bfill())
        s_unwrap = np.unwrap(s_rad)
        h_unwrap = np.unwrap(h_rad)
        x_unwrap = s_unwrap - h_unwrap
        df["x_factor_unwrap"] = np.rad2deg(x_unwrap)
        
        # 右手腕軌跡和平滑
        rw_x = df["r_wrist_x"]
        rw_y = df["r_wrist_y"]
        
        rw_x_f = rw_x.interpolate().bfill().ffill()
        rw_y_f = rw_y.interpolate().bfill().ffill()
        
        rw_x_s = rw_x_f.rolling(window=config.wrist_smooth_window, min_periods=1, center=True).mean()
        rw_y_s = rw_y_f.rolling(window=config.wrist_smooth_window, min_periods=1, center=True).mean()
        df["r_wrist_y_smooth"] = rw_y_s
        
        # 計算速度
        dx = rw_x_s.diff()
        dy = rw_y_s.diff()
        df["r_wrist_speed"] = np.sqrt(dx**2 + dy**2) * fps
        
        if not df["r_wrist_speed"].notna().any():
            df["phase"] = "unknown"
            return result
        
        # 建立基線和門檻
        baseline_len = min(config.baseline_frames, max(3, len(df) // 3))
        baseline = df["r_wrist_speed"].iloc[:baseline_len]
        threshold = baseline.mean() + config.speed_std_factor * baseline.std()
        
        # 尋找 backswing 起點
        min_start_frame = int(round(config.min_start_sec * fps))
        eligible = df["frame"].values >= min_start_frame
        over_th = (df["r_wrist_speed"].values > threshold) & eligible
        
        start_i = first_index_with_consecutive_true(over_th, config.start_consec_frames)
        if start_i is None:
            start_i = 0
            start_frame = int(df["frame"].iloc[0])
        else:
            start_frame = int(df.loc[start_i, "frame"])
        
        result["start_frame"] = start_frame
        
        # 尋找 impact frame（速度最高）
        mask_from_start = df["frame"] >= start_frame
        if mask_from_start.any():
            impact_idx = df.loc[mask_from_start, "r_wrist_speed"].idxmax()
            impact_frame = int(df.loc[impact_idx, "frame"])
            impact_i = impact_idx
        else:
            impact_i = 0
            impact_frame = start_frame
        
        result["impact_frame"] = impact_frame
        
        # 尋找 top frame（上桿頂點 - 手最高）
        lo_top = min(start_i, impact_i)
        hi_top = max(start_i, impact_i)
        top_sub = df.iloc[lo_top:hi_top+1]
        if len(top_sub) > 0:
            top_i = top_sub["r_wrist_y_smooth"].idxmin()
            top_frame = int(df.loc[top_i, "frame"])
        else:
            top_i = impact_i
            top_frame = impact_frame
        
        result["top_frame"] = top_frame
        
        # 尋找 low frame（下桿底部 - 手最低）
        lo_low_i = max(impact_i - config.low_around_impact_pre_frames, 0)
        hi_low_i = min(impact_i + config.low_around_impact_post_frames, len(df) - 1)
        low_sub = df.iloc[lo_low_i:hi_low_i+1]
        if len(low_sub) > 0:
            low_i = low_sub["r_wrist_y_smooth"].idxmax()
            low_frame = int(df.loc[low_i, "frame"])
        else:
            low_i = impact_i
            low_frame = impact_frame
        
        result["low_frame"] = low_frame
        
        # 標記各幀的階段
        def label_phase(f: int) -> str:
            if f < start_frame:
                return "address"
            elif f < top_frame:
                return "backswing"
            elif f <= low_frame:
                return "downswing"
            else:
                return "follow_through"
        
        df["phase"] = df["frame"].apply(label_phase)
        df["start_frame"] = start_frame
        df["top_frame"] = top_frame
        df["impact_frame"] = impact_frame
        df["low_frame"] = low_frame
        
        result["success"] = True
        result["df"] = df
        
    except Exception as e:
        warnings.warn(f"揮桿階段分析失敗：{e}")
        df["phase"] = "unknown"
    
    return result


# ============================================================================
# MediaPipe Pose 初始化
# ============================================================================

def initialize_pose_detector(config: MediaPoseConfig) -> Any:
    """初始化 MediaPipe Pose 檢測器
    
    Args:
        config: 配置對象
        
    Returns:
        初始化的 MediaPipe Pose detector
        
    Raises:
        ImportError: 若 MediaPipe 未安裝
        RuntimeError: 若初始化失敗
    """
    try:
        import mediapipe as mp
        
        # 使用 mp.solutions.pose 的更簡單 API
        pose = mp.solutions.pose.Pose(
            static_image_mode=False,
            model_complexity=1,  # 0=輕量, 1=完整, 2=重量
            smooth_landmarks=True,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5
        )
        
        print("✓ MediaPipe Pose detector 初始化成功")
        return pose
        
    except ImportError as e:
        raise ImportError(
            f"未安裝 MediaPipe。請運行：pip install mediapipe"
        ) from e
    except Exception as e:
        raise RuntimeError(f"MediaPipe Pose detector 初始化失敗：{e}") from e


# ============================================================================
# 公開 API
# ============================================================================

def run_openpose_analysis(config: MediaPoseConfig) -> pd.DataFrame:
    """執行 MediaPipe 姿勢分析（公開 API）
    
    對單個影片進行完整的姿勢估計和揮桿動作分析。
    
    Args:
        config: MediaPoseConfig 配置對象
        
    Returns:
        完整分析結果 DataFrame
        
    Raises:
        RuntimeError: 若 OpenPose 不可用
        FileNotFoundError: 若影片不存在
        
    Examples:
        >>> config = OpenPoseConfig(
        ...     video_path="swing_001.mp4",
        ...     output_dir="./output"
        ... )
        >>> results_df = run_openpose_analysis(config)
        >>> print(f"分析完成：{len(results_df)} 幀")
    """
    if not MEDIAPIPE_AVAILABLE:
        raise RuntimeError("MediaPipe 不可用，請執行：pip install mediapipe")
    
    print("\n" + "="*80)
    print("🧑 MediaPipe 姿勢分析 (mp.solutions.pose)")
    print("="*80)
    
    video_path = Path(config.video_path)
    base_name = video_path.stem
    output_dir = Path(config.output_dir)
    
    print(f"📽️ 影片：{video_path.name}")
    print(f"📁 輸出：{output_dir}")
    
    try:
        # 開啟影片
        cap = cv2.VideoCapture(str(video_path))
        if not cap.isOpened():
            raise FileNotFoundError(f"無法開啟影片：{video_path}")
        
        fps = cap.get(cv2.CAP_PROP_FPS)
        width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
        
        print(f"🎬 FPS: {fps}, 解析度: {width}x{height}")
        
        # 載入規則標籤
        rule_map = {}
        if config.show_rule_label:
            rule_map = load_rule_labels_from_dir(video_path.parent)
        
        rule_label = rule_map.get(normalize_video_key(base_name), "Null")
        
        # 初始化 MediaPipe Pose detector
        pose_detector = initialize_pose_detector(config)
        
        # 視頻寫入器
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        tmp_pose_path = output_dir / f"{base_name}_tmp_pose.mp4"
        
        if config.rotation_90_clockwise == 1:
            writer = cv2.VideoWriter(str(tmp_pose_path), fourcc, fps, (height, width))
        else:
            writer = cv2.VideoWriter(str(tmp_pose_path), fourcc, fps, (width, height))
        
        # 幀處理和數據收集
        rows = []
        frame_idx = 0
        
        print("⛳ 正在進行姿勢估計...")
        
        while True:
            ret, frame = cap.read()
            if not ret:
                break
            
            if config.rotation_90_clockwise == 1:
                frame = cv2.rotate(frame, cv2.ROTATE_90_CLOCKWISE)
            
            # 提取姿勢
            pose_data = extract_pose_keypoints(frame, pose_detector, config)
            
            # 繪製骨架
            out_frame = frame.copy()
            
            # 繪製姿勢骨架
            if pose_data.get("_pose_results") is not None:
                draw_pose_skeleton(out_frame, pose_data["_pose_results"], config.keypoint_conf_threshold)
            
            # 顯示角度信息
            shoulder_text = f"Shoulder: {pose_data['shoulder_angle']:6.1f} deg" if not np.isnan(pose_data['shoulder_angle']) else "Shoulder: ---"
            hip_text = f"Hip:      {pose_data['hip_angle']:6.1f} deg" if not np.isnan(pose_data['hip_angle']) else "Hip:      ---"
            x_factor_text = f"X-factor: {pose_data['x_factor']:6.1f} deg" if not np.isnan(pose_data['x_factor']) else "X-factor: ---"
            
            y0 = 30
            dy = 25
            for i, txt in enumerate([shoulder_text, hip_text, x_factor_text]):
                cv2.putText(out_frame, txt, (10, y0 + i * dy), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2, cv2.LINE_AA)
            
            if config.show_rule_label:
                draw_top_right_label(out_frame, rule_label)
            
            writer.write(out_frame)
            
            # 記錄數據
            t_sec = frame_idx / fps if fps > 0 else 0.0
            rows.append({
                "frame": frame_idx,
                "time_sec": t_sec,
                "mean_conf": pose_data["mean_conf"],
                "shoulder_angle": pose_data["shoulder_angle"],
                "hip_angle": pose_data["hip_angle"],
                "x_factor": pose_data["x_factor"],
                "nose_x": pose_data["nose_x"],
                "nose_y": pose_data["nose_y"],
                "l_shoulder_x": pose_data["l_shoulder_x"],
                "l_shoulder_y": pose_data["l_shoulder_y"],
                "r_shoulder_x": pose_data["r_shoulder_x"],
                "r_shoulder_y": pose_data["r_shoulder_y"],
                "l_hip_x": pose_data["l_hip_x"],
                "l_hip_y": pose_data["l_hip_y"],
                "r_hip_x": pose_data["r_hip_x"],
                "r_hip_y": pose_data["r_hip_y"],
                "l_wrist_x": pose_data["l_wrist_x"],
                "l_wrist_y": pose_data["l_wrist_y"],
                "r_wrist_x": pose_data["r_wrist_x"],
                "r_wrist_y": pose_data["r_wrist_y"],
            })
            
            frame_idx += 1
        
        cap.release()
        writer.release()
        
        # 轉成 DataFrame
        if not rows:
            raise ValueError("未能提取任何有效的姿勢數據")
        
        df = pd.DataFrame(rows)
        
        # 儲存 pose CSV
        if config.save_pose_csv:
            pose_csv_path = output_dir / f"{base_name}_pose.csv"
            df.to_csv(pose_csv_path, index=False, encoding="utf-8-sig")
            print(f"💾 已保存 pose CSV：{pose_csv_path}")
        
        # 分析揮桿階段
        print("🎯 正在分析揮桿階段...")
        phase_result = analyze_swing_phases(df, config, fps)
        df = phase_result["df"]
        
        if phase_result["success"]:
            print(f"✅ 揮桿階段：address→{phase_result['start_frame']}，"
                  f"backswing→{phase_result['top_frame']}，"
                  f"impact→{phase_result['impact_frame']}，"
                  f"low→{phase_result['low_frame']}")
        
        # 儲存 pose_phase CSV
        if config.save_pose_phase_csv:
            pose_phase_csv_path = output_dir / f"{base_name}_pose_phase.csv"
            df.to_csv(pose_phase_csv_path, index=False, encoding="utf-8-sig")
            print(f"💾 已保存 pose_phase CSV：{pose_phase_csv_path}")
        
        # 產生帶階段標籤的影片
        print("🎥 正在產生帶階段標籤的影片...")
        
        phase_by_frame = dict(zip(df["frame"].values, df["phase"].values))
        impact_frame_value = int(df["impact_frame"].iloc[0]) if "impact_frame" in df.columns else -999999
        
        cap2 = cv2.VideoCapture(str(tmp_pose_path))
        tmp_phase_path = output_dir / f"{base_name}_tmp_phase.mp4"
        phase_video_path = output_dir / f"{base_name}_pose_phase.mp4"
        
        width2 = int(cap2.get(cv2.CAP_PROP_FRAME_WIDTH))
        height2 = int(cap2.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps2 = cap2.get(cv2.CAP_PROP_FPS)
        
        writer2 = cv2.VideoWriter(str(tmp_phase_path), fourcc, fps2, (width2, height2))
        
        frame_idx2 = 0
        while True:
            ret, frame = cap2.read()
            if not ret:
                break
            
            phase = phase_by_frame.get(frame_idx2, "unknown")
            cv2.putText(frame, f"Phase: {phase}", (10, 120), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 0, 0), 2)
            
            if abs(frame_idx2 - impact_frame_value) <= config.hit_show_window:
                cv2.putText(frame, "HIT", (10, 170), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (0, 255, 255), 3)
            
            if config.show_rule_label:
                draw_top_right_label(frame, rule_label)
            
            writer2.write(frame)
            frame_idx2 += 1
        
        cap2.release()
        writer2.release()
        
        # 合併音訊
        print("🎵 正在合併音訊...")
        cmd = [
            "ffmpeg", "-y",
            "-i", str(tmp_phase_path),
            "-i", str(video_path),
            "-c:v", "copy",
            "-map", "0:v:0",
            "-map", "1:a:0?",
            "-shortest",
            str(phase_video_path),
        ]
        
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            print(f"✅ 已輸出 phase 影片：{phase_video_path}")
        except subprocess.CalledProcessError as e:
            print(f"⚠️ 音訊合併失敗，輸出無聲影片")
            import shutil
            shutil.copy(tmp_phase_path, phase_video_path)
        
        # 清理臨時文件
        tmp_pose_path.unlink(missing_ok=True)
        tmp_phase_path.unlink(missing_ok=True)
        
        print(f"\n✅ OpenPose 分析完成！共 {len(df)} 幀")
        
        return df
        
    except Exception as e:
        print(f"\n❌ OpenPose 分析失敗：{e}")
        raise


if __name__ == "__main__":
    try:
        config = MediaPoseConfig(video_path=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip_stabilized.mp4")
        results = run_openpose_analysis(config)
        print("✅ 分析完成！")
    except Exception as e:
        print(f"❌ 錯誤：{e}")
