#' Regimens start after the first drug?
#' 
#' This function checks if regimens for each person start after the first drug. 
#' @param pa Processed alignment data with personID and t_start
#' @importFrom dplyr group_by summarise
#' 
regimenStartAfterFirstDrug <- function(pa) {
    pa %>%
        group_by(personID) %>%
        summarise(regimenStartAfterFirstDrug = min(t_start) > 0, .groups = "drop")
 }  


#' Regimens start before the first drug?
#' 
#' This function checks if regimens for each person start after the first drug. 
#' @param pa Processed alignment data with personID and t_start
#' @importFrom dplyr group_by summarise select left_join
#' @importFrom tidyr separate_rows
#' 
regimenStartBeforeFirstDrug <- function(pa, ra) {
    # get the id of the first alignment and check if the regimen started before, 
    # i.e. if regimen_Start > 1  
    ra1 <- ra %>% 
        select(personID, alignmentID, regimen_Start, drugRec_Start)

    pa1 <- pa %>%
        separate_rows(alignmentID) %>% 
        mutate(alignmentID = as.integer(alignmentID)) %>% 
        left_join(ra1, by = c("personID", "alignmentID"))
        
    pa1 %>% 
        group_by(personID, component) %>% 
        arrange(t_start, drugRec_Start, regimen_Start) %>%
        summarise(regimenStartBeforeFirstDrug = first(regimen_Start) > 1)
 }


#' Regimens ends before last drug?
#' 
#' This function checks if regimens end before the last drug for each patient. 
#' @param pa Processed alignment data with personID and t_start
#' @importFrom dplyr group_by slice_max mutate select
#' 
regimenEndsBeforeLastDrug <- function(pa) {
    pa %>% 
        group_by(personID) %>% 
        slice_max(order_by = t_end, n = 1, with_ties = FALSE) %>% 
        mutate(regimenEndsBeforeLastDrug = interval > 0) %>% 
        select(personID, regimenEndsBeforeLastDrug) 
}


#' Consecutive regimens are the same?
#' 
#' This function checks if consecutive regimens are the same for each patient. 
#' @param pa Processed alignment data with personID and t_start
#' @importFrom dplyr group_by arrange summarise full_join lag
#' 
sameConsecutiveRegimens <- function(pa) {
    
    pa %>% 
        group_by(personID) %>% 
        arrange(t_start) %>% 
        summarise(sameConsecutiveRegimens = any(component == lag(component, default = "none")))
}


#' Any uncovered drugs?
#' 
#' This function checks if there are any uncovered drugs for a single patient. 
#' It is a part of nonRegimenDrugExposure function.
#' @param pa Processed alignment data with personID and t_start, and one patient. 
#' @importFrom dplyr group_by summarise
#' 
anyUncoveredDrugs <- function(pa) {
    drugDF <- createDrugDF(patientDrugRecord = pa$CompleteDrugRecord[1])
    
    # break down regimen times into days
    covered <- unique(unlist(
        mapply(seq, pa$t_start, pa$t_end, SIMPLIFY = FALSE)
    ))
    # check if there are any drugs that do not fall within the regimen times
    return(length(setdiff(drugDF$t_start, covered)) > 0)
}


#' Non-Regimen Drug Exposure?
#' 
#' This function checks if there are any uncovered drugs for each patient. 
#' It uses the anyUncoveredDrugs function to check for each patient separately.
#' @param pa Processed alignment data with personID and t_start.
#' @importFrom dplyr group_by summarise
#' 
nonRegimenDrugExposure <- function(pa) {

    pa %>% 
        group_by(personID) %>% 
        summarise(nonRegimenDrugExposure = anyUncoveredDrugs(.data))
}


#' Any Drug Missing In Regimens?
#' 
#' This function checks for each patient if there is a drug missing in regimens. 
#' It uses the anyUncoveredDrugs function to check for each patient separately.
#' @param pa Processed alignment data with personID and t_start.
#' @importFrom dplyr group_by summarise
#' 
anyDrugMissingInRegimens <- function(pa, regimens) {
    regimen_drugs <- regimens$shortString %>% 
        str_split(";") %>% 
        unlist() %>% 
        str_replace("^[^.]*\\.", "") %>%
        unique()

    pa %>% 
        select(personID, CompleteDrugRecord) %>%
        distinct() %>%
        separate_rows(CompleteDrugRecord, sep = ";") %>%
        mutate(drug = str_replace(CompleteDrugRecord, "^[^.]*\\.", "")) %>%   
        group_by(personID) %>% 
        summarise(anyDrugMissingInRegimens = setdiff(drug, regimen_drugs) %>% length() > 0)
}

#' Generate summary report
#'
#' This function generates a summary report for the processed alignment data. 
#' It checks if regimens start after the first drug, 
#' if regimens end before the last drug, 
#' if consecutive regimens are the same, 
#' and if there are any uncovered drugs for each patient.
#' @param pa Processed alignment data with personID and t_start.
#' @importFrom dplyr full_join
#' 
generateSummaryReport <- function(pa, ra, regimens) {
    report <- regimenStartAfterFirstDrug(pa) %>% 
        full_join(regimenEndsBeforeLastDrug(pa), by = "personID") %>% 
        full_join(nonRegimenDrugExposure(pa), by = "personID") %>%
        full_join(sameConsecutiveRegimens(pa), by = "personID") %>% 
        full_join(anyDrugMissingInRegimens(pa, regimens), by = "personID") %>% 
        full_join(regimenStartBeforeFirstDrug(pa, ra), by = "personID")
    
    return(report)
}


