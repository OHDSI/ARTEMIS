testthat::context("Treatment string builder")

library(testthat)
library(dplyr)
library(tibble)
library(lubridate)

# ------------------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------------------

make_con_df <- function(...) {
  tibble::tibble(...)
}

valid_drugs_tbl <- tibble::tibble(
  valid_concept_id = c(111, 222),
  valid_name = c("CARBO", "PEME")
)

# ------------------------------------------------------------------------------
# A. Smoke & schema
# ------------------------------------------------------------------------------

test_that("stringDF_from_cdm returns expected schema for single patient", {

  con_df <- make_con_df(
    person_id = "1",
    drug_exposure_start_date = as.Date("2025-01-01"),
    drug_concept_id = 111,
    ancestor_concept_id = 111,
    concept_name = "CARBO"
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  expect_s3_class(out, "data.frame")
  expect_true(all(c("person_id", "seq") %in% colnames(out)))
  expect_equal(nrow(out), 1)
  expect_equal(out$person_id, "1")
  expect_equal(out$seq, "0.CARBO;")
})

# ------------------------------------------------------------------------------
# B. Valid drug filtering
# ------------------------------------------------------------------------------

test_that("invalid/supportive drugs are excluded", {

  con_df <- make_con_df(
    person_id = c("1", "1"),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-01")),
    drug_concept_id = c(111, 333),
    ancestor_concept_id = c(111, 333),
    concept_name = c("CARBO", "SUPPORTIVE")
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  expect_equal(out$seq, "0.CARBO;")
  expect_false(grepl("SUPPORTIVE", out$seq))
})

# ------------------------------------------------------------------------------
# C. Same-day combination collapse
# ------------------------------------------------------------------------------

test_that("same-day duplicate drugs collapse to single token", {

  con_df <- make_con_df(
    person_id = c("1", "1"),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-01")),
    drug_concept_id = c(222, 222),
    ancestor_concept_id = c(222, 222),
    concept_name = c("PEME", "PEME")
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  expect_equal(out$seq, "0.PEME;")
})

# ------------------------------------------------------------------------------
# D. Deterministic intra-day ordering
# ------------------------------------------------------------------------------

test_that("same-day drugs are ordered deterministically by concept_name", {

  con_df1 <- make_con_df(
    person_id = c("1", "1"),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-01")),
    drug_concept_id = c(222, 111),
    ancestor_concept_id = c(222, 111),
    concept_name = c("PEME", "CARBO")
  )

  con_df2 <- con_df1[c(2, 1), ]

  out1 <- stringDF_from_cdm(con_df1, valid_drugs_tbl)
  out2 <- stringDF_from_cdm(con_df2, valid_drugs_tbl)

  expect_identical(out1$seq, out2$seq)
  expect_equal(out1$seq, "0.CARBO;0.PEME;")
})

# ------------------------------------------------------------------------------
# E. Consecutive-day lag encoding
# ------------------------------------------------------------------------------

test_that("dayTaken2 encodes inter-day gaps correctly", {

  con_df <- make_con_df(
    person_id = c("1", "1"),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-03")),
    drug_concept_id = c(111, 111),
    ancestor_concept_id = c(111, 111),
    concept_name = c("CARBO", "CARBO")
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  # Day 0, then +2 days
  expect_equal(out$seq, "0.CARBO;2.CARBO;")
})

# ------------------------------------------------------------------------------
# F. Multi-patient batching
# ------------------------------------------------------------------------------

test_that("multiple patients produce independent sequences", {

  con_df <- make_con_df(
    person_id = c("1", "1", "2"),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-02", "2025-02-01")),
    drug_concept_id = c(111, 222, 111),
    ancestor_concept_id = c(111, 222, 111),
    concept_name = c("CARBO", "PEME", "CARBO")
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  expect_equal(nrow(out), 2)
  expect_equal(out$person_id, c("1", "2"))
  expect_equal(out$seq[1], "0.CARBO;1.PEME;")
  expect_equal(out$seq[2], "0.CARBO;")
})

# ------------------------------------------------------------------------------
# G. NA handling
# ------------------------------------------------------------------------------

test_that("rows with NA person_id are retained as separate group", {

  con_df <- make_con_df(
    person_id = c("1", NA),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-01")),
    drug_concept_id = c(111, 111),
    ancestor_concept_id = c(111, 111),
    concept_name = c("CARBO", "CARBO")
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  expect_equal(nrow(out), 2)

  idx_valid <- which(out$person_id == "1")
  idx_na    <- which(is.na(out$person_id))

  expect_equal(length(idx_valid), 1)
  expect_equal(length(idx_na), 1)

  expect_equal(out$seq[idx_valid], "0.CARBO;")
  expect_equal(out$seq[idx_na],    "0.CARBO;")
})

# ------------------------------------------------------------------------------
# H. Token safety (delimiters)
# ------------------------------------------------------------------------------

test_that("concept names are sanitized for delimiters", {

  con_df <- make_con_df(
    person_id = "1",
    drug_exposure_start_date = as.Date("2025-01-01"),
    drug_concept_id = 111,
    ancestor_concept_id = 111,
    concept_name = "CARBO,PLATIN"
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  expect_false(grepl(",", out$seq))
  expect_true(grepl("CARBO_PLATIN", out$seq))
})

# ------------------------------------------------------------------------------
# I. Snapshot (golden)
# ------------------------------------------------------------------------------

test_that("golden snapshot: small cohort", {

  con_df <- make_con_df(
    person_id = c("1", "1", "2"),
    drug_exposure_start_date = as.Date(c("2025-01-01", "2025-01-01", "2025-02-01")),
    drug_concept_id = c(111, 222, 111),
    ancestor_concept_id = c(111, 222, 111),
    concept_name = c("CARBO", "PEME", "CARBO")
  )

  out <- stringDF_from_cdm(con_df, valid_drugs_tbl)

  testthat::expect_snapshot(out)
})
