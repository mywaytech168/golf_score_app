#!/usr/bin/env python3
"""
诊断脚本 - 检查 task_queue.py 是否包含修复
"""

import sys
from pathlib import Path

def check_numpy_encoder():
    """检查 NumpyEncoder 是否存在"""
    print("=" * 80)
    print("诊断：检查 NumpyEncoder 修复")
    print("=" * 80)
    
    task_queue_path = Path(__file__).parent / "services" / "task_queue.py"
    
    if not task_queue_path.exists():
        print(f"❌ 文件不存在：{task_queue_path}")
        return False
    
    with open(task_queue_path, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 检查 NumpyEncoder 类
    if "class NumpyEncoder" in content:
        print("✅ 找到 NumpyEncoder 类定义")
    else:
        print("❌ 未找到 NumpyEncoder 类定义")
        return False
    
    # 检查 numpy 导入
    if "import numpy as np" in content:
        print("✅ 找到 numpy 导入")
    else:
        print("❌ 未找到 numpy 导入")
        return False
    
    # 检查 cls=NumpyEncoder
    if "cls=NumpyEncoder" in content:
        print("✅ 找到 json.dumps(..., cls=NumpyEncoder) 调用")
    else:
        print("❌ 未找到 json.dumps(..., cls=NumpyEncoder) 调用")
        return False
    
    # 检查 isinstance(obj, np.integer)
    if "isinstance(obj, np.integer)" in content:
        print("✅ 找到 np.integer 类型检查")
    else:
        print("❌ 未找到 np.integer 类型检查")
        return False
    
    print("\n✅ 所有检查通过！修复已正确应用。")
    print("\n📝 下一步：")
    print("   1. 重启 Python 服务器")
    print("   2. 清理 __pycache__ 缓存")
    print("   3. 重新运行处理流程")
    
    return True


def show_statistics(file_path):
    """显示文件统计"""
    with open(file_path, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # 找到 NumpyEncoder 的位置
    for i, line in enumerate(lines, 1):
        if "class NumpyEncoder" in line:
            print(f"\n📍 NumpyEncoder 类定义在第 {i} 行")
            break
    
    # 找到 cls=NumpyEncoder 的位置
    for i, line in enumerate(lines, 1):
        if "cls=NumpyEncoder" in line:
            print(f"📍 json.dumps 调用在第 {i} 行")
            break
    
    print(f"📊 总行数：{len(lines)}")


if __name__ == "__main__":
    if check_numpy_encoder():
        task_queue_path = Path(__file__).parent / "services" / "task_queue.py"
        show_statistics(task_queue_path)
        sys.exit(0)
    else:
        sys.exit(1)
