
test_that("processAlignments", {

    
    s <- data.frame(seq = "7.carboplatin;0.paclitaxel;7.carboplatin;0.paclitaxel;7.carboplatin;0.paclitaxel;", 
                    person_id = "P1"
                  )


    ra <- generateRawAlignments(
        s,
        regimens = regimens,
        g = 0.4,
        Tfac = 0.5,
        verbose = 0,
        mem = -1,
        method = "PropDiff"
    )

    pa <- processAlignments(ra,regimenCombine = 120)

    res <- data.frame(
            component = c("Carboplatin and Paclitaxel (CP)"),
            personID = c("P1"),
            adjustedS = c(0.8866951),
            t_start = c(0),
            t_end = c(14)
        )


    expect_equal(pa$t_start, res$t_start)
    expect_equal(pa$t_end, res$t_end)
    expect_equal(pa$component, res$component)
    expect_equal(round(pa$adjustedS, 2), round(res$adjustedS, 2))
})
