"""
Audio PCM Peak Detection
========================
A simplified module that takes PCM audio input and detects sound peaks.
"""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass
from pathlib import Path
from typing import Tuple

import cv2
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
from scipy.signal import find_peaks, medfilt


# Signal processing parameters
AUDIO_MEDIAN_KERNEL = 9
AUDIO_SMOOTH_WIN = 9
AUDIO_BASELINE_KERNEL = 151

# Peak detection parameters
PEAK_DISTANCE_SEC = 0.45
AUDIO_HEIGHT_PERCENTILE = 90.0
AUDIO_MIN_HEIGHT = 0.04
AUDIO_PROM_SCALE = 2.0


@dataclass
class AudioPeak:
    """Audio peak information"""
    peak_idx: int
    frame: int
    time_sec: float
    value: float


def _odd(k: int) -> int:
    """Convert integer to odd number"""
    k = max(1, int(k))
    return k if (k % 2 == 1) else (k + 1)


def _moving_average(x: np.ndarray, window: int) -> np.ndarray:
    """Apply moving average filter"""
    w = max(1, int(window))
    if w <= 1 or len(x) == 0:
        return x.copy()
    pad = w // 2
    xp = np.pad(x, (pad, pad), mode="edge")
    ker = np.ones(w, dtype=float) / float(w)
    return np.convolve(xp, ker, mode="valid")


def _denoise_signal(
    raw: np.ndarray,
    median_kernel: int,
    smooth_win: int,
    baseline_kernel: int,
) -> Tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Denoise audio signal using median filter, moving average, and baseline subtraction.
    
    Args:
        raw: Raw audio signal
        median_kernel: Median filter kernel size
        smooth_win: Smoothing window size
        baseline_kernel: Baseline estimation kernel size
    
    Returns:
        Tuple of (smoothed, baseline, denoised)
    """
    med = medfilt(raw, kernel_size=_odd(median_kernel))
    smooth = _moving_average(med, smooth_win)
    baseline = medfilt(smooth, kernel_size=_odd(baseline_kernel))
    denoise = np.clip(smooth - baseline, 0.0, None)
    return smooth, baseline, denoise


def _detect_peaks(
    x: np.ndarray,
    fps: float,
    distance_sec: float,
    height_percentile: float,
    min_height: float,
    prom_scale: float,
) -> Tuple[np.ndarray, dict]:
    """
    Detect peaks in audio signal.
    
    Args:
        x: Denoised audio signal
        fps: Sample rate (frames per second)
        distance_sec: Minimum distance between peaks in seconds
        height_percentile: Height threshold percentile
        min_height: Minimum peak height
        prom_scale: Prominence scale factor
    
    Returns:
        Tuple of (peak_frames, peak_config_dict)
    """
    if len(x) < 3:
        return np.array([], dtype=int), {
            "height": 0.0,
            "prominence": 0.0,
            "distance_frames": 1,
        }
    
    med = float(np.median(x))
    mad = float(np.median(np.abs(x - med))) + 1e-6
    height = max(float(np.percentile(x, height_percentile)), float(min_height))
    prominence = max(float(prom_scale * mad), 0.05 * float(np.max(x)))
    distance = max(1, int(distance_sec * fps))
    
    peaks, props = find_peaks(x, height=height, prominence=prominence, distance=distance)
    
    return peaks.astype(int), {
        "height": float(height),
        "prominence": float(prominence),
        "distance_frames": int(distance),
        "num_peaks": int(len(peaks)),
        "peak_heights_mean": float(
            np.mean(props.get("peak_heights", [0.0])) if len(peaks) else 0.0
        ),
    }


def _plot_signal(
    path: Path,
    fps: float,
    raw: np.ndarray,
    smooth: np.ndarray,
    dn: np.ndarray,
    peaks: np.ndarray,
    title: str,
    ylabel: str,
) -> None:
    """
    Plot audio signal with peaks.
    
    Args:
        path: Output file path
        fps: Sample rate (frames per second)
        raw: Raw audio signal
        smooth: Smoothed audio signal
        dn: Denoised audio signal
        peaks: Peak frame indices
        title: Plot title
        ylabel: Y-axis label
    """
    t = np.arange(len(raw), dtype=float) / max(fps, 1e-6)
    plt.figure(figsize=(18, 6))
    plt.plot(t, raw, color="#4f4f4f", linewidth=0.8, label=f"{ylabel}_raw")
    plt.plot(t, smooth, color="#5dade2", linewidth=1.2, label=f"{ylabel}_smooth")
    plt.plot(t, dn, color="#00ff66", linewidth=1.0, label=f"{ylabel}_denoised")
    if len(peaks) > 0:
        plt.scatter(t[peaks], dn[peaks], s=20, color="#ffd166", label=f"{ylabel}_peaks")
    plt.title(title)
    plt.xlabel("Time (sec)")
    plt.ylabel(ylabel)
    plt.grid(alpha=0.25)
    plt.legend(loc="upper right")
    plt.tight_layout()
    plt.savefig(path, dpi=160)
    plt.close()


def detect_audio_peaks(
    audio_signal: np.ndarray,
    sample_rate: float = 16000.0,
    median_kernel: int = AUDIO_MEDIAN_KERNEL,
    smooth_win: int = AUDIO_SMOOTH_WIN,
    baseline_kernel: int = AUDIO_BASELINE_KERNEL,
    peak_distance_sec: float = PEAK_DISTANCE_SEC,
    height_percentile: float = AUDIO_HEIGHT_PERCENTILE,
    min_height: float = AUDIO_MIN_HEIGHT,
    prom_scale: float = AUDIO_PROM_SCALE,
) -> Tuple[list[AudioPeak], dict, dict]:
    """
    Detect peaks in PCM audio signal.
    
    Args:
        audio_signal: PCM audio samples (1D numpy array or list)
        sample_rate: Sample rate in Hz (default: 16000 Hz)
        median_kernel: Median filter kernel size
        smooth_win: Smoothing window size
        baseline_kernel: Baseline estimation kernel size
        peak_distance_sec: Minimum distance between peaks in seconds
        height_percentile: Height threshold percentile
        min_height: Minimum peak height
        prom_scale: Prominence scale factor
    
    Returns:
        Tuple of (list of AudioPeak objects, config dict, signal_dict)
    """
    # Ensure input is numpy array
    audio_raw = np.asarray(audio_signal, dtype=float)
    
    if len(audio_raw) == 0:
        return [], {}, {}
    
    # Denoise signal
    audio_smooth, audio_base, audio_dn = _denoise_signal(
        audio_raw,
        median_kernel,
        smooth_win,
        baseline_kernel,
    )
    
    # Detect peaks
    peaks, peak_config = _detect_peaks(
        audio_dn,
        sample_rate,
        peak_distance_sec,
        height_percentile,
        min_height,
        prom_scale,
    )
    
    # Create AudioPeak objects
    audio_peaks = []
    for i, peak_frame in enumerate(peaks, start=1):
        audio_peaks.append(
            AudioPeak(
                peak_idx=i,
                frame=int(peak_frame),
                time_sec=float(peak_frame / max(sample_rate, 1e-6)),
                value=float(audio_dn[int(peak_frame)]),
            )
        )
    
    # Create result config
    result_config = {
        "sample_rate": float(sample_rate),
        "num_samples": len(audio_raw),
        "duration_sec": float(len(audio_raw) / max(sample_rate, 1e-6)),
        "denoise_config": {
            "median_kernel": int(median_kernel),
            "smooth_win": int(smooth_win),
            "baseline_kernel": int(baseline_kernel),
        },
        "peak_config": peak_config,
        "signal_stats": {
            "raw_min": float(np.min(audio_raw)),
            "raw_max": float(np.max(audio_raw)),
            "raw_mean": float(np.mean(audio_raw)),
            "raw_std": float(np.std(audio_raw)),
            "denoised_min": float(np.min(audio_dn)),
            "denoised_max": float(np.max(audio_dn)),
            "denoised_mean": float(np.mean(audio_dn)),
            "denoised_std": float(np.std(audio_dn)),
        },
    }
    
    # Store signal data for plotting
    signal_data = {
        "raw": audio_raw,
        "smooth": audio_smooth,
        "denoised": audio_dn,
        "peaks": peaks,
    }
    
    return audio_peaks, result_config, signal_data


def peaks_to_dict(peaks: list[AudioPeak]) -> list[dict]:
    """Convert AudioPeak objects to dictionaries"""
    return [
        {
            "peak_idx": p.peak_idx,
            "frame": p.frame,
            "time_sec": p.time_sec,
            "value": p.value,
        }
        for p in peaks
    ]


def save_peaks_csv(output_path: Path, peaks: list[AudioPeak]) -> None:
    """Save peaks to CSV file"""
    import csv
    
    with output_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["peak_idx", "frame", "time_sec", "value"])
        for p in peaks:
            writer.writerow([p.peak_idx, p.frame, p.time_sec, p.value])


def save_peaks_json(output_path: Path, peaks: list[AudioPeak], config: dict) -> None:
    """Save peaks and configuration to JSON file"""
    data = {
        "config": config,
        "peaks": peaks_to_dict(peaks),
    }
    with output_path.open("w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def load_pcm_from_file(
    audio_file: str,
    sample_rate: float = 16000.0,
) -> np.ndarray:
    """
    Load PCM audio from file (supports WAV, MP3, etc.).
    
    Args:
        audio_file: Path to audio file
        sample_rate: Target sample rate in Hz
    
    Returns:
        PCM audio samples as numpy array
    """
    try:
        import librosa
        audio, _ = librosa.load(audio_file, sr=int(sample_rate), mono=True)
        return audio
    except ImportError:
        print("librosa not installed. Trying scipy...")
        try:
            from scipy.io import wavfile
            sr, audio = wavfile.read(audio_file)
            if sr != int(sample_rate):
                import librosa
                audio = librosa.resample(audio.astype(float) / 32768.0, orig_sr=sr, target_sr=int(sample_rate))
            elif audio.dtype == np.int16:
                audio = audio.astype(float) / 32768.0
            return audio
        except Exception as e:
            print(f"Error loading audio: {e}")
            raise


def process_audio_file(
    audio_file: str,
    output_dir: Path | None = None,
    sample_rate: float = 16000.0,
) -> Tuple[list[AudioPeak], dict]:
    """
    Process audio file and detect peaks.
    
    Args:
        audio_file: Path to audio file
        output_dir: Optional output directory for saving results
        sample_rate: Sample rate in Hz
    
    Returns:
        Tuple of (peaks, config)
    """
    # Load audio
    print(f"Loading audio from {audio_file}...")
    audio_signal = load_pcm_from_file(audio_file, sample_rate=sample_rate)
    
    # Detect peaks
    print("Detecting peaks...")
    peaks, config, signal_data = detect_audio_peaks(audio_signal, sample_rate=sample_rate)
    
    # Save results if output_dir specified
    if output_dir is not None:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Save peaks frames as text file
        frames_path = output_dir / "audio_peaks_frames.txt"
        peak_frames = np.array([p.frame for p in peaks], dtype=int)
        np.savetxt(frames_path, peak_frames, fmt="%d")
        print(f"Saved peak frames to {frames_path}")
        
        # Save peaks as CSV
        csv_path = output_dir / "audio_peaks.csv"
        save_peaks_csv(csv_path, peaks)
        print(f"Saved peaks to {csv_path}")
        
        # Save config as JSON
        json_path = output_dir / "audio_peaks.json"
        save_peaks_json(json_path, peaks, config)
        print(f"Saved config to {json_path}")
        
        # Plot signal
        plot_path = output_dir / "audio_signal_overview.png"
        _plot_signal(
            plot_path,
            sample_rate,
            signal_data["raw"],
            signal_data["smooth"],
            signal_data["denoised"],
            signal_data["peaks"],
            "Audio Signal Overview",
            "amplitude",
        )
        print(f"Saved signal plot to {plot_path}")
    
    return peaks, config


# Example usage
if __name__ == "__main__":
    # Example 1: Detect peaks from a PCM numpy array
    print("=== Example 1: PCM Array ===")
    # Generate a synthetic audio signal with peaks
    sample_rate = 16000.0
    duration = 5.0  # 5 seconds
    t = np.linspace(0, duration, int(sample_rate * duration))
    
    # Create synthetic signal with peaks
    audio = np.sin(2 * np.pi * 440 * t) * 0.3  # 440 Hz sine wave
    # Add some peaks (amplitude spikes)
    audio[int(1.0 * sample_rate)] += 0.8
    audio[int(2.0 * sample_rate)] += 0.7
    audio[int(3.5 * sample_rate)] += 0.75
    
    # Detect peaks
    peaks, config, signal_data = detect_audio_peaks(audio, sample_rate=sample_rate)
    
    print(f"Found {len(peaks)} peaks:")
    for peak in peaks:
        print(f"  Peak {peak.peak_idx}: frame={peak.frame}, time={peak.time_sec:.2f}s, value={peak.value:.4f}")
    
    print(f"Config: {json.dumps(config, indent=2)}")
    
    # Example 2: Process audio file (uncomment to use)
    # audio_file = "path/to/audio.wav"
    # output_dir = Path("output")
    # peaks, config = process_audio_file(audio_file, output_dir=output_dir)
    # print(f"\nDetected {len(peaks)} peaks from {audio_file}")
