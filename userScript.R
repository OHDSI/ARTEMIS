# Example script that walks through running ARTEMIS, 
# using the package’s included dummy database as input
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
                              validDrugs = validdrugs)

# check patients
stringDF


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
    processAlignments(regimens = regimens, 
                      regimenCombine = 28)

pa <- processedAll %>% 
    calculateEras()

## Data analysis
## Plot alignments for every patient 

p <- list()
persons <- unique(pa$personID)

for (i in persons) {
    # Select one patient to plot; otherwise, only the first one will be plotted.
    pa_i <- pa[pa$personID == i, ]
    p[[i]] <- plotAlignment(pa_i)
}

# check graphs
p
# or save them in the current working directory
pdf("graph_alignments.pdf", width = 8, height = 4)
p
dev.off()

# Plot score distribution and regimen length distribution
# of the most frequent regimens: 
plotScoreDistribution(pa)
plotRegimenLengthDistribution(pa)

# you could also specify your regimens of interest: 
plotScoreDistribution(pa, components = c("Pembrolizumab monotherapy"))
plotRegimenLengthDistribution(pa, components = c("Pembrolizumab monotherapy"))


# Plot frequency of the top n most frequent regimens: 

plotFrequency(pa, top_n = 10)

# Calculate regimen stats

regStats <- pa %>% 
    generateRegimenStats()

# Check regimen stats
regStats

