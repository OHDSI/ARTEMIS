test_that("Cython and Python bridge modules are consistent", {

  # cy_path <-  "cython"
  # py_path <-  "python"
  # CRAN simulated <sandbox>
  cy_path <- system.file("cython", package = "ARTEMIS")
  py_path <- system.file("python", package = "ARTEMIS")

  cy <- reticulate::import_from_path("main", path = cy_path)
  py <- reticulate::import_from_path("main", path = py_path)

  r_cy <- reticulate::py_to_r(cy$main())
  r_py <- reticulate::py_to_r(py$main())

  expect_true(
    isTRUE(all.equal(r_cy, r_py, tolerance = 1e-8)),
    info = "Output mismatch between cython and python main()"
  )
})