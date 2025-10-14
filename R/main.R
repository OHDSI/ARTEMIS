#' Generate Alignments
#' 
#' Generate processed alignments of treatment regimens using temporal 
#' Needleman–Wunsch or Smith–Waterman algorithms. 
#' The input regimens are aligned against patient drug records from stringDF data.frame.
#' @param stringDF A dataframe that contains patient IDs and seq columns. 
#' Each seq should be a valid encoded drug record. Check example below.
#' @examples
#' stringDF <- data.frame(
#'   person_id = c("P1", "P2"),
#'   seq = c("7.cisplatin;0.etoposide;1.etoposide;1.etoposide;",
#'           "0.paclitaxel;1.carboplatin;")
#' )
#' 
#' @param regimens A regimen dataframe, containing required regimen shortStrings
#' for testing
#' @param g A gap penalty supplied to the temporal Needleman-Wunsch/Smith–Waterman algorithm
#' @param Tfac The time penalty factor. All time penalties are calculated as a percentage of Tfac
#' @param s A substituion matrix, either user-defined or derived from defaultSmatrix.
#' Will be auto-generated if left blank.
#' @param verbose A variable indicating how verbose the python script should be in reporting results
#'            Verbose = 0 : Print nothing
#'            Verbose = 1 : Print seqs and scores
#'            Verbose = 2 : Report seqs, scores, H and traceMat
#' @param mem A number defining how many sequences to hold in memory during local alignment.
#'            Mem = -1 : Script will define memory length according to floor(len(regimen)/len(drugRec))
#'            Mem = 0 : Script will return exactly 1 alignment
#'            Mem = 1 : Script will return 1 alignment and all alignments with the same score
#'            Mem = X : Script will return X alignments and all alignments with equivalent score as the Xth alignment
#' @param removeOverlap A variable indicating whether to remove overlaps (1) or leave them in the output data (0)
#' @param method A character string indicating which loss function method to utilise. Please pick one of
#'            PropDiff        - Proportional difference of Tx and Ty
#'            AbsDiff         - Absolute difference of Tx and Ty
#'            Quadratic       - Absolute difference of Tx and Ty to the power 2
#'            PropQuadratic   - Absolute difference of Tx and Ty to the power 2, divided by the max of Tx and Ty
#'            LogCosh         - The natural logarithm of the Cosh of the absolute difference of Tx and Ty
#'
#' @param writeOut A variable indicating whether to save the set of drug records
#' @param outputName The name for a given written output
#' @return A data.frame containing regimen alignment results mapped onto patient records.
#' @export
generateRawAlignments <- function(stringDF,
                                  regimens,
                                  g,
                                  Tfac,
                                  s = NULL,
                                  verbose = 0,
                                  mem = -1,
                                  removeOverlap = -1,
                                  method = "PropDiff") {
    # Input check: stop if stringDF is not a data.frame or has no rows                                
    obj_name <- deparse(substitute(stringDF))
    if (!is.data.frame(stringDF)) {
        stop(paste0("Error: ", obj_name, " must be a data.frame object,",
            "\nwith patients records and ", 
            "person_id and seq columns."))
    }
    if (nrow(stringDF) == 0) { 
        stop(paste0("Error: ", obj_name, 
                    " is empty. No patient records found."))
    }
    if (!exists("align_patients_regimens", mode = "function")) {
        py_functions = reticulate::import_from_path("main", path = system.file("python", package = "ARTEMIS"))
        align_patients_regimens = py_functions$align_patients_regimens
    }

    output = align_patients_regimens(stringDF, regimens, g=g, T=Tfac, s=s, mem=-1, removeOverlap=1, method="PropDiff")

    output <- output %>%
        dplyr::mutate(dplyr::across(c(Score, adjustedS, 
                                      regimen_Start, regimen_End, 
                                      drugRec_Start, drugRec_End,
                                      Aligned_Seq_len, totAlign), 
                                    as.numeric))
    
    output <- output %>%
        dplyr::filter(!is.na(adjustedS) & !is.na(totAlign)) %>%
        dplyr::filter(totAlign > 0 & adjustedS > 0)
    
    return(output)
}




#' Perform post-processing on a data frame of raw alignment results
#' @param rawOutput An output dataframe produced by generateRawAlignments()
#' @param regimenCombine The numeric value of days allowed between regimens of the same
#' name before they are collapsed/summarised into a single regimen
#' @param regimens The set of input regimens used to generate alignments, from which cycle lengths may be derived
#' @param writeOut A variable indicating whether to save the set of drug records
#' @param outputName The name for a given written output
#' @return A dataframe processed alignments
#' @export
processAlignments <- function(rawOutput,
                              regimenCombine,
                              regimens = "none") {
    IDs_All <- unique(rawOutput$personID)    
    cli::cat_bullet(
        paste(
            "Performing post-processing of ",
            length(IDs_All),
            " patients.\n Total alignments: ",
            dim(rawOutput)[1],
            sep = ""
        ),
        bullet_col = "yellow",
        bullet = "info"
    )
    
    # Postprocess each patient individually
    processedAll <- data.frame()

    for (i in c(1:length(IDs_All))) {
        newOutput <- rawOutput[rawOutput$personID == IDs_All[i], ]
        
        processed <- postprocessDF(newOutput, regimenCombine = regimenCombine)
        processedAll <- dplyr::bind_rows(processedAll, processed)   
        
        progress(x = i, max = length(IDs_All))
    }
        
    if (!is(regimens, "data.frame")) {
        cli::cat_bullet(
            paste("Adding regimen cycle length data...", sep = ""),
            bullet_col = "yellow",
            bullet = "info"
        )
        
        regTemp <- regimens[, c("regName", "cycleLength")]
        colnames(regTemp)[1] <- "component"
        
        processedAll <- merge(processedAll, regTemp, by = "component")
        processedAll <- processedAll[order(processedAll$cycleLength, decreasing = TRUE), ]
        processedAll <- processedAll[!duplicated(processedAll[, !colnames(processedAll) %in% c("cycleLength")]), ]
    } else {
        cli::cat_bullet(
            paste("Regimen cycle length data not detected as input...", sep = ""),
            bullet_col = "yellow",
            bullet = "info"
        )
    }
    
    cli::cat_bullet("Complete!",
                    bullet_col = "green",
                    bullet = "tick")
    
    return(processedAll)
    
}

#' Adds first/second/other era data to a processed regimen alignment ouput
#' @param processedAll A dataframe processed alignments, generated by processAlignments()
#' @param discontinuationTime The number of days to use to indicate treatment discontinuation
#' @return A processed alignment dataframe with added era data relating to first/second/other sequencing
#' @export
calculateEras <- function(processedAll, discontinuationTime = 120) {
    IDs_All <- unique(processedAll$personID)
    processedEras <- processedAll[0, ]
    
    result_list <- vector("list", length(IDs_All))  # Preallocate list
    
    for (i in c(1:length(IDs_All))) {
        tempDF <- processedAll[processedAll$personID == IDs_All[i], ]
        
        tempDF <- tempDF[order(tempDF$t_start), ]
        toRemove <- c()
        
        if (nrow(tempDF) > 1) {
            for (ic in c(2:length(tempDF$component))) {
                if (tempDF[ic, ]$t_start < tempDF[ic - 1, ]$t_end) {
                    toRemove <- c(toRemove, ic)
                }
            }
        }
        
        if (length(toRemove) > 0) {
            tempDF <- tempDF[-toRemove, ]
        }
        
        tempDF <- tempDF %>%
            dplyr::mutate(timeToNextRegimen = dplyr::lead(t_start) - t_end)
        
        tempDF <- tempDF %>%
            dplyr::mutate(
                lag = dplyr::lag(.data$timeToNextRegimen),
                delete = ifelse((
                    dplyr::lag(.data$timeToNextRegimen) < discontinuationTime &
                        component == dplyr::lag(component)
                ),
                "Y",
                "N"
                )
            )
        
        tempDF[1, ]$delete <- "N"
        tempDF1 <- tempDF %>%
            mutate(newLine = cumsum(delete == "N")) %>%
            summarise(
                adjustedS = sum(adjustedS * (t_end - t_start) / sum(t_end - t_start)),
                t_start = min(t_start),
                t_end = max(t_end),
                timToEod = min(timeToEOD),
                .by = c(component, newLine, personID)
            ) %>%
            mutate(
                regLength = t_end - t_start,
                timeToNextRegimen = lag(t_start, 1) - t_end,
                First_Line = 1 * (row_number() == 1),
                Second_Line = 1 * (row_number() == 2),
                Other = 1 * (row_number() > 2)
            )
        
        tempDF$timeToNextRegimen[tempDF$timeToNextRegimen < 0] <- 0
        
        result_list[[i]] <- tempDF
        
    }
    
    processedEras <- dplyr::bind_rows(result_list)
    
    return(processedEras)
    
}

#' Generates a data frame containing summary stats from processed regimen data
#' @param processedEras A dataframe processed alignments, generated by processAlignments()
#' @return A data frame containing summary stats from processed regimen data
#' @export
generateRegimenStats <- function(processedEras) {
    processedEras$t_total <- (processedEras$t_end - processedEras$t_start) +
        1
    
    meanScores <- aggregate(adjustedS ~ component, processedEras, mean)
    medianScores <- aggregate(adjustedS ~ component, processedEras, median)
    rangeScores <- aggregate(adjustedS ~ component, processedEras, range)
    rangeScores$rangeScores <- paste("(", rangeScores[, 2][, 1], "-", rangeScores[, 2][, 2], ")", sep =
                                         "")
    rangeScores <- rangeScores[, c(1, 3)]
    colnames(rangeScores) <- c("component", "rangeScores")
    
    meanTimes <- aggregate(t_total ~ component, processedEras, mean)
    medianTimes <- aggregate(t_total ~ component, processedEras, median)
    rangeTimes <- aggregate(t_total ~ component, processedEras, range)
    rangeTimes$rangeTimes <- paste("(", rangeTimes[, 2][, 1], "-", rangeTimes[, 2][, 2], ")", sep =
                                       "")
    rangeTimes <- rangeTimes[, c(1, 3)]
    colnames(rangeTimes) <- c("component", "rangeTimes")
    
    firstLikelihood <- aggregate(First_Line ~ component, processedEras, mean)
    secondLikelihood <- aggregate(Second_Line ~ component, processedEras, mean)
    otherLikelihood <- aggregate(Other ~ component, processedEras, mean)
    
    count <- as.data.frame(table(processedEras$component))
    frequency <- as.data.frame(table(processedEras$component) / sum(table(processedEras$component)))
    colnames(count) <- c("component", "count")
    colnames(frequency) <- c("component", "frequency")
    
    dim(merge(meanScores, medianScores))
    
    aggregated_Processed_Data <- merge(merge(merge(
        merge(
            merge(
                merge(
                    merge(merge(
                        merge(
                            merge(meanScores, medianScores, by = "component"),
                            rangeScores,
                            by = "component"
                        ), meanTimes, by = "component"
                    ), medianTimes, by = "component"),
                    rangeTimes,
                    by = "component"
                ),
                firstLikelihood,
                by = "component"
            ),
            secondLikelihood,
            by = "component"
        ),
        otherLikelihood,
        by = "component"
    ), count, by = "component"), frequency, by = "component")
    colnames(aggregated_Processed_Data) <- c(
        "regName",
        "Mean Score",
        "Median Score",
        "Score Range",
        "Mean Length of Treatment",
        "Median Length of Treatment",
        "Length of Treatment Range",
        "First Era Likelihood",
        "Second Era Likelihood",
        "Other Era Likelihood",
        "Count",
        "Frequency"
    )
    return(aggregated_Processed_Data)
}

#' A function to conveniently generate several stats relating to the input cohort
#' @param connectionDetails A set of DatabaseConnector connectiondetails
#' @param cdmSchema A schema containing a valid OMOP CDM
#' @param stringDF A stringDF object containing all valid patients (i.e., those who have exposure
#' to at least one valid drug)
#' @param con_df A con_df dataframe
#' @return A dataframe containing various summary statistics regarding the age of treated
#' and untreated patients
#' @export
generateCohortStats <- function(connectionDetails,
                                cdmSchema,
                                con_df,
                                stringDF) {
    connection <- DatabaseConnector::connect(connectionDetails = connectionDetails)
    
    subjects <- unique(con_df$person_id)
    
    con_df_filtered <- con_df[!con_df$person_id %in% stringDF$person_id, ]
    subjects_filtered <- unique(con_df_filtered$person_id)
    subjects_unfiltered <- subjects[!subjects %in% subjects_filtered]
    
    person <- dplyr::tbl(connection,
                         DatabaseConnector::inDatabaseSchema(cdmSchema, "person"))
    
    con_patientTable <- person %>%
        dplyr::filter(.data$person_id %in% subjects) %>%
        dplyr::select(.data$person_id,
                      .data$year_of_birth,
                      .data$gender_concept_id) %>%
        as.data.frame()
    
    con_patientTable$gender <- ifelse(con_patientTable$gender_concept_id ==
                                          "8532", "F", "M")
    con_patientTable$age <- 2022 - as.numeric(as.character(con_patientTable$year_of_birth))
    
    unTreated <- con_patientTable %>%
        dplyr::filter(.data$person_id %in% subjects_filtered) %>%
        dplyr::select(.data$person_id, .data$age, .data$gender)
    
    uQuants_m <- quantile(unTreated[unTreated$gender == "M", ]$age)[c(2, 3, 4)]
    uQuants_f <- quantile(unTreated[unTreated$gender == "F", ]$age)[c(2, 3, 4)]
    uQuants_t <- quantile(unTreated$age)[c(2, 3, 4)]
    
    treated <- con_patientTable %>%
        dplyr::filter(.data$person_id %in% subjects_unfiltered) %>%
        dplyr::select(.data$person_id, .data$age, .data$gender)
    
    tQuants_m <- quantile(treated[treated$gender == "M", ]$age)[c(2, 3, 4)]
    tQuants_f <- quantile(treated[treated$gender == "F", ]$age)[c(2, 3, 4)]
    tQuants_t <- quantile(treated$age)[c(2, 3, 4)]
    
    quantiles <- as.data.frame(rbind(uQuants_t, rbind(tQuants_t, rbind(
        tQuants_m, rbind(tQuants_f, rbind(uQuants_m, uQuants_f))
    ))))
    quantiles$Category <- c("Untreated",
                            "Treated",
                            "Treated",
                            "Treated",
                            "Untreated",
                            "Untreated")
    quantiles$Gender <- c("Total", "Total", "M", "F", "M", "F")
    
    colnames(quantiles) <- c(
        "25th Percentile (AGE)",
        "Median (AGE)",
        "75th Percentile (AGE)",
        "Category",
        "Gender"
    )
    
    quantiles <- reshape2::melt(quantiles)
    quantiles$variable <- as.character(quantiles$variable)
    quantiles <- rbind(quantiles, c("Untreated", "Total", "No. of Patients", dim(unTreated)[1]))
    quantiles <- rbind(quantiles, c("Treated", "Total", "No. of Patients", dim(treated)[1]))
    quantiles <- rbind(quantiles, c("Treated", "M", "No. of Patients", dim(treated[treated$gender ==
                                                                                       "M", ])[1]))
    quantiles <- rbind(quantiles, c("Treated", "F", "No. of Patients", dim(treated[treated$gender ==
                                                                                       "F", ])[1]))
    quantiles <- rbind(quantiles, c("Untreated", "M", "No. of Patients", dim(unTreated[unTreated$gender ==
                                                                                           "M", ])[1]))
    quantiles <- rbind(quantiles, c("Untreated", "F", "No. of Patients", dim(unTreated[unTreated$gender ==
                                                                                           "F", ])[1]))
    
    output_df <- reshape2::acast(quantiles, variable ~ Gender + Category, value.var = "value")
    
    drug_exposure <- dplyr::tbl(connection,
                                DatabaseConnector::inDatabaseSchema(cdmSchema, "drug_exposure"))
    concept_ancestor <- dplyr::tbl(
        connection,
        DatabaseConnector::inDatabaseSchema(cdmSchema, "concept_ancestor")
    )
    concept <- dplyr::tbl(connection,
                          DatabaseConnector::inDatabaseSchema(cdmSchema, "concept"))
    
    con <- drug_exposure %>%
        dplyr::filter(.data$person_id %in% subjects_filtered) %>%
        dplyr::select(c("person_id", "drug_concept_id")) %>%
        dplyr::distinct() %>%
        dplyr::left_join(concept_ancestor,
                         by = c("drug_concept_id" = "descendant_concept_id")) %>%
        dplyr::left_join(concept, by = c("ancestor_concept_id" = "concept_id")) %>%
        dplyr::filter(tolower(.data$concept_class_id) == "atc 1st")
    
    con_df_temp <- as.data.frame(con)
    
    con_df_m <- con_df_temp %>%
        dplyr::filter(.data$person_id %in% unTreated[unTreated$gender == "M", ]$person_id)
    
    con_df_f <- con_df_temp %>%
        dplyr::filter(.data$person_id %in% unTreated[unTreated$gender == "F", ]$person_id)
    
    m_df <- as.data.frame(table(con_df_m$concept_name) / sum(table(con_df_m$concept_name)))
    f_df <- as.data.frame(table(con_df_f$concept_name) / sum(table(con_df_f$concept_name)))
    t_df <- as.data.frame(table(con_df_temp$concept_name) / sum(table(con_df_temp$concept_name)))
    
    m_df$Category <- "Untreated"
    m_df$Gender <- "M"
    f_df$Category <- "Untreated"
    f_df$Gender <- "F"
    t_df$Category <- "Untreated"
    t_df$Gender <- "Total"
    
    colnames(m_df)[c(1, 2)] <- c("variable", "value")
    colnames(f_df)[c(1, 2)] <- c("variable", "value")
    colnames(t_df)[c(1, 2)] <- c("variable", "value")
    
    atc_output <- as.data.frame(reshape2::acast(rbind(t_df, rbind(m_df, f_df)), variable ~
                                                    Gender + Category, value.var = "value"))
    atc_output$M_Treated <- ""
    atc_output$F_Treated <- ""
    atc_output$Total_Treated <- ""
    atc_output <- atc_output[, c(5, 1, 4, 2, 6, 3)]
    
    output <- rbind(output_df, atc_output)
    
    output[c(5:18), ]$F_Untreated <- as.character(format(round(
        100 * as.numeric(output[c(5:18), ]$F_Untreated), 2
    ), nsmall = 2))
    output[c(5:18), ]$M_Untreated <- as.character(format(round(
        100 * as.numeric(output[c(5:18), ]$M_Untreated), 2
    ), nsmall = 2))
    output[c(5:18), ]$Total_Untreated <- as.character(format(round(
        100 * as.numeric(output[c(5:18), ]$Total_Untreated), 2
    ), nsmall = 2))
    
    return(output)
    
}
