#!/usr/bin/env python3
"""
测试 NumpyEncoder 是否能正确处理 numpy 数据类型
"""

import json
import numpy as np
import pandas as pd
from datetime import datetime
from pathlib import Path


class NumpyEncoder(json.JSONEncoder):
    """支持 numpy 數據類型的 JSON Encoder"""
    def default(self, obj):
        try:
            if isinstance(obj, np.integer):
                return int(obj)
            elif isinstance(obj, np.floating):
                return float(obj)
            elif isinstance(obj, np.ndarray):
                return obj.tolist()
            elif isinstance(obj, np.bool_):
                return bool(obj)
            elif isinstance(obj, (datetime, Path)):
                return str(obj)
        except Exception:
            pass
        return super().default(obj)


def test_numpy_encoder():
    """测试各种 numpy 数据类型"""
    print("=" * 80)
    print("测试 NumpyEncoder")
    print("=" * 80)
    
    # 创建测试数据
    test_data = {
        "int64": np.int64(123),
        "int32": np.int32(456),
        "float64": np.float64(123.45),
        "float32": np.float32(67.89),
        "bool": np.bool_(True),
        "array": np.array([1, 2, 3]),
        "datetime": datetime.now(),
        "path": Path("/home/user"),
        "nested": {
            "values": [np.int64(1), np.float64(2.5), np.bool_(False)],
            "arrays": [np.array([1, 2]), np.array([3, 4])]
        }
    }
    
    try:
        result = json.dumps(test_data, indent=2, ensure_ascii=False, cls=NumpyEncoder)
        print("✅ JSON 序列化成功！")
        print("\n输出结果：")
        print(result)
        return True
    except Exception as e:
        print(f"❌ JSON 序列化失败：{e}")
        return False


def test_dataframe_encoder():
    """测试 pandas DataFrame 中的数据"""
    print("\n" + "=" * 80)
    print("测试 DataFrame 数据")
    print("=" * 80)
    
    # 创建 DataFrame
    df = pd.DataFrame({
        'column_a': [1, 2, 3],
        'column_b': [1.5, 2.5, 3.5],
        'column_c': [True, False, True]
    })
    
    # 转换为字典
    data_dict = {
        "dataframe": str(df),
        "values": df.values.tolist(),
        "dtypes": {k: str(v) for k, v in df.dtypes.items()},
        "dict": df.to_dict('list')  # 这会生成 numpy int64
    }
    
    try:
        result = json.dumps(data_dict, indent=2, ensure_ascii=False, cls=NumpyEncoder)
        print("✅ DataFrame 数据序列化成功！")
        print("\n输出结果（前 500 字符）：")
        print(result[:500])
        return True
    except Exception as e:
        print(f"❌ DataFrame 数据序列化失败：{e}")
        return False


def test_processing_result():
    """测试真实的处理结果数据结构"""
    print("\n" + "=" * 80)
    print("测试真实处理结果数据")
    print("=" * 80)
    
    result_data = {
        'queueItemId': '1',
        'videoId': '345049fc-e84b-42df-811c-859dea4dd0d5',
        'inputDir': '\\\\10.1.1.101\\ORVIA\\videos\\...',
        'processedAt': datetime.now().isoformat(),
        'steps': {
            'stabilization': {
                'status': 'completed',
                'duration': np.float64(48.3),
                'result': {
                    'mode': 'segment_meshflow',
                    'segment': (np.int64(10), np.int64(120)),
                    'crop_boundaries': (np.int64(5), np.int64(10), np.int64(15), np.int64(20)),
                }
            },
            'audio_analysis': {
                'status': 'completed',
                'duration': np.float64(12.5),
                'result': {
                    'hits_detected': np.int64(5),
                    'denoised_summary_path': 'result_denoised_summary.csv'
                }
            },
            'audio_scoring': {
                'status': 'completed',
                'duration': np.float64(3.8),
                'result': 'DataFrame with scores'
            }
        }
    }
    
    try:
        result = json.dumps(result_data, indent=2, ensure_ascii=False, cls=NumpyEncoder)
        print("✅ 处理结果数据序列化成功！")
        print("\n输出结果（前 800 字符）：")
        print(result[:800])
        return True
    except Exception as e:
        print(f"❌ 处理结果数据序列化失败：{e}")
        import traceback
        traceback.print_exc()
        return False


if __name__ == "__main__":
    all_passed = True
    
    all_passed &= test_numpy_encoder()
    all_passed &= test_dataframe_encoder()
    all_passed &= test_processing_result()
    
    print("\n" + "=" * 80)
    if all_passed:
        print("✅ 所有测试通过！NumpyEncoder 工作正常。")
    else:
        print("❌ 部分测试失败，需要进一步调查。")
    print("=" * 80)
