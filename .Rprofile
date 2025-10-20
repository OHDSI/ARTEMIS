
### ===========================================
###              USER CONFIG
### ===========================================

# User should set the evn variables like this:
### ===========================================
# export ARTEMIS_PY_VERSION="PATH/TO/PY/BIN"        # Versions condition 3.12+ 
# export DEVTOOLS_DIR_PATH="PATH/TO/R-DEVTOOLS"     # Custom build requirements directory 
# export ARTEMIS_DIR_PATH="ARTEMIS-build"           # default  
# (optionally) export TEST_ARTEMIS_BUILD=TRUE/FALSE
# See  readme how to run one-shot test

### ==============================================



# ----------- SET ENV VARS -----------

# enables cmd overrides
if (Sys.getenv("TEST_ARTEMIS_BUILD", unset = "") == "") {
  Sys.setenv(TEST_ARTEMIS_BUILD = "FALSE")
}

# Resolve paths from ENV or use fallback
ARTEMIS_DIR_PATH <- Sys.getenv("ARTEMIS_DIR_PATH", unset = "./ARTEMIS") # default
DEVTOOLS_DIR_PATH <- Sys.getenv("DEVTOOLS_DIR_PATH", unset = ".Ruserdata1")
ARTEMIS_PY_VERSION <- Sys.getenv("ARTEMIS_PY_VERSION", unset = Sys.which("python"))

.libPaths(c(
normalizePath(ARTEMIS_DIR_PATH, mustWork = FALSE),
normalizePath(DEVTOOLS_DIR_PATH, mustWork = FALSE),
.libPaths()
))
message("[ARTEMIS-env-setup] Custom lib path set via .Rprofile")
