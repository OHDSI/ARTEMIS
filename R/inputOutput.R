#' Generate a con_df dataframe without using CDMConnector
#' @param connectionDetails A set of DatabaseConnector connectiondetails
#' @param json A loaded cohort from loadJSON()
#' @param name A cohort-specific name for written tables
#' @param cdmSchema A schema containing a valid OMOP CDM
#' @param writeSchema A schema where the user has write access
#' @return A con_df dataframe
#' @export
getConDF <- function(connectionDetails, json, name, cdmSchema, writeSchema){

  connection <- DatabaseConnector::connect(connectionDetails = connectionDetails)

  cohortsToCreate <- CohortGenerator::createEmptyCohortDefinitionSet()
  cohortExpression <- CirceR::cohortExpressionFromJson(json$json[[1]])
  cohortSql <- CirceR::buildCohortQuery(cohortExpression, options = CirceR::createGenerateOptions(generateStats = FALSE))
  cohortsToCreate <- rbind(cohortsToCreate, data.frame(cohortId = 1,
                                                       cohortName = name,
                                                       sql = cohortSql,
                                                       stringsAsFactors = FALSE))

  cohortTableNames <- CohortGenerator::getCohortTableNames(cohortTable = name)

  CohortGenerator::createCohortTables(connection = connection,
                                      cohortDatabaseSchema = writeSchema,
                                      cohortTableNames = cohortTableNames)

  cohortsGenerated <- CohortGenerator::generateCohortSet(connection = connection,
                                                         cdmDatabaseSchema = cdmSchema,
                                                         cohortDatabaseSchema = writeSchema,
                                                         cohortTableNames = cohortTableNames,
                                                         cohortDefinitionSet = cohortsToCreate)

  subject_ids <- DatabaseConnector::dbGetQuery(conn = connection,
                                               statement = paste("SELECT subject_id FROM ",writeSchema,".",name,sep=""))
  
  if(nrow(subject_ids) == 0) stop("The target cohort has no subjects")

  sql_template <- "
WITH filtered_drug_exposure AS (
  SELECT drug_exposure.person_id,
         drug_exposure.drug_exposure_start_date,
         drug_exposure.drug_concept_id,
         concept_ancestor.ancestor_concept_id,
         concept.concept_name
  FROM @cdmSchema.drug_exposure
  LEFT JOIN @cdmSchema.concept_ancestor ON drug_exposure.drug_concept_id = concept_ancestor.descendant_concept_id
  LEFT JOIN @cdmSchema.concept ON concept_ancestor.ancestor_concept_id = concept.concept_id
  WHERE drug_exposure.person_id IN @subject_ids
    AND LOWER(concept.concept_class_id) = 'ingredient'
)
SELECT * FROM filtered_drug_exposure;
"

rendered_sql <- SqlRender::render(sql_template, subject_ids = gsub("c","",paste(subject_ids)), cdmSchema = cdmSchema)

con_df <- DatabaseConnector::dbGetQuery(conn = connection,
                                        statement = rendered_sql)

con_df <- as.data.frame(con_df)

return(con_df)

}

#' Generate a set of patient drug record strings from a valid CDM connection and
#' a valid cohort JSON.
#' @param con_df A con_df dataframe returned by getCohortSet()
#' @param writeOut A variable indicating whether to save the set of drug records
#' @param outputName The name for a given written output
#' as a local file
#' @param validDrugs A dataframe containing a set of validDrugs
#' @return A dataframe containing the relevant patients and their drug exposure strings
#' @export
stringDF_from_cdm <- function(con_df, writeOut=TRUE, outputName = "Output", validDrugs) {

  cli::cat_bullet("Filtering dataframe to valid drugs only...",
                  bullet_col = "yellow", bullet = "info")

  con_df <- con_df[con_df$ancestor_concept_id %in% validDrugs$valid_concept_id,]

  cli::cat_bullet("Generating lag times and constructing drug record strings...",
                  bullet_col = "yellow", bullet = "info")

  #Use lubridate to generate lagtimes
  con_df$dayTaken <- difftime(lubridate::ymd(con_df$drug_exposure_start_date),
                              min(lubridate::ymd(con_df$drug_exposure_start_date)), units = "days")

  #Correct lagtimes using dayTaken and start date for each subject ID
  con_df_out <- con_df %>%
    dplyr::with_groups(person_id, dplyr::mutate, dayTaken = .data$dayTaken - min(.data$dayTaken)) %>%
    dplyr::mutate_at(c("dayTaken"), as.numeric) %>%
    dplyr::arrange(.data$person_id,.data$dayTaken,.data$concept_name) %>%
    dplyr::with_groups(person_id, dplyr::mutate,
                       dayTaken2 = .data$dayTaken -
                         dplyr::lag(.data$dayTaken, default = dplyr::first(.data$dayTaken))) %>%
    dplyr::filter(!duplicated(paste(.data$person_id,.data$drug_exposure_start_date,.data$concept_name)))

  con_df_out2 <- con_df_out  %>%
    dplyr::group_by(.data$person_id) %>%
    dplyr::summarise(seq = paste(.data$dayTaken2, ".",.data$concept_name, ";", collapse = "", sep = ""))

  con_df_out2$seq <- gsub(" ","",gsub(",","_",con_df_out2$seq))

  if(writeOut == TRUE){
    outputFile <- here::here()
    write.csv(file = paste(outputFile,"/",outputName,".csv",sep=""), x = con_df_out2, append = FALSE)
  }

  cli::cat_bullet("Complete!",
                  bullet_col = "green", bullet = "tick")

  return(con_df_out2)

}

#' Filter a stringDF dataframe to contain only valid patients
#' @param min Number of valid drugs in a given subject's drug record required to pass
#' the filter
#' @param stringDF A stringDF dataframe
#' @return A filtered dataframe containing the relevant patients and their
#' drug exposure strings
#' @export
filter_stringDF <- function(stringDF,min) {

  stringDF <- stringDF %>%
    dplyr::mutate(Count = stringr::str_count(seq, ";") + 1)

  stringDF <- stringDF[stringDF$Count >= min,]

  return(stringDF)

}

#' Load the default valid drugs dataframe
#' @param absolute Optional. Absolute path to a custom `.rda` file containing the `validdrugs` dataset. If not provided, the function loads from the `ARTEMIS` package.
#' @export
loadDrugs <- function(absolute=NULL) {
   if (!is.null(absolute)) {
    if (!file.exists(absolute)) {
      stop(paste("Error: The specified file", absolute, "was not found."))
    }
    
    temp_env <- new.env()
    load(absolute, envir = temp_env)
    
    # Ensure `validdrugs` exists after loading
    if (!exists("validdrugs", envir = temp_env)) {
      stop("Error: Loaded file does not contain a dataset named 'validdrugs'.")
    }
    
    validdrugs <- temp_env$validdrugs
  } else {
    data("validdrugs", package = "ARTEMIS")
    
    if (!exists("validdrugs")) {
      stop("Error: Failed to load 'validdrugs' from ARTEMIS package.")
    }
  }
  
  return(validdrugs)
}

#' Load regimens for a given condition
#' @param condition A string indicating which regimen set to load
#' @param absolute Path to system regimen to use as reference
#' Presently, the only condition fully mapped are lungCancer and multiple myeloma
#' Edit: all conditions supported matching a name OR providing a mapping, see example
#' @param mapping A named list of user provids condition to maping
#' @export
loadRegimens <- function(condition, absolute = NULL, 
                         mapping = list("lungCancer" = c("Thoraic Oncology", "Thoraic Oncology"),
                                        "multipleMyeloma" = c("Multiple Myeloma"))) {
  
  # Load from absolute path if provided
  if (!is.null(absolute)) {
    if (!file.exists(absolute)) {
      stop(paste("Error: The specified file", absolute, "was not found."))
    }
    
    regimens_env <- new.env()
    load(absolute, envir = regimens_env)
    
    # Ensure `regimens` exists after loading
    if (!exists("regimens", envir = regimens_env)) {
      stop("Error: Loaded file does not contain a dataset named 'regimens'.")
    }
    
    regimens <- regimens_env$regimens
  } else {
    # Load from ARTEMIS package if no absolute path is given
    data("regimens", package = "ARTEMIS")
    
    if (!exists("regimens")) {
      stop("Error: Failed to load 'regimens' from ARTEMIS package.")
    }
  }
  
  # Handle mapping fallback: if condition is missing, use condition itself
  mapped_conditions <- mapping[[condition]]
  if (is.null(mapped_conditions)) {
    mapped_conditions <- condition
  }
  
  # Filter based on metaCondition
  return(regimens[regimens$metaCondition %in% mapped_conditions, ])
}



#' Display a list of valid conditions
#' @export
validConditions <- function(){
  message("Conditions currently implemented:")
  message("lungCancer")
  message("multipleMyeloma")
}

#' Load the default regimen group dataframe
#' @param absolute Optional. Absolute path to a custom `.rda` file containing the `validdrugs` dataset. If not provided, the function loads from the `ARTEMIS` package.
#' @export
loadGroups <- function(absolute=NULL) {
   if (!is.null(absolute)) {
    if (!file.exists(absolute)) {
      stop(paste("Error: The specified file", absolute, "was not found."))
    }
    
    temp_env <- new.env()
    load(absolute, envir = temp_env)
    
    # Ensure `regimengroups` exists after loading
    if (!exists("regimengroups", envir = temp_env)) {
      stop("Error: Loaded file does not contain a dataset named 'regimengroups'.")
    }
    
    regimengroups <- temp_env$regimengroups
  } else {
    data("regimengroups", package = "ARTEMIS")
    
    if (!exists("regimengroups")) {
      stop("Error: Failed to load 'regimengroups' from ARTEMIS package.")
    }
  }
  
  return(regimengroups)
}

#' Load the default regimen group dataframe
#' @export
loadCohort <- function() {
  #data("json", package = "ARTEMIS")
  return(ARTEMIS::json)
}

#' Filter a stringDF dataframe to contain only valid patients
#' @param output_all A dataframe containing raw outputs
#' @param processedAll A dataframe containing processed output regimens
#' @param processedEras A dataframe containing processed regimen eras
#' @param regGroups The desired regimen grouping variables for Sankey construction
#' @param regStats A dataframe containing various summary statistics
#' @param connectionDetails A set of DatabaseConnector connectiondetails
#' @param cdmSchema A schema containing a valid OMOP CDM
#' @param con_df The con dataframe object generated by getCohortSet
#' @param stringDF A stringDF object containing all valid patients (i.e., those who have exposure
#' to at least one valid drug)
#' @param skipSummaryStats A toggle indicating whether or not the user wishes to skip generating additional summary statistics
#' @export
writeOutputs <- function(output_all, processedAll, processedEras, regGroups, regStats, connectionDetails, cdmSchema, con_df, stringDF, skipSummaryStats = FALSE){
  uniqueIDs <- unique(output_all$personID)
  random_ids <- sample(1:10000000, length(uniqueIDs), replace = F) %>% as.character()
  id_dictionary <- cbind(uniqueIDs, random_ids) %>% `colnames<-`(c("personID", "anonymisedID")) %>% as.data.frame()

  output_all_anon <- merge(output_all,id_dictionary)[,-1]
  processedAll_anon <- merge(processedAll,id_dictionary)[,-1]
  output_eras_anon <- merge(processedEras,id_dictionary)[,-1]

  dir.create(file.path(here::here(), "output_data"), showWarnings = FALSE)
  dir.create(file.path(here::here(), "output_stats"), showWarnings = FALSE)
  dir.create(file.path(here::here(), "output_plots"), showWarnings = FALSE)

  cli::cat_bullet("Generating cohort level stats...",
                  bullet_col = "yellow", bullet = "info")

  if(!skipSummaryStats) {
    cohortStats <- generateCohortStats(connectionDetails = connectionDetails, cdmSchema = cdmSchema, con_df = con_df, stringDF = stringDF)
  } else {
    cohortStats <- data.frame(Characters=character(),
                              stringsAsFactors=FALSE)
  }

  cli::cat_bullet("Saving anonymised patient-level data...",
                  bullet_col = "yellow", bullet = "info")

  write.csv(x = output_all_anon, file = here::here("output_data/OutputAll.csv"))
  write.csv(x = processedAll_anon, file = here::here("output_data/OutputProcessed.csv"))
  write.csv(x = output_eras_anon, file = here::here("output_data/OutputEras.csv"))

  cli::cat_bullet("Saving aggregate data...",
                  bullet_col = "yellow", bullet = "info")

  write.csv(x = regStats, file = here::here("output_stats/regstats.csv"))
  write.csv(x = cohortStats, file = here::here("output_stats/CohortStats.csv"))

  cli::cat_bullet("Generating and saving sample plots (This may take a moment)...",
                  bullet_col = "yellow", bullet = "info")

  plotSankey(processedEras, regGroups, saveLocation = "output_plots/", fileName = "Sankey_Network")

  idTest <- unique(output_all_anon$anonymisedID)

  if(length(idTest) > 50){
    plotIDs <- sample(unique(output_all_anon$anonymisedID), size = 50, replace = F)
  } else {
    plotIDs <- idTest
  }

  for(i in c(1:length(plotIDs))){
    temp_output <- output_all_anon[output_all_anon$anonymisedID==plotIDs[i],]
    temp_plot <- plotOutput(temp_output, fontSize = 1.5, regimenCombine = 28) + ggplot2::ggtitle(paste("Test Plot: ",plotIDs[i],sep=""))
    filename <- paste("output_plots/Test_",plotIDs[i],".png",sep="")
    suppressWarnings(
      ggplot2::ggsave(filename, plot = temp_plot, device = "png", height = 7, width = 10)
    )
  }

  zip(zipfile = "output_data.zip", files = "output_data/")
  zip(zipfile = "output_stats.zip", files = "output_stats/")
  zip(zipfile = "output_plots.zip", files = "output_plots/")

  unlink('output_stats/', recursive=TRUE)
  unlink('output_data/', recursive=TRUE)
  unlink('output_plots/', recursive=TRUE)

  cli::cat_bullet("Complete!",
                  bullet_col = "green", bullet = "tick")

}