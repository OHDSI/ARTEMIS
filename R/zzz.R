.onLoad <- function(libname, pkgname) {
  so_files <- list.files(system.file("cython/TSW_Package", package = "ARTEMIS"), pattern = "\\.so$")

  if (length(so_files)) {
      print("Using Cython version of the alignment algorithm.")
      py_functions = reticulate::import_from_path("main", path = system.file("cython", package = "ARTEMIS"))
      assign("align_patients_regimens", py_functions$align_patients_regimens, envir = parent.env(environment()))
  
      # Optional: message to confirm
      packageStartupMessage("Cython function align_patients_regimens loaded successfully")

  } else {
      print("Using Python version of the alignment algorithm.")
      py_functions = reticulate::import_from_path("main", path = system.file("python", package = "ARTEMIS"))
      assign("align_patients_regimens", py_functions$align_patients_regimens, envir = parent.env(environment()))
  
      # Optional: message to confirm
      packageStartupMessage("Python function align_patients_regimens loaded successfully")
  }

}
