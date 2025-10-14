import sys
import subprocess
import venv
import platform
import pathlib
import os
from dataclasses import dataclass
import shutil

MY_LIB = "JAKE"  

@dataclass  # This is just a decorator for boilerplate stuff
class EnvInfo:
    os_name: str
    arch: str
    py_version: str
    py_exec: str

class BuildBootstrap:
    def __init__(self, package_root: str, cython_sources=None):
        self.package_root = pathlib.Path(package_root).resolve()
        self.cython_sources = cython_sources or []
        self.env_dir = self.package_root / ".build_env"
        self.env = self._detect_env()
        self._print_env()
        self._ensure_env()
        self._install_build_tools()
        if self.cython_sources:
            self._build_cython_sources()
        self._env_breakdown()
        self._cleanup_env()  
        print(f"[{MY_LIB}] ✅ Build completed and environment safely removed.")

    # ---------- Detect ----------
    def _detect_env(self) -> EnvInfo:
        return EnvInfo(
            os_name=platform.system().lower(),
            arch=platform.machine().lower(),
            py_version=f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
            py_exec=sys.executable,
        )

    def _print_env(self):
        print(f"[{MY_LIB}] Detected OS: {self.env.os_name}")
        print(f"[{MY_LIB}] Architecture: {self.env.arch}")
        print(f"[{MY_LIB}] Host Python: {self.env.py_version}")

    # ---------- Env creation ----------
    def _ensure_env(self):
        if not self.env_dir.exists():
            print(f"[{MY_LIB}] Creating isolated build environment at {self.env_dir}")
            builder = venv.EnvBuilder(with_pip=True, clear=True)
            builder.create(self.env_dir)
        else:
            print(f"[{MY_LIB}] Reusing existing build environment at {self.env_dir}")

    @property
    def _env_python(self) -> str:
        exe = "python.exe" if self.env.os_name.startswith("win") else "python"
        return str(self.env_dir / ("Scripts" if "win" in self.env.os_name else "bin") / exe)

    # ---------- Install base tools ----------
    def _install_build_tools(self):
        print(f"[{MY_LIB}] Installing build tools (setuptools, wheel, Cython)...")
        subprocess.run(
            [self._env_python, "-m", "pip", "install", "--quiet", "--upgrade", "setuptools", "wheel", "Cython"],
            check=True,
        )

   # ---------- Build Cython modules ----------
    def _build_cython_sources(self):
        """Build all .pyx modules into compiled .so/.pyd using the local setup.py."""
        print(f"[{MY_LIB}] Compiling all Cython modules in directory...")

        import subprocess, shutil, os

        # locate setup.py
        setup_path = self.package_root / "setup.py"
        if not setup_path.exists():
            raise FileNotFoundError(f"[{MY_LIB}] setup.py not found at {setup_path}")

        # clean up old build artifacts
        for pattern in ["TSW_Package", "*.so", "*.c", "*.o", "build"]:
            subprocess.run(f"rm -rf {pattern}", shell=True, cwd=self.package_root)

        # recreate the output directory
        os.makedirs(self.package_root / "TSW_Package", exist_ok=True)

        # ensure numpy is available in the build env
        subprocess.run(
            [self._env_python, "-m", "pip", "install", "--quiet", "numpy"],
            check=True
        )

        # build Cython modules
        try:
            subprocess.run(
                [self._env_python, str(setup_path), "build_ext", "--inplace"],
                cwd=self.package_root,
                check=True,
            )

            # copy results into TSW_Package
            for so_file in self.package_root.glob("*.so"):
                shutil.copy(so_file, self.package_root / "TSW_Package")
            init_py = self.package_root / "__init__.py"
            if init_py.exists():
                shutil.copy(init_py, self.package_root / "TSW_Package")

            # final cleanup
            subprocess.run("rm -rf build *.c", shell=True, cwd=self.package_root)

            print(f"[{MY_LIB}] ✅ All Cython modules compiled and packaged successfully.")
        except subprocess.CalledProcessError as e:
            raise RuntimeError(f"[{MY_LIB}] ❌ Cython build failed: {e}")


    # ---------- Run test main --------------
    def _test_main(self):
        """Optionally run a simple main test after build."""
        import importlib

        print(f"[{MY_LIB}] Running optional main.py test...")
        try:
            main_module = importlib.import_module("main")
            if hasattr(main_module, "main"):
                main_module.main()
                print(f"[{MY_LIB}] ✅ main.py executed successfully.")
            else:
                print(f"[{MY_LIB}] ⚠️ main.py has no 'main()' function.")
        except ModuleNotFoundError:
            print(f"[{MY_LIB}] ⚠️ No main.py found in current directory.")
        except Exception as e:
            print(f"[{MY_LIB}] ❌ main.py test failed: {e}")


    # ---------- Breakdown summary ----------
    def _env_breakdown(self):
        print(f"\n[{MY_LIB}] ✅ Environment Setup Summary")
        print("=" * 60)
        print(f"Package root     : {self.package_root}")
        print(f"Virtual env path : {self.env_dir}")
        print(f"Python executable: {self._env_python}")
        print(f"OS / Arch        : {self.env.os_name} / {self.env.arch}")
        print(f"Python version   : {self.env.py_version}")

        try:
            pkgs = subprocess.check_output(
                [self._env_python, "-m", "pip", "list", "--format=columns"], text=True
            )
            print("-" * 60)
            print("Installed packages:")
            for line in pkgs.strip().splitlines()[2:]:
                print("  " + line)
        except Exception as e:
            print(f"[{MY_LIB}] (Warning) Could not list packages: {e}")

        print("=" * 60)
        print(f"[{MY_LIB}] Build complete and environment ready.\n")

    # ---------- Cleanup ----------
    def _cleanup_env(self):
        """Remove the temporary virtual environment used for building."""
        if self.env_dir.exists():
            print(f"[{MY_LIB}] Cleaning up temporary build environment: {self.env_dir}")
            try:
                shutil.rmtree(self.env_dir)
                print(f"[{MY_LIB}] ✅ Removed build environment.")
            except Exception as e:
                print(f"[{MY_LIB}] ⚠️ Could not fully remove build environment: {e}")
