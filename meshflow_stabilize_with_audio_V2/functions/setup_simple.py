"""
Simplified Cython compilation - avoid complex NumPy types
"""

from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy as np
import sys

# Windows MSVC uses /O2
if sys.platform == 'win32':
    compile_args = ["/O2"]
else:
    compile_args = ["-O3"]

extensions = [
    Extension(
        "meshflow_stabilize_fast",
        ["meshflow_stabilize_fast_simple.pyx"],
        include_dirs=[np.get_include()],
        extra_compile_args=compile_args,
    )
]

setup(
    name="meshflow_stabilize_fast",
    ext_modules=cythonize(extensions, language_level="3"),
    include_dirs=[np.get_include()],
)
