from __future__ import annotations

import subprocess
from typing import Optional

import numpy as np


def extract_audio_amplitude(video_path: str, fps: float, num_frames: int, sample_rate: int = 16000) -> np.ndarray:
    if num_frames <= 0:
        return np.zeros((0,), dtype=np.float32)

    cmd = [
        "ffmpeg",
        "-v",
        "error",
        "-i",
        video_path,
        "-vn",
        "-ac",
        "1",
        "-ar",
        str(sample_rate),
        "-f",
        "s16le",
        "-acodec",
        "pcm_s16le",
        "-",
    ]
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except Exception:
        return np.zeros((num_frames,), dtype=np.float32)

    if proc.returncode != 0 or not proc.stdout:
        return np.zeros((num_frames,), dtype=np.float32)

    samples = np.frombuffer(proc.stdout, dtype=np.int16).astype(np.float32) / 32768.0
    if len(samples) == 0:
        return np.zeros((num_frames,), dtype=np.float32)

    samples_per_frame = sample_rate / max(fps, 1e-6)
    amps = np.zeros((num_frames,), dtype=np.float32)
    for i in range(num_frames):
        s = int(i * samples_per_frame)
        e = int((i + 1) * samples_per_frame)
        s = max(0, min(s, len(samples)))
        e = max(s + 1, min(e, len(samples)))
        chunk = samples[s:e]
        rms = float(np.sqrt(np.mean(chunk * chunk))) if len(chunk) > 0 else 0.0
        amps[i] = rms

    mx = float(np.max(amps))
    if mx > 1e-8:
        amps /= mx
    return amps
