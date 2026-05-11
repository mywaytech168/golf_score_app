from __future__ import annotations

import csv
from dataclasses import dataclass
from typing import List


@dataclass
class ImuImpact:
    impact_time_rel_sec: float
    impact_index: int
    impact_acc_mag: float
    start_time_rel_sec: float
    end_time_rel_sec: float
    sample_count: int

    @property
    def impact_time_from_video_start_sec(self) -> float:
        # Assume IMU recording start aligns with video start.
        return self.impact_time_rel_sec - self.start_time_rel_sec


def _acc_mag(ax: float, ay: float, az: float) -> float:
    return (ax * ax + ay * ay + az * az) ** 0.5


def extract_imu_impact(csv_path: str) -> ImuImpact:
    times: List[float] = []
    mags: List[float] = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        required = {"acc_x", "acc_y", "acc_z", "Time_rel"}
        if reader.fieldnames is None or not required.issubset(set(reader.fieldnames)):
            raise RuntimeError(f"CSV missing required columns: {required}")

        for row in reader:
            t = float(row["Time_rel"])
            ax = float(row["acc_x"])
            ay = float(row["acc_y"])
            az = float(row["acc_z"])
            times.append(t)
            mags.append(_acc_mag(ax, ay, az))

    if not times:
        raise RuntimeError(f"No IMU rows in {csv_path}")

    impact_idx = max(range(len(mags)), key=lambda i: mags[i])
    return ImuImpact(
        impact_time_rel_sec=float(times[impact_idx]),
        impact_index=int(impact_idx),
        impact_acc_mag=float(mags[impact_idx]),
        start_time_rel_sec=float(min(times)),
        end_time_rel_sec=float(max(times)),
        sample_count=len(times),
    )
