from __future__ import annotations

import argparse
import csv
import json
import os
from dataclasses import asdict


def parse_args():
    p = argparse.ArgumentParser(description="Golf swing impact detector (starter).")
    p.add_argument("--video", required=True, help="Path to input video.")
    p.add_argument("--output-dir", default="runs/default", help="Output directory.")
    p.add_argument("--det-conf", type=float, default=0.5, help="Pose detection confidence.")
    p.add_argument("--track-conf", type=float, default=0.5, help="Pose tracking confidence.")
    return p.parse_args()


def main():
    args = parse_args()
    os.makedirs(args.output_dir, exist_ok=True)
    from .audio import extract_audio_amplitude
    from .impact import compute_right_wrist_metrics, estimate_impact
    from .pose import extract_poses
    from .visualize import write_annotated_video, write_audio_overlay_plots, write_metrics_plot

    poses, frames, fps = extract_poses(
        video_path=args.video,
        min_detection_confidence=args.det_conf,
        min_tracking_confidence=args.track_conf,
    )

    impact = estimate_impact(poses, fps)
    _, right_y, right_speed = compute_right_wrist_metrics(poses)
    audio_amp = extract_audio_amplitude(args.video, fps=fps, num_frames=len(frames))
    result = asdict(impact)
    result["fps"] = fps
    result["num_frames"] = len(frames)
    result["video_path"] = os.path.abspath(args.video)

    json_path = os.path.join(args.output_dir, "impact_result.json")
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)

    video_out = os.path.join(args.output_dir, "annotated.mp4")
    write_annotated_video(video_out, frames, poses, impact, fps)

    metrics_csv = os.path.join(args.output_dir, "right_wrist_metrics.csv")
    with open(metrics_csv, "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["frame", "time_ms", "right_wrist_y_px", "right_wrist_speed_px_per_frame", "audio_amplitude_norm"])
        for i, (y, v, a) in enumerate(zip(right_y.tolist(), right_speed.tolist(), audio_amp.tolist())):
            t_ms = i / max(fps, 1e-6) * 1000.0
            writer.writerow([i, t_ms, y, v, a])

    plot_path = os.path.join(args.output_dir, "right_wrist_plot.png")
    write_metrics_plot(plot_path, right_y, right_speed)
    audio_plot_frames = os.path.join(args.output_dir, "right_wrist_audio_plot_frames.png")
    audio_plot_times = os.path.join(args.output_dir, "right_wrist_audio_plot_times.png")
    top_idx = impact.top_frame if impact.top_frame is not None else 0
    fast_idx = impact.right_peak_speed_frame if impact.right_peak_speed_frame is not None else 0
    down_idx = impact.down_frame if impact.down_frame is not None else impact.impact_frame
    write_audio_overlay_plots(
        frames_out_path=audio_plot_frames,
        times_out_path=audio_plot_times,
        right_y=right_y,
        right_speed=right_speed,
        audio_amp=audio_amp,
        fps=fps,
        top_idx=top_idx,
        fast_idx=fast_idx,
        down_idx=down_idx,
    )

    print(f"[OK] top frame   : {impact.top_frame}")
    print(f"[OK] down frame  : {impact.down_frame}")
    print(f"[OK] fast frame  : {impact.right_peak_speed_frame}")
    print(f"[OK] impact frame: {impact.impact_frame}")
    print(f"[OK] impact time : {impact.impact_time_sec:.4f} s")
    print(f"[OK] handedness  : {impact.handedness}")
    print(f"[OK] json        : {json_path}")
    print(f"[OK] video       : {video_out}")
    print(f"[OK] metrics csv : {metrics_csv}")
    print(f"[OK] plot png    : {plot_path}")
    print(f"[OK] audio plot f: {audio_plot_frames}")
    print(f"[OK] audio plot t: {audio_plot_times}")
    print(f"[OK] top shot    : {os.path.join(args.output_dir, 'top_frame.jpg')}")
    print(f"[OK] down shot   : {os.path.join(args.output_dir, 'down_frame.jpg')}")


if __name__ == "__main__":
    main()
