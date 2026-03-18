#!/usr/bin/env python3
"""
测试处理管道 - 验证每个步骤是否能被正确导入和调用
"""

import sys
from pathlib import Path
from datetime import datetime

# 添加当前目录到 Python 路径
sys.path.insert(0, str(Path(__file__).parent))

def test_imports():
    """测试所有模块能否导入"""
    print("🔍 测试模块导入...")
    
    try:
        from functions.meshflow_stabilization import run_meshflow_stabilization, MeshFlowConfig
        print("✅ MeshFlowConfig 导入成功")
    except Exception as e:
        print(f"❌ MeshFlowConfig 导入失败: {e}")
        return False
    
    try:
        from functions.audio_analysis import run_audio_analysis, AudioAnalysisConfig
        print("✅ AudioAnalysisConfig 导入成功")
    except Exception as e:
        print(f"❌ AudioAnalysisConfig 导入失败: {e}")
        return False
    
    try:
        from functions.audio_scoring import run_audio_scoring, AudioScoringConfig
        print("✅ AudioScoringConfig 导入成功")
    except Exception as e:
        print(f"❌ AudioScoringConfig 导入失败: {e}")
        return False
    
    try:
        from functions.openpose_analysis import run_openpose_analysis, MediaPoseConfig
        print("✅ MediaPoseConfig 导入成功")
    except Exception as e:
        print(f"❌ MediaPoseConfig 导入失败: {e}")
        return False
    
    try:
        from functions.ball_tracking import run_ball_tracking, BallTrackingConfig
        print("✅ BallTrackingConfig 导入成功")
    except Exception as e:
        print(f"❌ BallTrackingConfig 导入失败: {e}")
        return False
    
    return True


def test_config_instantiation():
    """测试配置对象能否实例化"""
    print("\n🔍 测试配置对象实例化...")
    
    from functions.meshflow_stabilization import MeshFlowConfig
    from functions.audio_analysis import AudioAnalysisConfig
    from functions.audio_scoring import AudioScoringConfig
    from functions.openpose_analysis import MediaPoseConfig
    from functions.ball_tracking import BallTrackingConfig
    
    try:
        config = MeshFlowConfig(input_path="test.mp4")
        print("✅ MeshFlowConfig 实例化成功")
    except Exception as e:
        print(f"❌ MeshFlowConfig 实例化失败: {e}")
        return False
    
    try:
        config = AudioAnalysisConfig(video_path="test.mp4", output_dir=".")
        print("✅ AudioAnalysisConfig 实例化成功")
    except Exception as e:
        print(f"❌ AudioAnalysisConfig 实例化失败: {e}")
        return False
    
    try:
        config = AudioScoringConfig(csv_folder=".", video_root=".")
        print("✅ AudioScoringConfig 实例化成功")
    except Exception as e:
        print(f"❌ AudioScoringConfig 实例化失败: {e}")
        return False
    
    try:
        config = MediaPoseConfig(video_path="test.mp4", output_dir=".")
        print("✅ MediaPoseConfig 实例化成功")
    except Exception as e:
        print(f"❌ MediaPoseConfig 实例化失败: {e}")
        return False
    
    try:
        config = BallTrackingConfig(batch_mode=True, input_dir=".")
        print("✅ BallTrackingConfig 实例化成功")
    except Exception as e:
        print(f"❌ BallTrackingConfig 实例化失败: {e}")
        return False
    
    return True


if __name__ == "__main__":
    print("=" * 80)
    print("高尔夫计分应用 - 处理管道测试")
    print("=" * 80)
    
    if not test_imports():
        print("\n❌ 模块导入失败")
        sys.exit(1)
    
    if not test_config_instantiation():
        print("\n❌ 配置对象实例化失败")
        sys.exit(1)
    
    print("\n✅ 所有测试通过！")
    print("=" * 80)
