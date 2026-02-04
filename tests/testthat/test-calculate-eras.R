
test_that("calculate_eras works for a single patient", {

    pa <- data.frame(
            personID = "P1",
            component = c("A", "B", "C"),
            t_start = c(0, 100, 200),
            t_end   = c(120, 150, 250),
            adjustedS = c(1, 1, 1),
            timeToEOD = c(300, 200, 100),
            DrugRecord_full = "A;B;C"
            )

    res <- data.frame(
            component = c("A", "C"),
            eras = c(1, 2),
            personID = c("P1", "P1"),
            DrugRecord_full = c("a;b;c", "a;b;c"),
            adjustedS = c(1, 1),
            t_start = c(0, 200),
            t_end = c(120, 250),
            timToEod = c(300, 100),
            regLength = c(120, 50),
            timeToNextRegimen = c(NA, NA),
            First_Line = c(1, 0),
            Second_Line = c(0, 1),
            Other = c(0, 0)
        )

    pa_eras <- calculateEras(pa, discontinuationTime = 120)

    expect_equal(pa_eras$t_start, res$t_start)
    expect_equal(pa_eras$t_end, res$t_end)
    expect_equal(pa_eras$component, res$component)
    expect_equal(pa_eras$adjustedS, res$adjustedS)
})
