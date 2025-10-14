from setuptools import setup
from setuptools.extension import Extension
from Cython.Build import cythonize
import numpy

# Define all your Cython modules here
extensions = [
    Extension(
        name="TSW_scoreMat",
        sources=["TSW_scoreMat.pyx"],
        include_dirs=[numpy.get_include()],
        extra_compile_args=["-O3"],
    ),
    Extension(
        name="find_best_score",
        sources=["find_best_score.pyx"],
        include_dirs=[numpy.get_include()],
        extra_compile_args=["-O3"],
    ),
    Extension(
        name="align_TSW",
        sources=["align_TSW.pyx"],
        include_dirs=[numpy.get_include()],
        extra_compile_args=["-O3"],
    ),
    Extension(
        name="init_TSW",
        sources=["init_TSW.pyx"],
        include_dirs=[numpy.get_include()],
        extra_compile_args=["-O3"],
    ),
    Extension(
        name="run_TSW",
        sources=["run_TSW.pyx"],
        include_dirs=[numpy.get_include()],
        extra_compile_args=["-O3"],
    ),
]

setup(
    name="TSW_Package",
    ext_modules=cythonize(
        extensions,
        compiler_directives={
            "boundscheck": False,
            "wraparound": False,
            "nonecheck": True,
            "cdivision": True,
            "language_level": 3,
        },
    ),
)
