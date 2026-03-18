"""
MeshFlow Stabilize with Audio V2 - Ball Tracking Main Entry Point

高爾夫球軌跡追蹤系統
連續處理視頻，輸出軌跡疊圖
"""

import sys
import argparse
from pathlib import Path
from datetime import datetime

# 添加 functions 模組路徑
sys.path.insert(0, str(Path(__file__).parent))

from functions.ball_tracking import BallTrackingConfig, run_ball_tracking


def print_header():
    """打印程式標題"""
    print("\n" + "="*90)
    print("🏌️  Golf Ball Tracking System - MeshFlow V2")
    print("="*90)
    print("球軌跡追蹤 | 高爾夫揮桿分析")
    print("="*90 + "\n")


def main():
    """主函式，處理命令行參數"""
    parser = argparse.ArgumentParser(
        description="高爾夫球軌跡追蹤系統 - 連續視頻處理",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
範例：
  python main.py --mode single --video path/to/video.mp4
    └─ 處理單支視頻
  
  python main.py --mode batch --input dir/ --output out_dir/
    └─ 批量處理資料夾中所有 MP4
  
  python main.py --mode batch --input dir/ --roi 742 255 --frames 300
    └─ 批量處理，指定 ROI 中心和追蹤幀數
        """
    )
    
    # 模式選擇
    parser.add_argument(
        "--mode",
        type=str,
        default="single",
        choices=["single", "batch"],
        help="處理模式：single(單支) 或 batch(批量)，預設 single"
    )
    
    # 單支視頻模式
    parser.add_argument(
        "--video",
        type=str,
        help="單支視頻路徑"
    )
    
    # 批量模式
    parser.add_argument(
        "--input",
        type=str,
        help="輸入資料夾（批量模式）"
    )
    
    parser.add_argument(
        "--output",
        type=str,
        help="輸出資料夾，預設為輸入資料夾內的 traj_out"
    )
    
    # ROI 設定
    parser.add_argument(
        "--roi",
        type=int,
        nargs=2,
        metavar=("X", "Y"),
        default=[742, 255],
        help="固定 ROI 中心座標 (x y)，預設 742 255"
    )
    
    # 追蹤參數
    parser.add_argument(
        "--frames",
        type=int,
        default=300,
        help="最大追蹤幀數，預設 300"
    )
    
    parser.add_argument(
        "--roi-size",
        type=int,
        default=200,
        help="初始 ROI 尺寸，預設 200"
    )
    
    parser.add_argument(
        "--roi-min",
        type=int,
        default=80,
        help="最小 ROI 尺寸，預設 80"
    )
    
    parser.add_argument(
        "--shrink-frames",
        type=int,
        default=60,
        help="ROI 縮小幀數，預設 60"
    )
    
    # 圖像處理
    parser.add_argument(
        "--flip-mode",
        type=int,
        default=5,
        help="圖像翻轉模式 (0-6)，預設 5 (旋轉90°逆時針)"
    )
    
    parser.add_argument(
        "--out-rotate",
        type=int,
        default=4,
        help="輸出旋轉模式 (0/4/5/6)，預設 4 (旋轉90°順時針)"
    )
    
    # UI 選項
    parser.add_argument(
        "--show",
        action="store_true",
        help="顯示即時追蹤預覽"
    )
    
    parser.add_argument(
        "--no-video",
        action="store_true",
        help="不輸出視頻，僅做追蹤"
    )
    
    parser.add_argument(
        "--auto-ui",
        action="store_true",
        default=True,
        help="批量模式時自動關閉 UI"
    )
    
    args = parser.parse_args()
    
    print_header()
    
    # 驗證模式
    if args.mode == "single" and not args.video:
        print("❌ 單支模式必須指定 --video")
        parser.print_help()
        return
    
    if args.mode == "batch" and not args.input:
        print("❌ 批量模式必須指定 --input")
        parser.print_help()
        return
    
    # 建立配置
    print("⚙️  配置中...")
    
    roi_x, roi_y = args.roi
    
    config = BallTrackingConfig(
        # 模式
        batch_mode=(args.mode == "batch"),
        video_path=args.video or "",
        input_dir=args.input or "",
        output_dir=args.output,
        
        # ROI 設定
        fixed_roi_mode=True,
        fixed_roi_center=(roi_x, roi_y),
        roi_cfg={
            "size_init": args.roi_size,
            "size_min": args.roi_min,
            "shrink_over_frames": args.shrink_frames,
            "center_alpha": 0.4,
            "max_center_step": 80,
        },
        
        # 追蹤參數
        track_frames=args.frames,
        
        # 圖像處理
        flip_mode=args.flip_mode,
        out_rotate_mode=args.out_rotate,
        
        # UI
        show_main=args.show,
        show_debug_roi=args.show,
        export_video=(not args.no_video),
        auto_disable_ui_in_batch=args.auto_ui,
    )
    
    # 打印配置摘要
    print("\n📋 執行配置：")
    print(f"  模式：{args.mode.upper()}")
    if args.mode == "single":
        print(f"  視頻：{args.video}")
    else:
        print(f"  輸入：{args.input}")
        print(f"  輸出：{args.output or '(同輸入資料夾)'}")
    
    print(f"  ROI 中心：({roi_x}, {roi_y})")
    print(f"  ROI 初始尺寸：{args.roi_size}")
    print(f"  最大追蹤幀數：{args.frames}")
    print(f"  圖像翻轉：{args.flip_mode} | 輸出旋轉：{args.out_rotate}")
    print(f"  UI：{'顯示' if args.show else '隱藏'} | 視頻：{'輸出' if not args.no_video else '不輸出'}")
    print()
    
    # 執行追蹤
    start_time = datetime.now()
    
    try:
        print("▶  開始追蹤...\n")
        results = run_ball_tracking(config)
        
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()
        
        # 結果摘要
        print("\n" + "="*90)
        print("📊 追蹤完成")
        print("="*90)
        
        if results:
            print(f"✅ 處理數量：{len(results)} 支視頻")
            for i, path in enumerate(results, 1):
                print(f"   {i}. {Path(path).name}")
        else:
            print("⚠️  未產生結果")
        
        print(f"⏱️  耗時：{duration:.2f} 秒")
        print("="*90)
        
        print("\n🎉 追蹤完成！")
        
    except KeyboardInterrupt:
        print("\n\n⛔ 使用者中止追蹤")
        
    except Exception as e:
        print(f"\n❌ 追蹤失敗：{e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()

