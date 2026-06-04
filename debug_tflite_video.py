"""
debug_tflite_video.py
─────────────────────────────────────────────────────────────────────────────
Python debug tool for golfballyolov8n_int8.tflite

Model spec (matches Android BallYoloDetector.kt / iOS BallYoloDetector.swift):
  Input : [1, 640, 640, 3]  INT8   zero_point=-128, scale=1/255
          Grayscale pixel replicated to RGB channels.
          INT8 value = uint8_pixel - 128

  Output: [1, 5, 8400]  FLOAT32 or INT8
          dim-1 channels: cx, cy, w, h (in 640×640 space), conf (0–1)

Usage:
  python debug_tflite_video.py <video_path> [options]

  -m / --model     path to .tflite model (default: assets/models/golfballyolov8n_int8.tflite)
  -o / --output    output annotated video file (optional; skip to preview only)
  -c / --conf      confidence threshold (default: 0.30)
  --iou            NMS IoU threshold    (default: 0.45)
  --max-frames     stop after N frames  (default: all)
  --no-preview     disable cv2 window   (useful on headless servers)
  --log-every      print detection log every N frames (default: 30)
"""

import argparse
import sys
import time
from pathlib import Path

import cv2
import numpy as np

# ─── TFLite runtime ──────────────────────────────────────────────────────────
try:
    from tflite_runtime.interpreter import Interpreter
    _BACKEND = "tflite_runtime"
except ImportError:
    try:
        import tensorflow as tf
        Interpreter = tf.lite.Interpreter
        _BACKEND = f"tensorflow {tf.__version__}"
    except ImportError:
        print("ERROR: install tflite-runtime or tensorflow first")
        sys.exit(1)

# ─── Constants ───────────────────────────────────────────────────────────────
INPUT_SIZE    = 640        # model input WxH
CONF_DEFAULT  = 0.30
IOU_DEFAULT   = 0.45
MODEL_DEFAULT = "assets/models/golfballyolov8n_int8.tflite"


# ─── NMS helper ──────────────────────────────────────────────────────────────

def _iou(b1: np.ndarray, b2: np.ndarray) -> float:
    """IoU between two boxes [x1,y1,x2,y2]."""
    ix1 = max(b1[0], b2[0]); iy1 = max(b1[1], b2[1])
    ix2 = min(b1[2], b2[2]); iy2 = min(b1[3], b2[3])
    inter = max(0.0, ix2 - ix1) * max(0.0, iy2 - iy1)
    a1 = (b1[2]-b1[0]) * (b1[3]-b1[1])
    a2 = (b2[2]-b2[0]) * (b2[3]-b2[1])
    union = a1 + a2 - inter
    return inter / union if union > 0 else 0.0


def nms(boxes: list[tuple], iou_thresh: float) -> list[tuple]:
    """
    Simple greedy NMS.
    boxes: list of (conf, cx, cy, w, h) all in model-space (640×640).
    Returns filtered list.
    """
    if not boxes:
        return []
    boxes_sorted = sorted(boxes, key=lambda b: b[0], reverse=True)
    kept = []
    while boxes_sorted:
        best = boxes_sorted.pop(0)
        kept.append(best)
        _, bx, by, bw, bh = best
        bx1, by1 = bx - bw/2, by - bh/2
        bx2, by2 = bx + bw/2, by + bh/2
        boxes_sorted = [
            b for b in boxes_sorted
            if _iou(
                np.array([bx1, by1, bx2, by2]),
                np.array([b[1]-b[3]/2, b[2]-b[4]/2, b[1]+b[3]/2, b[2]+b[4]/2])
            ) < iou_thresh
        ]
    return kept


# ─── Preprocessing ───────────────────────────────────────────────────────────

def preprocess_frame(frame_bgr: np.ndarray) -> np.ndarray:
    """
    BGR → grayscale → resize 640×640 → INT8 [1,640,640,3].
    Matches Android BallYoloDetector.kt: grayscale replicated to 3 channels,
    quantised as  int8 = uint8 - 128  (zero_point=-128, scale=1/255).
    """
    gray  = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2GRAY)
    gray  = cv2.resize(gray, (INPUT_SIZE, INPUT_SIZE), interpolation=cv2.INTER_LINEAR)
    gray3 = np.stack([gray, gray, gray], axis=-1)          # [640,640,3] uint8
    int8  = gray3.astype(np.int32) - 128                   # [640,640,3] int32
    int8  = np.clip(int8, -128, 127).astype(np.int8)       # → int8
    return int8[np.newaxis, ...]                            # [1,640,640,3]


# ─── Post-processing ─────────────────────────────────────────────────────────

def parse_output(
    out_tensor: np.ndarray,
    out_detail: dict,
    conf_thresh: float,
    iou_thresh: float,
    frame_w: int,
    frame_h: int,
) -> list[dict]:
    """
    Parse model output [1, 5, 8400] → list of detections in original frame space.

    Handles both FLOAT32 and INT8 output (dequantise when needed).
    Returns list of dicts: {cx, cy, w, h, conf} in pixel coords of original frame.
    """
    dtype = out_detail["dtype"]
    quant = out_detail["quantization"]  # (scale, zero_point)

    raw = out_tensor[0]   # [5, 8400]

    # Dequantise if INT8 output
    if dtype == np.int8:
        scale, zero_point = quant
        raw = (raw.astype(np.float32) - zero_point) * scale

    cx_all   = raw[0]   # [8400]
    cy_all   = raw[1]
    w_all    = raw[2]
    h_all    = raw[3]
    conf_all = raw[4]

    # Filter by confidence
    mask = conf_all >= conf_thresh
    if not mask.any():
        return []

    candidates = list(zip(
        conf_all[mask].tolist(),
        cx_all[mask].tolist(),
        cy_all[mask].tolist(),
        w_all[mask].tolist(),
        h_all[mask].tolist(),
    ))

    # NMS in model space
    kept = nms(candidates, iou_thresh)

    # Scale to original frame size
    sx = frame_w / INPUT_SIZE
    sy = frame_h / INPUT_SIZE

    results = []
    for conf, cx, cy, w, h in kept:
        results.append({
            "cx":   cx * sx,
            "cy":   cy * sy,
            "w":    w  * sx,
            "h":    h  * sy,
            "conf": conf,
        })
    return results


# ─── Visualisation ───────────────────────────────────────────────────────────

def draw_detections(frame: np.ndarray, dets: list[dict]) -> np.ndarray:
    vis = frame.copy()
    for d in dets:
        cx, cy, w, h, conf = d["cx"], d["cy"], d["w"], d["h"], d["conf"]
        x1 = int(cx - w / 2); y1 = int(cy - h / 2)
        x2 = int(cx + w / 2); y2 = int(cy + h / 2)
        cv2.rectangle(vis, (x1, y1), (x2, y2), (0, 255, 0), 2)
        cv2.circle(vis, (int(cx), int(cy)), 4, (0, 0, 255), -1)
        label = f"{conf:.2f}"
        (tw, th), _ = cv2.getTextSize(label, cv2.FONT_HERSHEY_SIMPLEX, 0.55, 1)
        cv2.rectangle(vis, (x1, y1 - th - 6), (x1 + tw + 4, y1), (0, 200, 0), -1)
        cv2.putText(vis, label, (x1 + 2, y1 - 4),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 1, cv2.LINE_AA)
    return vis


# ─── Main ─────────────────────────────────────────────────────────────────────

def main():
    ap = argparse.ArgumentParser(description="TFLite YOLOv8 golf-ball debug on video")
    ap.add_argument("video",         help="Input video path")
    ap.add_argument("-m", "--model", default=MODEL_DEFAULT, help="Path to .tflite model")
    ap.add_argument("-o", "--output",default=None,          help="Annotated output video path")
    ap.add_argument("-c", "--conf",  type=float, default=CONF_DEFAULT, help="Conf threshold")
    ap.add_argument("--iou",         type=float, default=IOU_DEFAULT,  help="NMS IoU threshold")
    ap.add_argument("--max-frames",  type=int,   default=0,  help="Max frames (0=all)")
    ap.add_argument("--no-preview",  action="store_true",    help="Disable cv2 window")
    ap.add_argument("--log-every",   type=int,   default=30, help="Print log every N frames")
    args = ap.parse_args()

    video_path = Path(args.video)
    model_path = Path(args.model)

    if not video_path.exists():
        print(f"ERROR: video not found: {video_path}")
        sys.exit(1)
    if not model_path.exists():
        print(f"ERROR: model not found: {model_path}")
        sys.exit(1)

    # ── Load model ──
    print(f"Backend  : {_BACKEND}")
    print(f"Model    : {model_path}")
    interp = Interpreter(model_path=str(model_path))
    interp.allocate_tensors()

    in_detail  = interp.get_input_details()[0]
    out_detail = interp.get_output_details()[0]

    print(f"\n── Input tensor ──")
    print(f"  shape : {in_detail['shape'].tolist()}")
    print(f"  dtype : {in_detail['dtype']}")
    print(f"  quant : scale={in_detail['quantization'][0]:.6f}  "
          f"zero_point={in_detail['quantization'][1]}")

    print(f"\n── Output tensor ──")
    print(f"  shape : {out_detail['shape'].tolist()}")
    print(f"  dtype : {out_detail['dtype']}")
    print(f"  quant : scale={out_detail['quantization'][0]:.6f}  "
          f"zero_point={out_detail['quantization'][1]}")

    print(f"\n── Video : {video_path} ──")
    cap = cv2.VideoCapture(str(video_path))
    if not cap.isOpened():
        print("ERROR: cannot open video")
        sys.exit(1)

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    fps          = cap.get(cv2.CAP_PROP_FPS) or 30.0
    vid_w        = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    vid_h        = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"  size  : {vid_w}×{vid_h}  fps={fps:.2f}  frames={total_frames}")
    print(f"  conf  : {args.conf}   iou: {args.iou}")
    print()

    # ── Output writer ──
    writer = None
    if args.output:
        out_path = Path(args.output)
        fourcc = cv2.VideoWriter_fourcc(*"mp4v")
        writer = cv2.VideoWriter(str(out_path), fourcc, fps, (vid_w, vid_h))
        if not writer.isOpened():
            print(f"WARNING: cannot open output writer at {out_path}")
            writer = None
        else:
            print(f"Output   : {out_path}")

    # ── Per-frame stats ──
    frame_idx     = 0
    total_dets    = 0
    frames_with   = 0
    t_infer_total = 0.0

    while True:
        ret, frame = cap.read()
        if not ret:
            break
        frame_idx += 1
        if args.max_frames > 0 and frame_idx > args.max_frames:
            break

        # Preprocess
        inp = preprocess_frame(frame)

        # Inference
        interp.set_tensor(in_detail["index"], inp)
        t0 = time.perf_counter()
        interp.invoke()
        t_infer_total += time.perf_counter() - t0

        raw_out = interp.get_tensor(out_detail["index"])

        # Parse detections
        dets = parse_output(raw_out, out_detail, args.conf, args.iou, vid_w, vid_h)

        total_dets += len(dets)
        if dets:
            frames_with += 1

        # Log
        if frame_idx % args.log_every == 0:
            avg_ms = t_infer_total / frame_idx * 1000
            print(f"  frame {frame_idx:5d}/{total_frames}  "
                  f"dets this frame={len(dets):2d}  "
                  f"avg_infer={avg_ms:.1f}ms")
            for i, d in enumerate(dets):
                print(f"    [{i}] cx={d['cx']:.1f} cy={d['cy']:.1f}  "
                      f"w={d['w']:.1f} h={d['h']:.1f}  conf={d['conf']:.3f}")

        # Draw + write/show
        vis = draw_detections(frame, dets)

        # Overlay: frame info
        info = (f"F{frame_idx}  dets={len(dets)}  "
                f"conf>={args.conf}  {vid_w}x{vid_h}")
        cv2.putText(vis, info, (8, 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (255, 255, 0), 1, cv2.LINE_AA)

        if writer:
            writer.write(vis)

        if not args.no_preview:
            cv2.imshow("TFLite Golf Ball Debug (Q to quit)", vis)
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                print("  [interrupted by user]")
                break

    # ── Summary ──
    cap.release()
    if writer:
        writer.release()
    if not args.no_preview:
        cv2.destroyAllWindows()

    avg_ms = t_infer_total / max(frame_idx, 1) * 1000
    print()
    print("═" * 50)
    print(f"  Frames processed : {frame_idx}")
    print(f"  Frames with ball : {frames_with}  "
          f"({100*frames_with/max(frame_idx,1):.1f}%)")
    print(f"  Total detections : {total_dets}")
    print(f"  Avg infer time   : {avg_ms:.2f} ms/frame")
    print("═" * 50)


if __name__ == "__main__":
    main()
