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

import setuptools
from distutils import ccompiler

# 🔥 強制移除 MSVC 的 /GL（Whole Program Optimization）
if ccompiler.get_default_compiler() == "msvc":
    from distutils._msvccompiler import MSVCCompiler

    _orig_compile = MSVCCompiler.compile

    def _compile_without_gl(self, sources, *args, **kwargs):
        if "extra_preargs" in kwargs and kwargs["extra_preargs"]:
            kwargs["extra_preargs"] = [
                arg for arg in kwargs["extra_preargs"]
                if arg.upper() != "/GL"
            ]
        return _orig_compile(self, sources, *args, **kwargs)

    MSVCCompiler.compile = _compile_without_gl

extensions = [
    Extension(
        "meshflow_stabilize_fast",
        ["meshflow_stabilize_fast.pyx"],
        include_dirs=[np.get_include()],
    )
]

setup(
    name="meshflow_stabilize_fast",
    ext_modules=cythonize(extensions, language_level="3"),
    include_dirs=[np.get_include()],
)
