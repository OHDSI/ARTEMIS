#' Aligns together either a single drug regimen/record, or a list of regimens against a drug record,
#' returning either a set of global alignments or a set of local alignments, either overlapping
#' or otherwise
#'
#' @param regimen A sequence to be aligned, usually a short sequence defining a chemotherapy regimen,
#'                may contain multiple regimens if supplied as a list
#' @param regName The name of the supplied regimen
#' @param drugRec A patient's converted drug occurrence table
#' @param g A gap penalty supplied to the temporal needleman wunsch/smith waterman algorithms
#' @param Tfac The time penalty factor. All time penalties are calculated as a percentage of Tfac
#' @param s A substituion matrix, either user-defined or derived from defaultSmatrix. Will be auto-generated if left blank.
#' @param verbose A variable indicating how verbose the python script should be in reporting results
#'            Verbose = 0 : Print nothing
#'            Verbose = 1 : Print seqs and scores
#'            Verbose = 2 : Report seqs, scores, H and traceMat
#'
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
#' @return dat A dataframe containing information on the resulting alignments
#' output <- align(regimen,drugRec)
#' @export
align <- function(regimen,
                  regName,
                  personID,
                  personSeq,
                  g = 0.4,
                  Tfac = 0.5,
                  s = NA,
                  verbose = 0,
                  mem = -1,
                  removeOverlap = 1,
                  method = "PropDiff") {
    if (!exists("temporal_alignment", mode = "function")) {
        reticulate::source_python(system.file("python/main.py", package = "ARTEMIS"), envir = globalenv())
    }

    regimen_list <- encode(regimen)
    drugRec <- encode(personSeq)

    dat <- data.frame(
        Regimen        = character(),
        DrugRecord     = character(),
        Score          = numeric(),
        adjustedS      = numeric(),
        regimen_Start  = numeric(),
        regimen_End    = numeric(),
        drugRec_Start  = numeric(),
        drugRec_End    = numeric(),
        Aligned_Seq_len = numeric(),
        totAlign       = numeric()
            )
    
    
    if (is.na(s)) {
        s <- defaultSmatrix(regimen, drugRec)
    }
        
    temp_dat <- temporal_alignment(
        regimen_list,
        drugRec,
        g,
        Tfac,
        as.data.frame(s),
        verbose,
        mem,
        removeOverlap,
        method
    )
    temp_dat <- as.data.frame(temp_dat)

    if(nrow(temp_dat) == 0) {
        return(data.frame())
    }
    
    names(temp_dat) <- names(dat)
    
    temp_dat <- temp_dat %>%
        dplyr::mutate(dplyr::across(c(Score, adjustedS, 
                                      regimen_Start, regimen_End, 
                                      drugRec_Start, drugRec_End,
                                      Aligned_Seq_len, totAlign), 
                      as.numeric))
    
    temp_dat$regName <- regName
    temp_dat$Regimen_full <- regimen
    temp_dat$DrugRecord_full <- personSeq
    temp_dat$personID <- as.character(personID)
    
    temp_dat <- temp_dat %>%
        dplyr::filter(!is.na(adjustedS) & !is.na(totAlign)) %>%
        dplyr::filter(totAlign > 0 & adjustedS > 0)

    return(temp_dat)
}
