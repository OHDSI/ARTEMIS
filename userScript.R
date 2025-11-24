# Example script that walks through running ARTEMIS, 
# using the package’s included dummy database as input

# If you are using a custom Python environment, 
# specify the full path to the desired Python executable:
# Sys.setenv(RETICULATE_PYTHON = "/full/path/to/python3")
library(ARTEMIS)

##### Prepare input #####
# Example: create connection details for a Redshift database using DatabaseConnector
# connectionDetails <- DatabaseConnector::createConnectionDetails(
#     dbms = "redshift",
#     server = "server/database",
#     user = "username",
#     port = "9999",
#     password = "password",
#     pathToDriver = "./JBDC"
# )

# Load SQLite test database within the package
db_path <- system.file("extdata", "testing_db.sqlite", package = "ARTEMIS")

connectionDetails <- DatabaseConnector::createConnectionDetails(dbms = "sqlite", server = db_path)


df_json <- loadCohort()
name <- "lungcancer"

validdrugs <- loadDrugs()
regimens <- loadRegimens(condition = "all")
regGroups <- loadGroups()

cdmSchema <- "main"
writeSchema <- "main"

##### Fetch data #####
con_df <- getConDF(
    connectionDetails = connectionDetails,
    json = df_json$json[1],
    name = name,
    cdmSchema = cdmSchema,
    writeSchema = writeSchema
)


# Check if the dates are correctly written
con_df$drug_exposure_start_date
# and if not:
con_df$drug_exposure_start_date <- as.POSIXct(con_df$drug_exposure_start_date,
                                              origin = "1970-01-01",
                                              tz = "UTC")

# Prepare a data.frame of patient drug records used in the alignment step
stringDF <- stringDF_from_cdm(con_df = con_df,
                              writeOut = F,
                              validDrugs = validdrugs)

## Alignment

output_all <- stringDF %>%
    generateRawAlignments(
        regimens = regimens,
        g = 0.4,
        Tfac = 0.4,
        method = "PropDiff",
        verbose = 0
    )

## Post-process Alignment

processedAll <- output_all %>%
    processAlignments(regimens = regimens, regimenCombine = 28)

processedEras <- processedAll %>% calculateEras()

# To be decided what to do with generateRegimenStats and writeOutputs
# Regimen stats does not work
# regStats <- processedEras %>% generateRegimenStats()

##### Save all outputs #####
# 
# writeOutputs(
#     output_all,
#     processedAll = processedAll,
#     processedEras = processedEras,
#     connectionDetails = connectionDetails,
#     cdmSchema = cdmSchema,
#     regGroups = regGroups,
#     regStats = regStats,
#     stringDF = stringDF,
#     con_df = con_df
# )
