"""
ball_trajectory_server.py  —  球軌跡追蹤 Flask server

只做一件事：接收影片 URL，下載後回傳球軌跡 JSON。

啟動：
    python ball_trajectory_server.py [--host 0.0.0.0] [--port 6001]

POST /api/ball-trajectory
    Body: {
      "video_url":    "https://b2.../clip.mp4",  # 必填（B2 presigned URL）
      "hit_sec":      2.5,                       # 選填
      "flip_mode":    0,                         # 選填（0 = Android coded-space）
      "roi_cx_ratio": 0.5984,                    # 選填
      "roi_cy_ratio": 0.3759,                    # 選填
      "roi_radius":   200                        # 選填
    }
    Response: {
      "track_pts": [{"x":int,"y":int,"frame_idx":int,"pts_us":int}, ...],
      "fps": float, "width": int, "height": int, "rotation": int
    }

GET /health  →  {"status": "ok"}
"""

import argparse
import logging
import os
import sys
import tempfile
import urllib.request
from pathlib import Path

from flask import Flask, jsonify, request

# functions/ 目錄與此檔案同層
sys.path.insert(0, str(Path(__file__).parent))
from functions.ball_trajectory_worker import extract_trajectory

# ──────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)

app = Flask(__name__)


# ──────────────────────────────────────────────────────────────
# Endpoints
# ──────────────────────────────────────────────────────────────

@app.post("/api/ball-trajectory")
def ball_trajectory():
    data = request.get_json(force=True, silent=True)
    if not data or "video_url" not in data:
        return jsonify({"error": "缺少 video_url 欄位"}), 400

    video_url = data["video_url"]
    tmp_path  = None

    try:
        # 從 B2 presigned URL 下載到本地暫存（C# server 與 Flask server 在不同機器）
        fd, tmp_path = tempfile.mkstemp(suffix=".mp4", prefix="btraj_")
        os.close(fd)
        logger.info("下載影片: %s → %s", video_url[:60] + "...", tmp_path)
        urllib.request.urlretrieve(video_url, tmp_path)
        logger.info("下載完成: %.1f MB", os.path.getsize(tmp_path) / 1_048_576)

        result = extract_trajectory(
            video_path   = tmp_path,
            hit_sec      = data.get("hit_sec"),
            flip_mode    = int(data.get("flip_mode",    0)),
            roi_cx_ratio = float(data.get("roi_cx_ratio", 1149 / 1920)),
            roi_cy_ratio = float(data.get("roi_cy_ratio",  406 / 1080)),
            roi_radius   = int(data.get("roi_radius",   200)),
        )
        logger.info("done: %d track_pts", len(result["track_pts"]))
        return jsonify(result), 200

    except Exception as e:
        logger.exception("ball_trajectory 失敗")
        return jsonify({"error": str(e)}), 500

    finally:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)


@app.get("/health")
def health():
    return jsonify({"status": "ok"}), 200


# ──────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=6001)
    args = parser.parse_args()

    logger.info("球軌跡 server 啟動 → http://%s:%d", args.host, args.port)
    app.run(host=args.host, port=args.port, debug=False, threaded=True)
