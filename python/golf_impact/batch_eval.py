from __future__ import annotations

import argparse
import csv
import glob
import json
import os
from dataclasses import asdict
from statistics import mean

from .cli import main as detect_main
from .imu import extract_imu_impact


def _detect_one(video_path: str, output_dir: str, det_conf: float, track_conf: float):
    # Reuse existing CLI behavior by calling module internals through argv style.
    import sys

    old_argv = sys.argv[:]
    try:
        sys.argv = [
            "golf_impact.cli",
            "--video",
            video_path,
            "--output-dir",
            output_dir,
            "--det-conf",
            str(det_conf),
            "--track-conf",
            str(track_conf),
        ]
        detect_main()
    finally:
        sys.argv = old_argv

    result_path = os.path.join(output_dir, "impact_result.json")
    with open(result_path, "r", encoding="utf-8") as f:
        return json.load(f)


def parse_args():
    p = argparse.ArgumentParser(description="Batch evaluate impact detection with IMU csv ground truth.")
    p.add_argument("--data-dir", default="golf_data", help="Directory containing hit_XXXX.mp4 and hit_XXXX.csv")
    p.add_argument("--output-dir", default="runs/eval", help="Output directory for per-case and summary results")
    p.add_argument("--det-conf", type=float, default=0.5, help="Pose detection confidence")
    p.add_argument("--track-conf", type=float, default=0.5, help="Pose tracking confidence")
    return p.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    video_paths = sorted(glob.glob(os.path.join(args.data_dir, "*.mp4")))
    if not video_paths:
        raise RuntimeError(f"No mp4 files found in {args.data_dir}")

    rows = []
    for video_path in video_paths:
        stem = os.path.splitext(os.path.basename(video_path))[0]
        csv_path = os.path.join(args.data_dir, f"{stem}.csv")
        if not os.path.exists(csv_path):
            print(f"[WARN] Missing IMU csv for {stem}, skip.")
            continue

        case_dir = os.path.join(args.output_dir, stem)
        os.makedirs(case_dir, exist_ok=True)
        pred = _detect_one(video_path, case_dir, args.det_conf, args.track_conf)
        imu = extract_imu_impact(csv_path)

        gt_t = imu.impact_time_from_video_start_sec
        pred_t = float(pred["impact_time_sec"])
        dt = pred_t - gt_t
        abs_dt = abs(dt)
        fps = float(pred["fps"]) if "fps" in pred else 30.0
        frame_err = abs_dt * fps

        row = {
            "case": stem,
            "video_path": os.path.abspath(video_path),
            "imu_path": os.path.abspath(csv_path),
            "pred_impact_time_sec": pred_t,
            "gt_impact_time_sec": gt_t,
            "time_error_sec": dt,
            "abs_time_error_sec": abs_dt,
            "abs_frame_error": frame_err,
            "pred_confidence": float(pred.get("confidence", 0.0)),
            "fps": fps,
            "imu_impact_time_rel_sec": imu.impact_time_rel_sec,
            "imu_start_time_rel_sec": imu.start_time_rel_sec,
            "imu_end_time_rel_sec": imu.end_time_rel_sec,
            "imu_peak_acc_mag": imu.impact_acc_mag,
            "imu_samples": imu.sample_count,
        }
        rows.append(row)

        with open(os.path.join(case_dir, "imu_impact.json"), "w", encoding="utf-8") as f:
            json.dump(asdict(imu), f, indent=2, ensure_ascii=False)
        with open(os.path.join(case_dir, "comparison.json"), "w", encoding="utf-8") as f:
            json.dump(row, f, indent=2, ensure_ascii=False)

        print(
            f"[{stem}] pred={pred_t:.4f}s gt={gt_t:.4f}s "
            f"abs_err={abs_dt:.4f}s ({frame_err:.2f} frames)"
        )

    if not rows:
        raise RuntimeError("No valid video+csv pairs to evaluate.")

    mae_sec = mean(r["abs_time_error_sec"] for r in rows)
    mae_frame = mean(r["abs_frame_error"] for r in rows)
    summary = {
        "num_cases": len(rows),
        "mae_sec": mae_sec,
        "mae_frame": mae_frame,
        "cases": rows,
        "assumption": "IMU Time_rel start is aligned with video frame-0 time.",
    }

    with open(os.path.join(args.output_dir, "evaluation_summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, indent=2, ensure_ascii=False)

    csv_out = os.path.join(args.output_dir, "evaluation_summary.csv")
    fieldnames = list(rows[0].keys())
    with open(csv_out, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    print(f"[DONE] cases={len(rows)}")
    print(f"[DONE] MAE={mae_sec:.4f}s ({mae_frame:.2f} frames)")
    print(f"[DONE] summary json: {os.path.abspath(os.path.join(args.output_dir, 'evaluation_summary.json'))}")
    print(f"[DONE] summary csv : {os.path.abspath(csv_out)}")


if __name__ == "__main__":
    main()
