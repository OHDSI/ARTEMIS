import sys
import subprocess
import venv
import platform
import pathlib
import os
from dataclasses import dataclass
import shutil

# This should be install directory
# devtools::install_github("OHDSI/ARTEMIS")

# During install_github step this happens:
# inst/cython/bootstrap_env.py  →  <R-LIB>/ARTEMIS/cython/bootstrap_env.py
# inst/cython/setup.py          →  <R-LIB>/ARTEMIS/cython/setup.py

LIB_LABEL = "ARTEMIS"  

@dataclass  # Just a decorator for boilerplate stuff
class EnvInfo:
    os_name: str
    arch: str
    py_version: str
    py_exec: str


class BootstrapGraph:
    """Chain of responsivility"""
    def __init__(self):
        self.phases = {}         # name → (deps, func)
        self.completed = set()   # name → already executed

    def add(self, name, deps, func):
        self.phases[name] = (deps, func)

    def run(self, name):
        if name in self.completed:
            return

        if name not in self.phases:
            raise ValueError(f"Phase '{name}' not registered")

        deps, func = self.phases[name]
        for dep in deps:
            self.run(dep)

        # Dev log
        # print(f"[{LIB_LABEL}-boot-Py] Running phase: {name}")
        func()
        self.completed.add(name)


class AlreadyBuilt(Exception): pass

class BuildBootstrap:
    def __init__(self, package_root: str, cython_sources=None):
        self.package_root = pathlib.Path(package_root).resolve()
        self.cython_sources = cython_sources or []
        self.env_dir = pathlib.Path(sys.prefix)  # uses reticulate's active virtualenv
        self.env = self._detect_env()
        self.cython_failed = False

        self._print_env()

        bg = BootstrapGraph()
        bg.add("ensure_env", [], self._ensure_env)
        bg.add("site_packages_dir", ["ensure_env"], self._set_site_packages_dir)
        bg.add("site_packages_var", ["site_packages_dir"], self._set_site_packages_var)
        bg.add("check_build", ["site_packages_dir"], self._already_built)
        bg.add("install", ["check_build"], self._install_build_tools)

        if self.cython_sources:
            bg.add("compile", ["install"], self._build_cython_sources_wrap)
            bg.add("copy", ["compile"], self._copy_so_outputs)
            bg.add("load", ["copy"], self._write_init_py)
            top_phase = "load"
        else:
            top_phase = "install"

        try:
            bg.run(top_phase)
        except AlreadyBuilt:
            pass  # Exit quietly

        print(f"[{LIB_LABEL}-boot-Py] [OK] Build completed.")
    
    # ---------- Detect ----------
    def _detect_env(self) -> EnvInfo:
        return EnvInfo(
            os_name=platform.system().lower(),
            arch=platform.machine().lower(),
            py_version=f"{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}",
            py_exec=sys.executable,
        )

    def _print_env(self):
        print(f"[{LIB_LABEL}-boot-Py] Detected OS: {self.env.os_name}")
        print(f"[{LIB_LABEL}-boot-Py] Architecture: {self.env.arch}")
        print(f"[{LIB_LABEL}-boot-Py] Host Python: {self.env.py_version}")

    # ---------- Env creation ----------
    def _ensure_env(self):
        if not self.env_dir.exists():
            print(f"[{LIB_LABEL}-boot-Py] Creating isolated build environment at {self.env_dir}")
            builder = venv.EnvBuilder(with_pip=True, clear=True)
            builder.create(self.env_dir)
        else:
            print(f"[{LIB_LABEL}-boot-Py] Reusing existing build environment at {self.env_dir}")

    @property
    def _env_python(self) -> str:
        # exe = "python.exe" if self.env.os_name.startswith("win") else "python"
        # return str(self.env_dir / ("Scripts" if "win" in self.env.os_name else "bin") / exe)
        return sys.executable  # directly reticulate's Python

    def _set_site_packages_dir(self):
        """Single directory to store all python site package"""
        site_packages_dir = pathlib.Path(subprocess.check_output([
            self._env_python, "-c",
            "import site; print(site.getsitepackages()[0])"
        ]).decode().strip())

        self.site_packages_dir = site_packages_dir 

    def _set_site_packages_var(self):
        os.environ['TSW_PACKAGE_PATH'] = str(self.site_packages_dir)

    def _already_built(self) -> bool:
        target_dir = self.site_packages_dir / "TSW_Package"
        if not target_dir.exists():
            return False

        ext = ".pyd" if self.env.os_name.startswith("win") else ".so"
        files = list(target_dir.glob(f"*{ext}"))
        compiled = len([f for f in files if f.stat().st_size > 4096]) >= 3
        if compiled:
            print(f"[{LIB_LABEL}-boot-Py] Already built. Skipping rebuild.")
            raise AlreadyBuilt()
        
    # ---------- Install base tools ----------
    def _install_build_tools(self):
        # TODO: No internet for some users!
        print(f"[{LIB_LABEL}-boot-Py] Installing build tools and dependencies (setuptools, wheel, Cython, numpy, pandas)...")
        subprocess.run(
            [
                self._env_python, "-m", "pip", "install", "--quiet", "--upgrade",
                "setuptools",
                "wheel",
                "Cython",
                "numpy",
                "pandas",
                "tqdm"
            ],
            check=True,
        )
        print(f"[{LIB_LABEL}-boot-Py] Build dependencies installed successfully.")


    # ---------- Build Cython modules ----------
    def _build_cython_sources(self):
        """Build all .pyx modules into compiled .so/.pyd using setup.py in cython/."""
        print(f"[{LIB_LABEL}-boot-Py] Compiling Cython modules")

        cython_dir = self.package_root / "cython" # temp mirror
        setup_path = cython_dir / "setup.py"
        if not setup_path.exists():
            raise FileNotFoundError(f"[{LIB_LABEL}-boot-Py] setup.py not found at {setup_path}")

        target_dir = pathlib.Path(self.site_packages_dir) / "TSW_Package"
        os.makedirs(target_dir, exist_ok=True)

        # Compile Cython using the venv's python
        subprocess.run(
            [self._env_python, str(setup_path), "build_ext", "--inplace"],
            cwd=cython_dir,
            check=True
        )

        print(f"[{LIB_LABEL}-boot-Py] [OK] Cython compilation complete.")

    def _build_cython_sources_wrap(self):
        """Wrapper around _build_cython_sources to allow clean fallback if Cython fails."""
        try:
            self._build_cython_sources()
        except Exception as e:
            print(f"[{LIB_LABEL}-boot-Py] [WARN!] Cython build Failed — falling back to pure Python.\nReason build failed:\n{e}")
            self.cython_failed = True
            return # allow build continuation

    # ---------- Breakdown summary ----------
    def _env_breakdown(self):
        print(f"\n[{LIB_LABEL}-boot-Py] [OK] Environment Setup Summary")
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
            print(f"[{LIB_LABEL}-boot-Py] [WARN!] Could not list packages: {e}")

        print("=" * 60)
        print(f"[{LIB_LABEL}-boot-Py] Build complete and environment ready.\n")

    def _copy_so_outputs(self):
        """Copy .so/.pyd files into TSW_Package/"""
        if not self.cython_failed:
            build_dir = self.package_root / "cython"
            target_dir = self.site_packages_dir / "TSW_Package"
            print(f"[{LIB_LABEL}-boot-Py] Site package dir used: {target_dir}")
            target_dir.mkdir(exist_ok=True)

            for ext in ["*.so", "*.pyd"]:
                for compiled_file in build_dir.glob(ext):
                    shutil.copy2(compiled_file, target_dir)
                    print(f"[{LIB_LABEL}-boot-Py] Copied: {compiled_file.name} → TSW_Package")

    def _write_init_py(self):
        """Write __init__.py pointing to Cython entrypoint"""
        if not self.cython_failed:
            init_path = self.site_packages_dir / "TSW_Package" / "__init__.py"
            with open(init_path, "w") as f:
                f.write("from .run_TSW import align_patients_regimens_fast\n")
                f.write("__all__ = [align_patients_regimens_fast,]\n")
            print(f"[{LIB_LABEL}-boot-Py] __init__.py written for TSW_Package")
