"""
MeshFlow Stabilize with Audio V2 - Functions Package

完整的高爾夫揮桿分析管線：
1. 步驟1：Split Hits from CSV and Video
2. 步驟2：MeshFlow Video Stabilization
3. 步驟3：Audio Analysis and Classification
4. 步驟4：Audio Score Classification
5. 步驟5：Video OpenPose Analysis
6. 步驟6：Ball Tracking Analysis
"""

import sys
from pathlib import Path

# 添加函數模組路徑
current_dir = Path(__file__).parent
sys.path.insert(0, str(current_dir))

try:
    from split_hits import run_split_hits
    from meshflow_stabilization import run_meshflow_stabilization
    from audio_analysis import run_audio_analysis
    from audio_scoring import run_audio_scoring
    from openpose_analysis import run_openpose_analysis
    from ball_tracking import run_ball_tracking
except ImportError as e:
    print(f"警告：無法導入部分模組：{e}")
    # 定義虛擬函數以防止完全崩潰
    def run_split_hits(): raise NotImplementedError("模組未正確導入")
    def run_meshflow_stabilization(*args, **kwargs): raise NotImplementedError("模組未正確導入")
    def run_audio_analysis(*args, **kwargs): raise NotImplementedError("模組未正確導入")
    def run_audio_scoring(*args, **kwargs): raise NotImplementedError("模組未正確導入")
    def run_openpose_analysis(*args, **kwargs): raise NotImplementedError("模組未正確導入")
    def run_ball_tracking(*args, **kwargs): raise NotImplementedError("模組未正確導入")

__all__ = [
    'run_split_hits',
    'run_meshflow_stabilization',
    'run_audio_analysis',
    'run_audio_scoring',
    'run_openpose_analysis',
    'run_ball_tracking',
]
