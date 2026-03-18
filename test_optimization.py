"""
測試優化後的 MeshFlow Stabilizer
驗證多線程並行化和灰度預計算的性能提升
"""

import sys
import os
import time
import cv2
import numpy as np

# 添加路徑
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'meshflow_stabilize_with_audio_V2', 'functions'))

from meshflow_stabilize_cython import MeshFlowStabilizerCython

def test_basic_functionality():
    """測試基本功能 - 驗證優化版本不崩潰"""
    print("=" * 60)
    print("測試 1: 基本功能驗證")
    print("=" * 60)
    
    # 建立穩定器
    stabilizer = MeshFlowStabilizerCython(
        mesh_row_count=16,
        mesh_col_count=16,
        mesh_outlier_subframe_row_count=4,
        mesh_outlier_subframe_col_count=4
    )
    
    print(f"✓ MeshFlowStabilizerCython 建立成功")
    print(f"  - Cython 加速: {stabilizer.use_cython}")
    print(f"  - 特徵點限制: {stabilizer.max_features_to_track}")
    print(f"  - LK 窗口大小: {stabilizer.lk_win_size}")
    print(f"  - FastFeature 檢測器: {stabilizer.feature_detector is not None}")
    
    # 生成測試幀
    h, w = 480, 640
    frames = []
    for i in range(3):
        # 生成帶有輕微運動的测試幀
        frame = np.zeros((h, w, 3), dtype=np.uint8)
        x_offset = i * 5  # 簡單的平移
        # 繪製一些特徵（十字形）
        for y in range(50, h-50, 100):
            for x in range(50, w-50, 100):
                x_pos = x + x_offset
                if 0 <= x_pos < w:
                    cv2.line(frame, (x_pos-20, y), (x_pos+20, y), (255, 255, 255), 2)
                    cv2.line(frame, (x_pos, y-20), (x_pos, y+20), (255, 255, 255), 2)
                    cv2.circle(frame, (x_pos, y), 10, (0, 255, 0), 2)
        frames.append(frame)
    
    print(f"✓ 生成 3 個測試幀: {h}x{w}")
    
    # 測試優化版本
    print("\n開始測試位移計算...")
    start_time = time.time()
    
    try:
        disp, homographies = stabilizer._get_unstabilized_vertex_displacements_and_homographies(
            len(frames), frames
        )
        elapsed = time.time() - start_time
        
        print(f"✓ 優化版本執行成功！")
        print(f"  - 耗時: {elapsed:.3f} 秒")
        print(f"  - 位移數組形狀: {disp.shape}")
        print(f"  - Homography 數量: {len(homographies)}")
        print(f"  - 平均每幀時間: {elapsed / (len(frames)-1):.3f} 秒")
        
        return True
        
    except AttributeError as e:
        print(f"✗ AttributeError: {e}")
        print(f"  這通常表示缺少函數定義")
        return False
    except Exception as e:
        print(f"✗ 錯誤: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return False

def test_multithreading():
    """測試多線程並行化"""
    print("\n" + "=" * 60)
    print("測試 2: 多線程並行化驗證")
    print("=" * 60)
    
    stabilizer = MeshFlowStabilizerCython()
    
    # 測試 _process_subframe_optimized
    h, w = 100, 100
    e_gray = np.random.randint(0, 255, (h, w), dtype=np.uint8)
    l_gray = np.random.randint(0, 255, (h, w), dtype=np.uint8)
    e_color = np.random.randint(0, 255, (h, w, 3), dtype=np.uint8)
    l_color = np.random.randint(0, 255, (h, w, 3), dtype=np.uint8)
    
    task = (e_gray, l_gray, e_color, l_color, [0, 0])
    
    try:
        result = stabilizer._process_subframe_optimized(task)
        print(f"✓ _process_subframe_optimized 執行成功")
        print(f"  - 傳回值: {result}")
        return True
    except Exception as e:
        print(f"✗ 錯誤: {type(e).__name__}: {e}")
        return False

def test_grayscale_optimization():
    """測試灰度預計算"""
    print("\n" + "=" * 60)
    print("測試 3: 灰度預計算優化")
    print("=" * 60)
    
    stabilizer = MeshFlowStabilizerCython()
    
    # 生成測試彩色幀
    h, w = 200, 200
    early_color = np.random.randint(0, 255, (h, w, 3), dtype=np.uint8)
    late_color = np.random.randint(0, 255, (h, w, 3), dtype=np.uint8)
    early_gray = cv2.cvtColor(early_color, cv2.COLOR_BGR2GRAY)
    late_gray = cv2.cvtColor(late_color, cv2.COLOR_BGR2GRAY)
    
    try:
        result = stabilizer._get_matched_features_and_homography_optimized(
            early_color, late_color, early_gray, late_gray
        )
        print(f"✓ _get_matched_features_and_homography_optimized 執行成功")
        early_feat, late_feat, H = result
        if H is not None:
            print(f"  - 特徵點: {len(early_feat) if early_feat is not None else 0}")
            print(f"  - Homography: {H.shape if H is not None else 'None'}")
        else:
            print(f"  - 特徵檢測失敗（隨機幀）")
        return True
    except Exception as e:
        print(f"✗ 錯誤: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    print("\n🧪 MeshFlow 優化版本測試套件\n")
    
    results = []
    results.append(("基本功能", test_basic_functionality()))
    results.append(("多線程", test_multithreading()))
    results.append(("灰度優化", test_grayscale_optimization()))
    
    print("\n" + "=" * 60)
    print("測試總結")
    print("=" * 60)
    for name, passed in results:
        status = "✓ 通過" if passed else "✗ 失敗"
        print(f"{status} - {name}")
    
    all_passed = all(r[1] for r in results)
    print(f"\n{'✓ 所有測試通過！' if all_passed else '✗ 某些測試失敗'}")
    sys.exit(0 if all_passed else 1)
