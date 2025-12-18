test_that("Simple alignment completes without error", {

  regimens <- ARTEMIS::loadRegimens(condition = "all")
  regGroups <- ARTEMIS::loadGroups()
  validDrugs <- ARTEMIS::loadDrugs()

  # Use the first known regimen and repeat it 3 times
  test_seq <- regimens$shortString[1]
  repeated_seq <- paste0(rep(test_seq, 3), collapse = "")

  df <- data.frame(
    person_id = "test",
    seq = repeated_seq,
    stringsAsFactors = FALSE
  )

  # Generate raw alignment
  output_all <- df %>%
    generateRawAlignments(
      regimens = regimens,
      g = 0.4,
      Tfac = 0.4,
      method = "PropDiff",
      verbose = 0
    )

  # Process alignment
  processedAll <- output_all %>%
    processAlignments(
      regimens = regimens,
      regimenCombine = 28
    )

  pa <- processedAll %>%
    calculateEras()

  # Expectation: alignment correctly maps back to the original regimen
  expect_true(
    all(pa$component == regimens$regName[1]),
    info = "Alignment did not return expected original regimen"
  )
})
