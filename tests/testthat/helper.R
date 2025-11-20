# Determinism & test env defaults
set.seed(1L)
Sys.setenv(TZ = "UTC")

# Helper: stable arrange (explicit)
stable_arrange <- function(df, ...) {
  # Always include a deterministic tiebreaker if not provided upstream
  dplyr::arrange(df, ..., .by_group = FALSE)
}

# Fixture root
fixture_path <- function(...) {
  file.path("tests", "fixtures", ...)
}