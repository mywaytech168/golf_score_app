from setuptools import setup, Extension
from Cython.Build import cythonize
import numpy as np

extensions = [
    Extension(
        "meshflow_stabilize_fast",
        ["meshflow_stabilize_fast_minimal.pyx"],
        include_dirs=[np.get_include()],
    )
]

setup(
    name="meshflow_stabilize_fast",
    ext_modules=cythonize(extensions, language_level="3"),
    include_dirs=[np.get_include()],
)
