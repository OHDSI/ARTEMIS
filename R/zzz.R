.onLoad <- function(libname, pkgname) {
  
  # ----------- EVN SETUP BLOCK -----------
  # Resolve paths from ENV or use fallback
  ARTEMIS_PY_VERSION <- Sys.getenv("ARTEMIS_PY_VERSION", unset = Sys.which("python"))
  message("[ARTEMIS-ENV-SETUP] Done.")
  message("[ARTEMIS-boot] Initializing Python backend...")

  # TODO: Add DEV_tools or Artemis custom path but keep libPaths!

  # ----------- Python runtime  -----------
  # Find what python executable for R and set PATH
  python_path = ARTEMIS_PY_VERSION
  if (!nzchar(python_path)) {
    stop("❌ No 'python' binary found on PATH. Install Python 3.12+ first.")
  }
  # ---------- Ensure reticulate is installed and loaded ------------------
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    message("[ARTEMIS-boot] Installing 'reticulate' package...")
    install.packages("reticulate", repos = "https://cloud.r-project.org")
  }
  library(reticulate)

  # --------------- Setup project scope reticulate virtualenv ----------
  package_root <- system.file(package = pkgname)
  venv_path <- file.path(package_root, ".r-reticulate")
  virtualenv_create(venv_path, python = python_path)
  cat("[ARTEMIS-boot] Environment path:", venv_path, "\n")
  cat("[ARTEMIS-boot] Python version to use:", python_path, "\n")
  use_virtualenv(venv_path, required = TRUE)
  
  # ---------- [Logging] Detect final Python configuration with a fallback ---------------
  cfg <- tryCatch(py_config(), error = function(e) NULL)
  print(cfg)

  if (is.null(cfg)) {
    os <- Sys.info()[["sysname"]]
    cat("\n[ARTEMIS-boot] ERR No Python interpreter detected.\n")
    cat("ARTEMIS requires Python 3.12 or newer.\n\n")

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
    stop("[ARTEMIS-boot] Aborting setup: Python 3.12+ required.")
  }

  # -------- [Safeguard] Enforce minimum Python version -------------------------------
  ver_major <- as.numeric(cfg$version$major)
  ver_minor <- as.numeric(cfg$version$minor)
  if (ver_major < 3 || (ver_major == 3 && ver_minor < 12)) {
    stop(paste0(
      "[ARTEMIS-boot] Detected Python ", cfg$version$version,
      " — too old. Please upgrade to Python 3.12 or newer, then rerun:\n",
      "   devtools::install_github('OHDSI/ARTEMIS')"
    ))
  }
  # ------------- Lock the interpreter path for both build and runtime -----------
  py_exec <- cfg$python
  message(paste("[ARTEMIS-boot] Using Python:", py_exec))
  
  # ------------ Install required py packages =----------------------------
  required <- c("numpy", "pandas")
  for (pkg in required) {
    if (!py_module_available(pkg)) {
      message(sprintf("[ARTEMIS-boot] Installing missing Python module: %s", pkg))
      py_install(pkg, python = python_path)
    }
  }
  cfg <- tryCatch(py_config(), error = function(e) NULL)

  # -------------- Trigger Python bootstrap build under the same interpreter -------
  bootstrap_path <- system.file("cython/bootstrap_env.py", package = pkgname)
  package_root   <- system.file(package = pkgname)
  cython_dir     <- file.path(package_root, "cython")
  cython_sources <- list.files(cython_dir, pattern = "\\.pyx$", full.names = TRUE)
  
  # ----------------------------------------------------------------------------------
  # BUILD BLOCK
  # ----------------------------------------------------------------------------------
  
  # -----  Will look inside reticulate python env (venv)... ----- 
  # TODO (Optional): convert to R if better ----
  tsw_dir <- py_eval("(__import__('sysconfig').get_paths()['purelib'])", convert = TRUE)

  cat("tsw_dir:", tsw_dir, '\n')

  so_files <- list.files(
    file.path(tsw_dir, "TSW_Package"),
    pattern = "\\.(so|pyd)$",
    full.names = TRUE
  )

  is_built <- length(so_files) >= 3  # heuristic: 3+ .so/.pyd = built
  cat("is_built:", is_built, '\n')
  
  if (!is_built) {
    cat("[ARTEMIS-boot] ⏳ No compiled Cython modules detected — running bootstrap...\n")
    reticulate::source_python(bootstrap_path)
  
    # Run builder (calls Python class which sys.exit(1) if build fails)
    py$BuildBootstrap(
      package_root = package_root,
      cython_sources = cython_sources
    )

    # Cleaning
    reticulate::py_run_string("import gc; gc.collect()")
  } else {
    message("[ARTEMIS-boot] ✅ Existing. Build detected — skipping bootstrap.")
  }

  # ------------------------------------------
  # RUNTIME BLOCK
  # ------------------------------------------

  cat("[ARTEMIS-boot] Loading alignment algorithm...\n")
  ns <- asNamespace(pkgname)

  mod_path <- if (is_built && length(so_files) >= 3) "cython" else "python"

  py_functions <- tryCatch(
    reticulate::import_from_path("main", path = file.path(package_root, mod_path)),
    error = function(e) {
      if (mod_path == "cython") {
        warning("[ARTEMIS-boot] ⚠️ Cython import failed, falling back to Python")
        return(NULL)
      } else {
        stop("[ARTEMIS-boot] ❌ Failed to import Python fallback module: ", e$message)
      }
    }
  )

  if (!is.null(py_functions$align_patients_regimens)) {
    assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
    message(sprintf("[ARTEMIS-boot] ✅ align_patients_regimens loaded (%s)", mod_path))
    return(invisible(NULL))
  }

  # If Cython failed silently, attempt Python fallback once more
  if (mod_path == "cython") {
    py_functions <- reticulate::import_from_path("main", path = file.path(package_root, "python"))
    if (!is.null(py_functions$align_patients_regimens)) {
      assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
      message("[ARTEMIS-boot] ✅ align_patients_regimens loaded (python fallback)")
      return(invisible(NULL))
    }
  }

  stop("[ARTEMIS-boot] ❌ align_patients_regimens not found in any module")

}
