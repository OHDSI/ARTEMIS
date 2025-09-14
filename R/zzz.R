.onLoad <- function(libname, pkgname) {
  # Read the venv python path recorded during build
  venv_file <- system.file(".venv_python", package = pkgname)
  if (!file.exists(venv_file)) {
    packageStartupMessage("⚠️ .venv_python not found in installed package.")
    return()
  }

  venv_python <- trimws(readLines(venv_file, warn = FALSE)[1])
  if (!file.exists(venv_python)) {
    packageStartupMessage("⚠️ Python venv path in .venv_python is invalid: ", venv_python)
    return()
  }

  # Force reticulate to use this Python
  Sys.setenv(RETICULATE_PYTHON = venv_python)
  reticulate::py_config()

  pkg_root   <- system.file(package = pkgname)
  python_dir <- file.path(pkg_root, "python")
  dist_dir   <- file.path(pkg_root, "dist")

  # Inject both dirs into sys.path before sourcing anything
  reticulate::py_run_string(
    sprintf(
      "import sys; sys.path.insert(0, r'%s'); sys.path.insert(0, r'%s')",
      python_dir, dist_dir
    )
  )

  # Debug print so you SEE what python got picked
  reticulate::py_run_string("import sys; print('🔧 Python:', sys.executable); print('🔢 Version:', sys.version)")

  # Source all entrypoints
  reticulate::source_python(file.path(python_dir, "init.py"),  envir = globalenv())
  reticulate::source_python(file.path(python_dir, "score.py"), envir = globalenv())
  reticulate::source_python(file.path(python_dir, "align.py"), envir = globalenv())
  reticulate::source_python(file.path(python_dir, "main.py"),  envir = globalenv())
}
