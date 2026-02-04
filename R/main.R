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

    output = align_patients_regimens(stringDF, regimens, g=g, T=Tfac, s=s, mem=-1, method=method)

    if (nrow(output) == 0) {
        cli::cat_bullet(
            paste("No alignments", sep = ""),
            bullet_col = "yellow",
            bullet = "info"
        )
        return(data.frame())
    }   

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

    if (nrow(rawOutput) == 0) {
        cli::cat_bullet(
            paste("No alignments detected", sep = ""),
            bullet_col = "yellow",
            bullet = "info"
        )
        return(data.frame()) 
    }

    IDs_All <- unique(rawOutput$personID)    
    cli::cat_bullet(
        paste(
            "Performing post-processing of ", length(IDs_All),
            " patients.\n Total alignments: ", dim(rawOutput)[1],
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
