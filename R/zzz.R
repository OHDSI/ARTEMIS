.onLoad <- function(libname, pkgname) {
  
  # ----------- EVN SETUP BLOCK -----------
  # Resolve paths from ENV or use fallback
  ARTEMIS_PYTHON <- Sys.getenv("ARTEMIS_PYTHON", unset = Sys.which("python"))
  DEBUG <- tolower(Sys.getenv("ARTEMIS_DEBUG", unset = "false")) == "true"

  message("[ARTEMIS-boot-R] Setup env...")
  message("[ARTEMIS-boot-R] Initializing Python backend...")

  # (Optional) Development friendly chunk
  ARTEMIS_DIR_PATH <- Sys.getenv("ARTEMIS_DIR_PATH", unset="")
  DEVTOOLS_DIR_PATH <- Sys.getenv("DEVTOOLS_DIR_PATH", unset = "")
  custom_paths <- c(ARTEMIS_DIR_PATH, DEVTOOLS_DIR_PATH)
  valid_custom_paths <- custom_paths[nzchar(custom_paths)] # filter "" paths
  if (length(valid_custom_paths) > 0) {
      .libPaths(c(valid_custom_paths, .libPaths()))
  }

  # ----------- Python runtime  -----------
  # Find what python executable for R and set PATH
  python_path = ARTEMIS_PYTHON
  if (!nzchar(python_path)) {
    stop(
      "[X] No 'python' binary found on PATH.\n",
      "Please install Python 3.12+ first.\n",
      "In case you have a specific Python environment, just set the path:\n",
      "Sys.setenv(ARTEMIS_PYTHON = \"/path/to/your/python\")\n",
      "Then re-run the script."
    )
  }
  # ---------- Ensure reticulate is installed and loaded ------------------
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    if (DEBUG) message("[ARTEMIS-boot-R] Installing 'reticulate' package...")
    install.packages("reticulate", repos = "https://cloud.r-project.org")
  }
  library(reticulate)

  # --------------- Setup project scope reticulate virtualenv ----------
  package_root <- system.file(package = pkgname)
  venv_path <- file.path(package_root, ".r-reticulate")
  
  # temp envdir does not trigger compilation
  is_temp_install <- grepl("00LOCK", package_root) 
  
  # skip repeats
  if (!dir.exists(venv_path)) {
    virtualenv_create(venv_path, python = python_path)
  }
  use_virtualenv(venv_path, required = TRUE)
  
  # -------- [Safeguard] Enforce minimum Python version with a fallback ------------------------
  cfg <- tryCatch(py_config(), error = function(e) NULL)
  
  if (is.null(cfg)) {
    os <- Sys.info()[["sysname"]]
    cat("\n[ARTEMIS-boot-R] ERR No Python interpreter detected.\n")
    cat("[ARTEMIS-boot-R] Requires Python 3.12 or newer.\n\n")

    if (os == "Windows") {
      cat(">  Windows detected.\n")
      cat("   Install Python 3.12 from the Microsoft Store or from:\n")
      cat("   https://www.python.org/downloads/windows/\n")
      cat("   During installation:\n")
      cat("   - [] Check 'Add Python to PATH'\n")
      cat("   - [] Install for all users if possible\n\n")
    } else if (os == "Darwin") {
      cat(">  macOS detected.\n")
      cat("   Install Python 3.12 using Homebrew or from:\n")
      cat("   https://www.python.org/downloads/macos/\n")
      cat("   Example command:\n")
      cat("     brew install python@3.12\n\n")
    } else {
      cat(">  Linux detected.\n")
      cat("   Install Python 3.12 with your package manager, e.g.:\n")
      cat("     sudo apt install python3.12 python3.12-venv python3.12-dev\n")
      cat("   or from:\n")
      cat("     https://www.python.org/downloads/source/\n\n")
    }
    
    # --------------- User Message to rerun R installer ---------------------------
    cat("After installing Python 3.12+, restart R and rerun the installation:\n")
    cat("   devtools::install_github('OHDSI/ARTEMIS')\n")
    cat("Then load the package normally:\n")
    cat("   library(ARTEMIS)\n\n")
    stop("[ARTEMIS-boot-R] Aborting setup: Python 3.12+ required.")
  }

  ver_major <- as.numeric(cfg$version$major)
  ver_minor <- as.numeric(cfg$version$minor)
  if (ver_major < 3 || (ver_major == 3 && ver_minor < 12)) {
    stop(paste0(
      "[ARTEMIS-boot-R] Detected Python ", cfg$version$version,
      " — too old. Please upgrade to Python 3.12 or newer, then rerun:\n",
      "   devtools::install_github('OHDSI/ARTEMIS')"
    ))
  }
  # ---------- (Optional) Logging environment configuration ---------------
  if (DEBUG) cat("[ARTEMIS-boot-R] Environment details:", "\n")
  if (DEBUG) cat("path:           ", venv_path, "\n")
  if (DEBUG) print(cfg)

  # ------------- Lock the interpreter path for both build and runtime -----------
  py_exec <- cfg$python
  
  # ------------ Install required py packages =----------------------------
  # Note - reticulate installs numpy by default with `virtualenv_create`.
  required <- c("numpy", "pandas")
  for (pkg in required) {
    if (!py_module_available(pkg)) {
      if (DEBUG) message(sprintf("[ARTEMIS-boot-R] Installing Python module: %s", pkg))
      py_install(pkg, python = python_path)
    }
  }
  cfg <- tryCatch(py_config(), error = function(e) NULL)

  # -------------- Trigger Python bootstrap build under the same interpreter -------
  cython_dir     <- file.path(package_root, "cython")
  cython_sources <- list.files(cython_dir, pattern = "\\.pyx$", full.names = TRUE)
  bootstrap_path <- system.file("cython/bootstrap_env.py", package = pkgname)
  
  if (!is_temp_install) {
    # ----------------------------------------------------------------------------------
    # BUILD BLOCK
    # ----------------------------------------------------------------------------------
    
    if (DEBUG) cat("[ARTEMIS-boot-R] Checking Cython modules — running Py bootstrap...\n")
    reticulate::source_python(bootstrap_path)
    
    # Run builder
    pyObject <- py$BuildBootstrap(
      package_root = package_root,
      cython_sources = cython_sources
    )

    use_python <- pyObject$cython_failed

    # Cleaning
    reticulate::py_run_string("import gc; gc.collect()")

    # ------------------------------------------
    # RUNTIME BLOCK
    # ------------------------------------------

    if (DEBUG) cat("[ARTEMIS-boot-R] Loading alignment algorithm...\n")
    ns <- asNamespace(pkgname)

    mod_path <- if (use_python) "python" else "cython"

    py_functions <- tryCatch(
      reticulate::import_from_path("main", path = file.path(package_root, mod_path)),
      error = function(e) {
        if (mod_path == "cython") {
          warning("[ARTEMIS-boot-R] [WARN!] Cython import failed, falling back to Python")
          return(NULL)
        } else {
          stop("[ARTEMIS-boot-R] [X] Failed to import Python fallback module: ", e$message)
        }
      }
    )

    if (!is.null(py_functions$align_patients_regimens)) {
      assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
      message(sprintf("[ARTEMIS-boot-R] [OK] align_patients_regimens loaded (%s)", mod_path))
      return(invisible(NULL))
    }

    # If Cython failed silently, attempt Python fallback once more
    if (mod_path == "cython") {
      py_functions <- reticulate::import_from_path("main", path = file.path(package_root, "python"))
      if (!is.null(py_functions$align_patients_regimens)) {
        assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
        message("[ARTEMIS-boot-R] [OK] align_patients_regimens loaded (python fallback)")
        return(invisible(NULL))
      }
    }

    stop("[ARTEMIS-boot-R] [X] align_patients_regimens not found in any module")
  }
}
