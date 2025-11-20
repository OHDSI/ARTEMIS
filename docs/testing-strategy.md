# Testing Strategy

This project uses `testthat` and `devtools` to test the installed ARTEMIS package — including its R to Python to Cython bridge logic.

### Structure

```
tests/
├── testthat/
│   ├── helper.R # test utilities, env setup
│   ├── test-000-smoke.R # baseline smoke test
│   ├── test-100-bridge.R # bridge output consistency check
...
│   └── testthat.yml # optional (reporter config)
└── testthat.R # testthat entrypoint (required)
```

### Test Workflow

ARTEMIS must be installed and its install location added to .libPaths() before running tests.

    .libPaths(c("/path/to/ARTEMIS", .libPaths()))
    library(devtools)
    library(testthat)
    library(ARTEMIS)

    devtools::test(pkg = "/path/to/ARTEMIS/ARTEMIS")

Where last ARTEMIS refers to the actual package directory
Parent dir might contain other build/test infra

**What Gets Tested** 

* 000-smoke.R

Asserts testthat itself is wired and functional.

* 100-bridge.R

Uses reticulate::import_from_path() to load:

    cython/main.py

    python/main.py

Then checks their return values match using:

    isTRUE(all.equal(r_cy, r_py, tolerance = 1e-8))

### Expected Output

    devtools::test(pkg="/path/to/ARTEMIS")
    ℹ Testing ARTEMIS
    ✔ | F W S OK | Context
    ✔ | 1 | 000-smoke
    Processing patients: 100%|█| 1/1 [00:00<00:00, 1226.76

    ... [bridge output showing processed tables] ...

    Cython module loaded successfully.
    ✔ | 1 | 100-bridge

    ══ Results ═══════════════════════════════════════════
    [ FAIL 0 | WARN 0 | SKIP 0 | PASS 2 ]

    Warning message:
    Objects listed as exports, but not present in
    namespace:
    • calculateEras
    • combineOverlaps
    ...

### Post-Test Cleanup

To fix the NAMESPACE export warning:

    devtools::document()

This will regenerate the NAMESPACE file based on roxygen tags (#' @export) in your R code.

Use `devtools::check()` When:

* You're releasing

* You want full CRAN-style checks

* You want to catch broken docs, missing imports, export issues, etc.

Use `devtools::test()` When:

* You're actively developing

* You want fast, focused feedback

* You're iterating on R or Python bridge logic
