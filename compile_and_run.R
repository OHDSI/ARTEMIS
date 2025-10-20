# ============================================================
#  Cross-Platform Installer for ARTEMIS

# ============================================================

# Note to user, see README (update -TODO)
# User exports path to new ARTEMIS_DIR_PATH
# Breaks if not set OR uses a default
# Use exports DEVTOOLS_DIR_PATH need to exists - and OS/architecture dependent setup
# Uses should export PYTHON to use as well
# Used by reticulate and controls versioning
# Fallsback to: python_path <- Sys.which("python")
R_PKG_PATH <- Sys.getenv("ARTEMIS_DIR_PATH")
INSTALL_TOOLS <- Sys.getenv("DEVTOOLS_DIR_PATH")

START_FRESH <- FALSE

# Reinitialize
if (START_FRESH && dir.exists(R_PKG_PATH)) {
  unlink(R_PKG_PATH, recursive = TRUE, force = TRUE)
}
if (!dir.exists(R_PKG_PATH)) {
  dir.create(R_PKG_PATH, recursive = TRUE, showWarnings = FALSE)
}

# Setting R_PKG_PATH first
# this way set R_PKG_PATH as install dir for devtools
.libPaths(c(R_PKG_PATH, INSTALL_TOOLS)) 

os <- Sys.info()[["sysname"]]

cat("📦 Sys name:\n")
print(os)

# system dependencies detection... 
if (os == "Linux") {
  Sys.setenv(
    JAVA_HOME = "/usr/lib/jvm/java-25-openjdk",
    LD_LIBRARY_PATH = paste(
      "/usr/lib",
      "/usr/lib64",
      "/usr/local/lib",
      "/usr/lib/jvm/java-25-openjdk/lib/server",
      sep = ":"
    ),
    PKG_CONFIG_PATH = "/usr/lib/pkgconfig:/usr/share/pkgconfig",
    LDFLAGS = "-L/usr/lib -L/usr/local/lib",
    CPPFLAGS = "-I/usr/include -I/usr/local/include"
  )

} else if (os == "Darwin") {
  Sys.setenv(
    JAVA_HOME = system("/usr/libexec/java_home", intern = TRUE),
    DYLD_FALLBACK_LIBRARY_PATH = "/usr/local/lib:/opt/homebrew/lib",
    PKG_CONFIG_PATH = "/usr/local/lib/pkgconfig:/opt/homebrew/lib/pkgconfig",
    LDFLAGS = "-L/usr/local/lib -L/opt/homebrew/lib",
    CPPFLAGS = "-I/usr/local/include -I/opt/homebrew/include"
  )

} else if (os == "Windows") {
  Sys.setenv(
    JAVA_HOME = "C:/Program Files/Java/jdk-21",
    PATH = paste("C:/rtools43/ucrt64/bin", Sys.getenv("PATH"), sep = ";")
  )
}

if (!requireNamespace("devtools", quietly = TRUE, lib.loc = INSTALL_TOOLS)) {
  stop("devtools not found in ", INSTALL_TOOLS, ". Run setup first.")
}

library(devtools, lib.loc = INSTALL_TOOLS)
#  ============================================================
# Uncomment for local install
# devtools::install(".")

# ============================================================
# Uncomment for GitHub install:
 devtools::install_github("OHDSI/ARTEMIS@ss-wrap/sn-cython2", lib = R_PKG_PATH)
