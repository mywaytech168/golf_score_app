"""
步驟2：FFmpeg Video Stabilization - 生產級函數庫
功能：使用FFmpeg Stabilize濾鏡穩定視頻，移除相機晃動，保留音訊

API 概述：
  - FFmpegStabilizeConfig: 配置類
  - stabilize_video_ffmpeg(): 使用 FFmpeg 穩定化視頻
  - run_ffmpeg_stabilization(): 命令行/程序入口

使用示例：
  from functions.ffmpeg_stabilization import FFmpegStabilizeConfig, run_ffmpeg_stabilization
  config = FFmpegStabilizeConfig(input_path="input.mp4", output_path="output.mp4")
  result = run_ffmpeg_stabilization(config)
"""

import subprocess
import os
import tempfile
import shutil
from pathlib import Path
from typing import Dict, Tuple, Optional, Any
from dataclasses import dataclass
import platform


# =============================================================================
# 配置類
# =============================================================================

@dataclass
class FFmpegStabilizeConfig:
    """FFmpeg Stabilize 視頻穩定化配置類
    
    使用 FFmpeg 的 vidstab 過濾器進行視頻穩定化。
    包含 25+ 參數，提供精細的調整控制。
    """
    # ========== 輸入輸出 ==========
    input_path: str = ""
    output_path: str = ""
    
    # ========== vidstabdetect 檢測參數 ==========
    shakiness: int = 8          # 檢測靈敏度 (1-10)，越高越敏感，推薦=8
    accuracy: int = 15          # 精度 (1-15)，越高越準確但越慢，推薦=15
    stepsize: int = 4           # 分析步長 (4-32)，越小越精確，推薦=4(精細)
    mincontrast: float = 0.20   # 最小對比度 (0.0-1.0)，影響特徵檢測，推薦=0.2(更敏感)
    tripod: int = 0             # 三腳架模式 (0/1)，假設攝像機完全靜止，default=0
    show: int = 0               # 顯示偵測過程 (0/1)，用於調試，default=0
    
    # ========== vidstabtransform 應用參數 ==========
    smoothing: int = 20         # 平滑量 (0-100)，越高越平滑，推薦=20(對應MeshFlow radius=10)
    zoom: int = 0               # 縮放補償 (-100 to 100)，推薦=0
    optzoom: int = 1            # 自動縮放 (0/1)，自動補償邊界，推薦=1
    zoomspeed: float = 0.5      # 縮放速度 (0.1-5.0)，推薦=0.5(適中)
    interpol: int = 2           # 插值方法 (0=linear, 1=bilinear, 2=bicubic)，推薦=2(高質量)
    crop: int = 1               # 裁剪黑邊 (0/1)，推薦=1
    invert: int = 0             # 反轉變換 (0/1)，用於特殊情況，default=0
    
    # ========== 視頻編碼 - 速度與質量 ==========
    preset: str = "fast"        # 編碼速度: ultrafast, superfast, veryfast, faster, fast, medium, slow, slower, veryslow，推薦=fast
    crf: int = 16               # 視頻質量 (0-51)，越低越好但文件越大，推薦=16(高質量)
    
    # ========== 視頻編碼 - 高級選項 ==========
    bitrate: Optional[str] = None       # 位速率 (e.g., "5000k")，None=自動（crf優先）
    bufsize: str = "5000k"              # 緩衝大小，default=5000k
    maxrate: Optional[str] = None       # 最大位速率，None=無限制
    
    # ========== 音頻編碼 ==========
    audio_codec: str = "aac"           # 音頻編碼器，default=aac
    audio_bitrate: str = "128k"        # 音頻位速率，default=128k
    audio_samplerate: int = 48000      # 音頻採樣率 (Hz)，default=48000
    
    # ========== 處理選項 ==========
    threads: int = 0                   # 線程數，0=自動，default=0
    keep_temp_files: bool = False      # 保留臨時檔案用於調試
    
    def __post_init__(self):
        """驗證配置參數"""
        if not self.input_path:
            raise ValueError("input_path 不能為空")
        if not self.output_path:
            raise ValueError("output_path 不能為空")
        if not Path(self.input_path).exists():
            raise ValueError(f"輸入檔案不存在：{self.input_path}")


# =============================================================================
# 輔助函數
# =============================================================================

def _check_ffmpeg_installed() -> bool:
    """檢查 FFmpeg 是否已安裝"""
    try:
        subprocess.run(
            ["ffmpeg", "-version"],
            capture_output=True,
            check=True,
            timeout=5
        )
        return True
    except (FileNotFoundError, subprocess.TimeoutExpired, subprocess.CalledProcessError):
        return False


def _normalize_path(path: str) -> str:
    """
    標準化路徑（Windows UNC → Linux 相容）
    
    Example:
      \\10.1.1.101\ORVIA\videos\... → /data/orvia/videos/...
    """
    current_os = platform.system()
    
    if current_os == "Linux":
        # 只在 Linux 上進行轉換
        if "\\\\10.1.1.101\\ORVIA" in path or "\\10.1.1.101\\ORVIA" in path:
            converted = path.replace("\\\\10.1.1.101\\ORVIA", "/data/orvia")
            converted = converted.replace("\\10.1.1.101\\ORVIA", "/data/orvia")
            converted = converted.replace("\\", "/")
            return converted
    
    return path


# =============================================================================
# 核心函數 - FFmpeg 穩定化
# =============================================================================

def stabilize_video_ffmpeg(config: FFmpegStabilizeConfig) -> Dict[str, Any]:
    """使用 FFmpeg 穩定化視頻的完整流程
    
    流程：
    1. 檢查 FFmpeg 是否安裝
    2. 創建臨時目錄
    3. 執行 vidstabdetect 分析抖動
    4. 執行 vidstabtransform 應用穩定化
    5. 添加音頻
    6. 清理臨時檔案
    7. 返回結果
    
    Args:
        config: FFmpegStabilizeConfig 配置
        
    Returns:
        {'success': bool, 'output': str, 'message': str}
    """
    print("\n" + "="*80)
    print("🎬 步驟 2/6：FFmpeg Video Stabilization with Audio")
    print("="*80)
    
    # 0. 檢查 FFmpeg
    if not _check_ffmpeg_installed():
        raise RuntimeError("❌ FFmpeg 未安裝或不在 PATH 中")
    
    print("✅ FFmpeg 已檢測")
    
    # 標準化路徑
    input_path = _normalize_path(config.input_path)
    output_path = _normalize_path(config.output_path)
    
    print(f"輸入：{input_path}")
    print(f"輸出：{output_path}")
    
    # 確保輸出目錄存在
    output_dir = Path(output_path).parent
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # 1. 創建臨時目錄
    with tempfile.TemporaryDirectory() as tmpdir:
        tmpdir_path = Path(tmpdir)
        
        # 複製輸入視頻到臨時目錄（解決網絡路徑權限問題）
        temp_input = tmpdir_path / "input.mp4"
        temp_transforms = tmpdir_path / "input.stab"
        temp_stabilized = tmpdir_path / "stabilized.mp4"
        
        print(f"\n📁 臨時目錄：{tmpdir}")
        print(f"💾 複製輸入視頻到臨時目錄...")
        shutil.copy(input_path, str(temp_input))
        print(f"✅ 複製完成")
        
        try:
            # 2. 執行 vidstabdetect（分析抖動）
            print("\n🔍 步驟 1/3：分析視頻抖動...")
            
            # 在臨時目錄中運行，使用相對路徑避免路徑問題
            vidstabdetect_filter = (
                f"vidstabdetect="
                f"shakiness={config.shakiness}:"
                f"accuracy={config.accuracy}:"
                f"stepsize={config.stepsize}:"
                f"mincontrast={config.mincontrast}:"
                f"tripod={config.tripod}:"
                f"show={config.show}:"
                f"result=input.stab"
            )
            
            detect_cmd = [
                "ffmpeg",
                "-i", "input.mp4",
                "-vf", vidstabdetect_filter,
                "-f", "null",
                "-"
            ]
            
            print(f"   執行：{' '.join(detect_cmd[:5])}...")
            
            result = subprocess.run(detect_cmd, capture_output=True, text=True, cwd=str(tmpdir_path))
            
            # 打印 FFmpeg 的 stderr（包含進度信息）
            if result.stderr:
                stderr_lines = result.stderr.split('\n')
                # 顯示最後 5 行（跳過元數據信息）
                print(f"   FFmpeg 進度：")
                for line in stderr_lines[-5:]:
                    if line.strip() and 'frame=' in line:
                        print(f"     {line.strip()}")
            
            if result.returncode != 0:
                print(f"❌ 分析失敗（返回碼：{result.returncode}）")
                print(f"   stderr：{result.stderr[-500:]}")  # 顯示最後 500 字符
                raise RuntimeError(f"vidstabdetect 失敗")
            
            # 檢查轉換文件是否生成
            if not temp_transforms.exists():
                print(f"❌ 轉換檔案未生成")
                print(f"   預期路徑：{temp_transforms}")
                stab_files = list(tmpdir_path.glob("*"))
                print(f"   臨時目錄中的文件：{[f.name for f in stab_files]}")
                raise RuntimeError(f"vidstabdetect 未生成轉換檔案")
            
            print(f"✅ 已生成轉換檔案：{temp_transforms.name}")
            
            # 3. 執行 vidstabtransform（應用穩定化）
            print("\n⚙️  步驟 2/3：應用穩定化...")
            
            vidstabtransform_filter = (
                f"vidstabtransform="
                f"input=input.stab:"
                f"smoothing={config.smoothing}:"
                f"zoom={config.zoom}:"
                f"optzoom={config.optzoom}:"
                f"zoomspeed={config.zoomspeed}:"
                f"interpol={config.interpol}:"
                f"crop={config.crop}:"
                f"invert={config.invert}"
            )
            
            transform_cmd = [
                "ffmpeg",
                "-i", "input.mp4",
                "-vf", vidstabtransform_filter,
                "-c:v", "libx264",
                "-preset", config.preset,
                "-crf", str(config.crf),
            ]
            
            # 添加可選的位速率參數
            if config.bitrate:
                transform_cmd.extend(["-b:v", config.bitrate])
            
            # 添加線程參數
            if config.threads > 0:
                transform_cmd.extend(["-threads", str(config.threads)])
            
            transform_cmd.extend([
                "-bufsize", config.bufsize,
                "-an",  # 不複製音頻
                "-y",
                "stabilized.mp4"
            ])
            
            print(f"   執行：{' '.join(transform_cmd[:5])}...")
            result = subprocess.run(transform_cmd, capture_output=True, text=True, cwd=str(tmpdir_path))
            
            if result.returncode != 0:
                print(f"❌ 穩定化失敗（返回碼：{result.returncode}）")
                print(f"   stderr：{result.stderr[-500:]}")
                raise RuntimeError(f"vidstabtransform 失敗")
            
            if not temp_stabilized.exists():
                raise RuntimeError(f"穩定化視頻未生成")
            
            print(f"✅ 穩定化完成")
            
            # 4. 添加音頻
            print("\n🎵 步驟 3/3：添加音頻...")
            merge_cmd = [
                "ffmpeg",
                "-i", str(temp_stabilized),
                "-i", input_path,
                "-map", "0:v:0",
                "-map", "1:a:0",
                "-c:v", "copy",
                "-c:a", config.audio_codec,
                "-b:a", config.audio_bitrate,
                "-ar", str(config.audio_samplerate),
                "-shortest",
                "-y",
                output_path
            ]
            
            print(f"   執行：{' '.join(merge_cmd[:5])}...")
            result = subprocess.run(merge_cmd, capture_output=True, text=True)
            
            if result.returncode != 0:
                print(f"⚠️  添加音頻失敗，使用無音頻版本")
                # 直接複製無音頻版本
                shutil.copy(str(temp_stabilized), output_path)
            
            if not Path(output_path).exists():
                raise RuntimeError(f"輸出檔案未生成")
            
            print(f"✅ 已寫出視頻：{output_path}")
            
            # 5. 清理臨時檔案
            if not config.keep_temp_files:
                print("\n🧹 清理臨時檔案...")
            else:
                print(f"\n📂 保留臨時檔案（用於調試）：{tmpdir}")
        
        except Exception as e:
            print(f"\n❌ 錯誤：{e}")
            raise
    
    return {
        "success": True,
        "output": output_path,
        "message": "FFmpeg 穩定化完成"
    }


# =============================================================================
# 公開 API
# =============================================================================

def run_ffmpeg_stabilization(config: Optional[FFmpegStabilizeConfig] = None) -> Dict[str, Any]:
    """FFmpeg 視頻穩定化的命令行和程序入口
    
    Args:
        config: FFmpegStabilizeConfig 配置，或 None 使用默認值
        
    Returns:
        {'success': bool, 'output': str, 'message': str}
        
    使用示例：
        # 默認配置
        result = run_ffmpeg_stabilization(
            FFmpegStabilizeConfig(
                input_path="input.mp4",
                output_path="output_stabilized.mp4"
            )
        )
        
        # 完全配置
        config = FFmpegStabilizeConfig(
            input_path="input.mp4",
            output_path="output.mp4",
            shakiness=5,
            accuracy=15,
            smoothing=10,
        )
        result = run_ffmpeg_stabilization(config)
    """
    if config is None:
        config = FFmpegStabilizeConfig()
    
    try:
        result = stabilize_video_ffmpeg(config)
        print("\n" + "="*80)
        print("✅ FFmpeg 穩定化完成")
        print(f"   輸出：{result['output']}")
        print("="*80)
        return result
    except Exception as e:
        print(f"\n❌ 錯誤：{e}")
        raise


# =============================================================================
# 主函數（測試用）
# =============================================================================

if __name__ == "__main__":
    # 測試用例 - 優化穩定化參數
    config = FFmpegStabilizeConfig(
        input_path=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip.mp4",
        output_path=r"\\10.1.1.101\ORVIA\videos\8f89d7b1-da5d-4eaf-84fd-6234c0fcbad9\4897e6a5-d3f4-4d7a-a76b-4c7153bfbc41\clip_stabilized2.mp4",
        # 偵測參數
        shakiness=6,        # 更敏感的檢測
        accuracy=15,        # 保持高精度
        stepsize=6,         # 更精細的分析
        mincontrast=0.3,   # 更敏感的對比度
        # 應用參數
        smoothing=15,       # 更平滑的結果
        optzoom=1,          # 自動縮放補償
        zoomspeed=0.15,      # 適中的縮放速度
        interpol=2,         # 高質量插值
        crop=1,             # 裁剪黑邊
        # 編碼參數
        preset="fast",      # 平衡速度與質量
        crf=16              # 高質量輸出
    )
    result = run_ffmpeg_stabilization(config)
