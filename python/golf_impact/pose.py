from __future__ import annotations

from typing import Dict, List, Optional, Tuple

import cv2
import mediapipe as mp

from .types import FramePose


LANDMARK_INDEX = {
    "left_shoulder": 11,
    "right_shoulder": 12,
    "left_elbow": 13,
    "right_elbow": 14,
    "left_wrist": 15,
    "right_wrist": 16,
    "left_hip": 23,
    "right_hip": 24,
}


def _extract_landmarks(result, width: int, height: int) -> Tuple[Dict[str, Tuple[float, float]], Dict[str, float]]:
    landmarks_xy: Dict[str, Tuple[float, float]] = {}
    visibility: Dict[str, float] = {}
    if not result.pose_landmarks:
        return landmarks_xy, visibility

    lms = result.pose_landmarks.landmark
    for name, idx in LANDMARK_INDEX.items():
        lm = lms[idx]
        landmarks_xy[name] = (lm.x * width, lm.y * height)
        visibility[name] = float(lm.visibility)
    return landmarks_xy, visibility


def extract_poses(video_path: str, min_detection_confidence: float = 0.5, min_tracking_confidence: float = 0.5):
    cap = cv2.VideoCapture(video_path)
    if not cap.isOpened():
        raise RuntimeError(f"Cannot open video: {video_path}")

    fps = cap.get(cv2.CAP_PROP_FPS)
    if fps <= 1e-6:
        fps = 30.0

    poses: List[FramePose] = []
    raw_frames: List = []

    mp_pose = mp.solutions.pose
    with mp_pose.Pose(
        static_image_mode=False,
        model_complexity=1,
        min_detection_confidence=min_detection_confidence,
        min_tracking_confidence=min_tracking_confidence,
    ) as pose:
        frame_idx = 0
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            raw_frames.append(frame.copy())
            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            result = pose.process(rgb)
            h, w = frame.shape[:2]
            landmarks_xy, visibility = _extract_landmarks(result, w, h)
            poses.append(
                FramePose(
                    frame_idx=frame_idx,
                    timestamp_sec=frame_idx / fps,
                    landmarks_xy=landmarks_xy,
                    visibility=visibility,
                )
            )
            frame_idx += 1

    cap.release()
    return poses, raw_frames, fps
