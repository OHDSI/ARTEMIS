# ============================================================
#  Cross-Platform Installer for ARTEM

# ============================================================

R_PKG_PATH <- ".Ruserdata-ARTEMIS-fresh"
INSTALL_TOOLS <- ".Ruserdata1"
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

#  ============================================================
# Uncomment for local install
library(devtools, lib.loc = INSTALL_TOOLS)
devtools::install(".")

#  ============================================================
# Uncomment for git install
#  GitHub install for production version:
#  devtools::install_github("OHDSI/ARTEMIS", lib = R_PKG_PATH)
