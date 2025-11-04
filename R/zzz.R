.onLoad <- function(libname, pkgname) {
  
  # ----------- EVN SETUP BLOCK -----------

  # Enable command‑line override but default to FALSE
  if (Sys.getenv("TEST_ARTEMIS_BUILD", unset = "") == "") {
    Sys.setenv(TEST_ARTEMIS_BUILD = "FALSE")
  }

  # Resolve paths from ENV or use fallback
  ARTEMIS_PY_VERSION <- Sys.getenv("ARTEMIS_PY_VERSION", unset = Sys.which("python"))

  message("[ARTEMIS-ENV-SETUP] Done.")


  message("[ARTEMIS-boot] Initializing Python backend...")



  # ----------------- Python runtime -----------------
  # Find what python executable R would see on PATH
  python_path = ARTEMIS_PY_VERSION

  if (!nzchar(python_path)) {
    stop("❌ No 'python' binary found on PATH. Install Python 3.12+ first.")
  }

  # --------------- Ensure reticulate is installed and loaded ------------------
  if (!requireNamespace("reticulate", quietly = TRUE)) {
    message("[ARTEMIS-boot] Installing 'reticulate' package...")
    install.packages("reticulate", repos = "https://cloud.r-project.org")
  }
  
  library(reticulate)
  


  # --------------- Setup project scope reticulate virtualenv ----------
  package_root <- system.file(package = pkgname)
  venv_path <- file.path(package_root, ".r-reticulate")
  # venv_path <- "~/.virtualenvs/r-reticulate"

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
      " — too old. Please upgrade to Python 3.12 or newer, then rerun:\n", # optional !
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
  # print(cfg) # this is venv 
  # stop()

  # -------------- Trigger Python bootstrap build under the same interpreter -------
  bootstrap_path <- system.file("cython/bootstrap_env.py", package = pkgname)
  package_root   <- system.file(package = pkgname)
  cython_dir     <- file.path(package_root, "cython")
  cython_sources <- list.files(cython_dir, pattern = "\\.pyx$", full.names = TRUE)
  
  # ----------------------------------------------------------------------------------
  # BUILD BLOCK
  # ----------------------------------------------------------------------------------
  
  # -----  Will look inside reticulate python env (venv)... ----- 
  # ---- Ok, its py... TODO: convert to R if better ----
  tsw_dir <- py_eval("(__import__('sysconfig').get_paths()['purelib'])", convert = TRUE)

  cat("tsw_dir:", tsw_dir, '\n')

  so_files <- list.files(
    file.path(tsw_dir, "TSW_Package"), # From venv
    pattern = "\\.(so|pyd)$",
    full.names = TRUE
  )

  is_built <- length(so_files) >= 3  # heuristic: 3+ .so/.pyd = built
  cat("is_built:", is_built, '\n')
  
  if (!is_built) {
    # ----- Compile via reticulate ----
    reticulate::source_python(bootstrap_path)

    py$BuildBootstrap(
      package_root = package_root,
      cython_sources = cython_sources
    )

    # ----- Clean ------
    reticulate::py_run_string("import gc; gc.collect()")
  } else {
    message("[ARTEMIS-boot] ✅ Cython build found — skipping bootstrap.")
  }

  # ------------ Add Default .Rprofile ---------------------------------------

  rprofile_path <- file.path(libname, ".Rprofile")

  if (!file.exists(rprofile_path)) {
    message("[ARTEMIS-boot] Creating default .Rprofile in: ", rprofile_path)

    rprofile_lines <- c(
      "# -------- Default ARTEMIS .Rprofile (user can edit this) --------",
      "# Enables cmd overrides",
      'if (Sys.getenv("TEST_ARTEMIS_BUILD", unset = "") == "") {',
      '  Sys.setenv(TEST_ARTEMIS_BUILD = "FALSE")',
      '}',
      "# Resolve paths from ENV or use fallback",
      'Sys.setenv(ARTEMIS_DIR_PATH = normalizePath(getwd()))',
      'ARTEMIS_DIR_PATH <- Sys.getenv("ARTEMIS_DIR_PATH")', 
      'DEVTOOLS_DIR_PATH <- Sys.getenv("DEVTOOLS_DIR_PATH", unset = ".Ruserdata1")',
      'ARTEMIS_PY_VERSION <- Sys.getenv("ARTEMIS_PY_VERSION", unset = Sys.which("python"))',
      ".libPaths(c(",
      "  normalizePath(ARTEMIS_DIR_PATH, mustWork = FALSE),",
      "  normalizePath(DEVTOOLS_DIR_PATH, mustWork = FALSE),",
      "  .libPaths()",
      "))",
      'message("[ARTEMIS-env-setup] Custom lib path set via .Rprofile")'
    )

    writeLines(rprofile_lines, con = rprofile_path)
  } else {
    message("[ARTEMIS-boot] .Rprofile already exists; not overwriting.")
  }

    
  # ------------------------------------------
  # RUNTIME BLOCK
  # ------------------------------------------

  # --------------- [Logging] Show compiled C code -------------------------------
  # cat(strrep("-", 60), "\n", "[ARTEMIS-boot] C files:\n", paste(so_files, collapse = "\n"), "\n")
  cat("Is build: ", is_built, "\n")
  ns <- asNamespace(pkgname)
  # if (is_built) {
  #   cat("[ARTEMIS-boot] Using Cython version of the alignment algorithm.\n")
  #   py_functions <- reticulate::import_from_path("main", path = file.path(package_root, "cython"))
  #   assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
  #   message("[ARTEMIS-boot] ✅ align_patients_regimens (Cython) loaded successfully")
  # } else {
  #   cat("[ARTEMIS-boot] Using fallback pure Python version of the alignment algorithm.\n")
  #   py_functions <- reticulate::import_from_path("main", path = file.path(package_root, "python"))
  #   assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
  #   message("[ARTEMIS-boot] ✅⚠️ align_patients_regimens (Python) loaded — Cython build not found")
  # }

  if (is_built) {
    cat("[ARTEMIS-boot] Using Cython version of the alignment algorithm.\n")
    py_functions <- tryCatch(
      reticulate::import_from_path("main", path = file.path(package_root, "cython")),
      error = function(e) {
        stop("[ARTEMIS-boot] ❌ Failed to import Cython main module: ", e$message)
      }
    )

    if (is.null(py_functions$align_patients_regimens)) {
      stop("[ARTEMIS-boot] [X] align_patients_regimens not found in Cython main module")
    }

    assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
    message("[ARTEMIS-boot] ✅ align_patients_regimens (Cython) loaded successfully")

  } else {
    cat("[ARTEMIS-boot] Using fallback pure Python version of the alignment algorithm.\n")
    py_functions <- tryCatch(
      reticulate::import_from_path("main", path = file.path(package_root, "python")),
      error = function(e) {
        stop("[ARTEMIS-boot] [X] Failed to import Python main module: ", e$message)
      }
    )

    if (is.null(py_functions$align_patients_regimens)) {
      stop("[ARTEMIS-boot] [X] align_patients_regimens not found in Python main module")
    }

    assign("align_patients_regimens", py_functions$align_patients_regimens, envir = ns)
    message("[ARTEMIS-boot] ✅⚠️ align_patients_regimens (Python) loaded — Cython build not found")
  }

  # ------------------ TEST ----------------------------
  # Reading env var to trigger test
  TRIGGER_TEST = Sys.getenv("TEST_ARTEMIS_BUILD")

  if (TRIGGER_TEST) {
    # Full Package
    cy_path <- file.path(package_root, "cython")
    py_path <- file.path(package_root, "python")

    cy <- reticulate::import_from_path("main", path = cy_path)
    py <- reticulate::import_from_path("main", path = py_path)

    cat("[ARTEMIS-boot] ▶ Running both mains for cross-check...\n")

    df_cy <- cy$main()
    df_py <- py$main()

    # Convert to R data frames for comparison
    r_cy <- reticulate::py_to_r(df_cy)
    r_py <- reticulate::py_to_r(df_py)

    identical_check <- isTRUE(all.equal(r_cy, r_py, tolerance = 1e-8))
    cat("[ARTEMIS-boot] ✅ Output consistency between Cython and Python:", identical_check, "\n")
  }

}
