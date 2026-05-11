from dataclasses import dataclass
from typing import Dict, Optional, Tuple


Point = Tuple[float, float]


@dataclass
class FramePose:
    frame_idx: int
    timestamp_sec: float
    landmarks_xy: Dict[str, Point]
    visibility: Dict[str, float]


@dataclass
class ImpactResult:
    impact_frame: int
    impact_time_sec: float
    confidence: float
    handedness: str
    top_frame: Optional[int]
    down_frame: Optional[int]
    backswing_top_frame: Optional[int]
    lowest_wrist_frame: Optional[int]
    left_top_frame: Optional[int]
    right_top_frame: Optional[int]
    left_low_frame: Optional[int]
    right_low_frame: Optional[int]
    left_peak_speed_frame: Optional[int]
    right_peak_speed_frame: Optional[int]
    follow_through_frame: Optional[int]
