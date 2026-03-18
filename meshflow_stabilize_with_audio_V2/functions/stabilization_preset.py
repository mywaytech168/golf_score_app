"""
穩定化預設管理器
提供統一的穩定化參數配置，支持在 FFmpeg 和 MeshFlow 之間自動轉換
"""

from dataclasses import dataclass
from typing import Dict, Any
from enum import Enum


class StabilizationLevel(Enum):
    """穩定化等級定義"""
    LIGHT = 1          # 輕度：保留更多自然感
    MEDIUM = 2         # 中等：平衡自然感和穩定性
    STRONG = 3         # 強：優先穩定性


@dataclass
class StabilizationPreset:
    """統一的穩定化預設
    
    自動管理 FFmpeg 和 MeshFlow 的參數轉換，確保效果一致性
    """
    name: str
    level: StabilizationLevel
    description: str = ""
    
    def __post_init__(self):
        """驗證預設"""
        if self.level not in StabilizationLevel:
            raise ValueError(f"無效的穩定化等級: {self.level}")
    
    def get_ffmpeg_config(self) -> Dict[str, Any]:
        """獲取 FFmpeg 配置"""
        presets = {
            StabilizationLevel.LIGHT: {
                'shakiness': 4,
                'accuracy': 12,
                'stepsize': 8,
                'mincontrast': 0.30,
                'smoothing': 10,
                'zoomspeed': 0.10,
                'interpol': 1,
                'crf': 18,
            },
            StabilizationLevel.MEDIUM: {
                'shakiness': 6,
                'accuracy': 15,
                'stepsize': 6,
                'mincontrast': 0.25,
                'smoothing': 20,
                'zoomspeed': 0.15,
                'interpol': 2,
                'crf': 16,
            },
            StabilizationLevel.STRONG: {
                'shakiness': 8,
                'accuracy': 15,
                'stepsize': 4,
                'mincontrast': 0.20,
                'smoothing': 40,
                'zoomspeed': 0.30,
                'interpol': 2,
                'crf': 14,
            }
        }
        return presets[self.level]
    
    def get_meshflow_config(self) -> Dict[str, Any]:
        """獲取 MeshFlow 配置"""
        presets = {
            StabilizationLevel.LIGHT: {
                'mesh_row_count': 12,
                'mesh_col_count': 12,
                'mesh_outlier_subframe_row_count': 3,
                'mesh_outlier_subframe_col_count': 3,
                'feature_ellipse_row_count': 8,
                'feature_ellipse_col_count': 8,
                'homography_min_number_corresponding_features': 4,
                'temporal_smoothing_radius': 8,
                'optimization_num_iterations': 60,
                'shake_thresh_k': 4.5,
                'shake_smooth_win': 5,
                'shake_pad_frames': 5,
            },
            StabilizationLevel.MEDIUM: {
                'mesh_row_count': 16,
                'mesh_col_count': 16,
                'mesh_outlier_subframe_row_count': 4,
                'mesh_outlier_subframe_col_count': 4,
                'feature_ellipse_row_count': 10,
                'feature_ellipse_col_count': 10,
                'homography_min_number_corresponding_features': 4,
                'temporal_smoothing_radius': 10,
                'optimization_num_iterations': 80,
                'shake_thresh_k': 4.0,
                'shake_smooth_win': 7,
                'shake_pad_frames': 8,
            },
            StabilizationLevel.STRONG: {
                'mesh_row_count': 20,
                'mesh_col_count': 20,
                'mesh_outlier_subframe_row_count': 5,
                'mesh_outlier_subframe_col_count': 5,
                'feature_ellipse_row_count': 12,
                'feature_ellipse_col_count': 12,
                'homography_min_number_corresponding_features': 4,
                'temporal_smoothing_radius': 15,
                'optimization_num_iterations': 120,
                'shake_thresh_k': 3.5,
                'shake_smooth_win': 9,
                'shake_pad_frames': 10,
            }
        }
        return presets[self.level]
    
    def apply_to_ffmpeg_config(self, config) -> None:
        """應用預設到 FFmpegStabilizeConfig 對象"""
        ffmpeg_params = self.get_ffmpeg_config()
        for key, value in ffmpeg_params.items():
            if hasattr(config, key):
                setattr(config, key, value)
    
    def apply_to_meshflow_config(self, config) -> None:
        """應用預設到 MeshFlowConfig 對象"""
        meshflow_params = self.get_meshflow_config()
        for key, value in meshflow_params.items():
            if hasattr(config, key):
                setattr(config, key, value)


# 預定義預設
PRESETS = {
    'golf_light': StabilizationPreset(
        name='golf_light',
        level=StabilizationLevel.LIGHT,
        description='高爾夫揮桿分析 - 輕度穩定化，保留原始運動細節'
    ),
    'golf_medium': StabilizationPreset(
        name='golf_medium',
        level=StabilizationLevel.MEDIUM,
        description='高爾夫揮桿分析 - 中等穩定化，平衡穩定性和自然感'
    ),
    'golf_strong': StabilizationPreset(
        name='golf_strong',
        level=StabilizationLevel.STRONG,
        description='高爾夫揮桿分析 - 強穩定化，優先視覺流暢度'
    ),
}


def get_preset(name: str) -> StabilizationPreset:
    """獲取預設配置"""
    if name not in PRESETS:
        raise ValueError(f"未知的預設: {name}。可用預設: {list(PRESETS.keys())}")
    return PRESETS[name]


def get_all_presets() -> Dict[str, StabilizationPreset]:
    """獲取所有預設"""
    return PRESETS.copy()


# 使用示例
if __name__ == "__main__":
    from ffmpeg_stabilization import FFmpegStabilizeConfig
    from meshflow_stabilization import MeshFlowConfig
    
    # 獲取預設
    preset = get_preset('golf_medium')
    
    print(f"預設名稱: {preset.name}")
    print(f"說明: {preset.description}")
    print(f"等級: {preset.level.name}")
    
    # 應用到 FFmpeg
    ffmpeg_config = FFmpegStabilizeConfig(
        input_path="input.mp4",
        output_path="output_ffmpeg.mp4"
    )
    preset.apply_to_ffmpeg_config(ffmpeg_config)
    print(f"\nFFmpeg 配置已應用")
    print(f"  smoothing: {ffmpeg_config.smoothing}")
    print(f"  shakiness: {ffmpeg_config.shakiness}")
    
    # 應用到 MeshFlow
    meshflow_config = MeshFlowConfig(
        input_path="input.mp4",
        output_path="output_meshflow.mp4"
    )
    preset.apply_to_meshflow_config(meshflow_config)
    print(f"\nMeshFlow 配置已應用")
    print(f"  temporal_smoothing_radius: {meshflow_config.temporal_smoothing_radius}")
    print(f"  shake_thresh_k: {meshflow_config.shake_thresh_k}")
