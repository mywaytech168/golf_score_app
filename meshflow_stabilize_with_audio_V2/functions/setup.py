"""
Cython 编译配置文件

使用方法：
  python setup.py build_ext --inplace

编译后会生成 meshflow_stabilize_fast.so（Linux）或 .pyd（Windows）
"""

from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy as np
import sys

# Windows MSVC 使用 /O2，其他编译器使用 -O3
if sys.platform == 'win32':
    compile_args = ["/O2"]
else:
    compile_args = ["-O3"]

extensions = [
    Extension(
        "meshflow_stabilize_fast",
        ["meshflow_stabilize_fast.pyx"],
        include_dirs=[np.get_include()],
        extra_compile_args=compile_args,
    ),
    Extension(
        "meshflow_warp_fast",
        ["meshflow_warp_fast.pyx"],
        include_dirs=[np.get_include()],
        extra_compile_args=compile_args,
    )
]

setup(
    name="meshflow_stabilize_fast",
    ext_modules=cythonize(extensions, language_level="3"),
    include_dirs=[np.get_include()],
)
