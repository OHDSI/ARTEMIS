<p float="left">

<img src="./img/artemis.png" style="vertical-align: center;" width="100"/>

</p>

## Overview

ARTEMIS provides an interface to a modified Temporal Smith–Waterman (TSW) algorithm, adapted from the approach presented in [10.1109/DSAA.2015.7344785](https://www.researchgate.net/publication/292331949_Temporal_Needleman-Wunsch). This algorithm transforms longitudinal EHR data into discrete regimen eras.
Although applicable to various contexts, ARTEMIS is primarily intended for cancer patients and uses regimen definitions sourced from the [`HemOnc`](https://hemonc.org/wiki/Main_Page) oncology reference.


<figure>
<img src="./img/Workflow_Detailed.png?" alt="ARTEMIS Workflow" />
<figcaption aria-hidden="true">ARTEMIS Workflow</figcaption>
</figure>

### Quick to Docs:
* See [release notes](docs/branch-versioning.md) for versioning and contribution.

## Installation

Before installing ARTEMIS, ensure that **Python (version ≥ 3.12)** is installed on your system.  
You can check which Python version R detects using:

```r
system("python --version", intern = TRUE)
```

If you want ARTEMIS to use a specific Python interpreter, set the `ARTEMIS_PYTHON` environment variable before installation:

```r
Sys.setenv(ARTEMIS_PYTHON = "/path/to/your/python")
```

ARTEMIS can be installed directly from GitHub:

```r
# Install devtools if it is not already installed
if (!requireNamespace("devtools", quietly = TRUE)) {
  install.packages("devtools")
}

# Install ARTEMIS from GitHub
devtools::install_github("OHDSI/ARTEMIS")
```

If you are unsure how to install `Python` or set `ARTEMIS_PYTHON`, refer to the OS-specific setup instructions below.

### On Windows
Install Python 3.12 or above from the Microsoft Store or from:
https://www.python.org/downloads/windows/

Then open cmd or PowerShell and set the environment variable:

    set ARTEMIS_PYTHON=<ABS\\PATH\\TO\\python.exe (v3.12+)>

Other requirements checklist:

* R, Rtools, and devtools installed

* Microsoft Visual C++ 14.0 or greater (required by Python packages like numpy)

* Visual Studio Build Tools (for faster Cython-compiled alignment)

### On Linux or macOS

Install Python 3.12+ using your preferred package manager (e.g., Homebrew, apt, pacman) or download it from: https://www.python.org/

Then from the terminal, set the Python version environment variable:

    export ARTEMIS_PYTHON="/absolute/path/to/python3.12"

Other dependencies you might need installed:

    base-devel, r, git, libgit2, zlib, libxml2, openssl, curl, pkgconf, 
    pandoc, glpk, gmp, libtool, graphviz, make, cmake, tzdata, 
    jdk-openjdk, libcurl-compat, gcc-fortran, openblas, lapack

### Reticulate

💡 You do NOT need to manually set up reticulate — ARTEMIS takes care of it automatically during setup. This section is for informational purposes only.

ARTEMIS relies on a python back-end via
[reticulate](https://rstudio.github.io/reticulate/) and depending on
your reticulate settings, system and environment, you may need to run
the following commands before loading the package:

    reticulate::py_install("numpy")
    reticulate::py_install("pandas")

    **Other python dependencies for the build**
    reticulate::py_install("setuptools")
    reticulate::py_install("wheel")
    reticulate::py_install("Cython")
    reticulate::py_install("tqdm")
    
If you do not presently have reticulate or python3.12 installed you may
first need to run the following commands to ensure that reticulate can
access a valid python install on your system:

    install.packages("reticulate")
    library(reticulate)

This will prompt reticulate to install python, create a local virtualenv
called “r-reticulate” and, finally, set this virtual environment as the
local environment for use when running python via R through reticulate.

## Usage - User Script

A user script is included in this repository,`userScript.R`, to demonstrate how ARTEMIS works. It uses a dummy database to create patients and align them with treatment regimens.

### DatabaseConnector

ARTEMIS also relies on the package
[DatabaseConnector](https://github.com/OHDSI/DatabaseConnector) to
create a connection to your CDM. The process of cohort creation requires
that you have a valid data-containing schema, and a pre-existing schema
where you have write access. This write schema will be used to store
cohort tables during their generation, and may be safely deleted after
running the package.

The specific drivers required by dbConnect may change depending on your
system. More detailed information can be found in the section “DBI
Drivers” at the bottom of this readme.

If the OHDSI package [CirceR](https://github.com/OHDSI/CirceR) is not
already installed on your system, you may need to directly install this
from the OHDSI/CirceR github page, as this is a non-CRAN dependency
required by CDMConnector. You may similarly need to install the
[CohortGenerator](https://github.com/OHDSI/CohortGenerator) package
directly from GitHub.

    #devtools::install_github("OHDSI/CohortGenerator")
    #devtools::install_github("OHDSI/CirceR")

    connectionDetails <- DatabaseConnector::createConnectionDetails(dbms="redshift",
                                                                    server="myServer/serverName",
                                                                    user="user",
                                                                    port = "1337",
                                                                    password="passowrd",
                                                                    pathToDriver = "path/to/JDBC_drivers/")

    cdmSchema <- "schema_containing_data"
    writeSchema <- "schema_with_write_access"

### Input

An input JSON containing a cohort specification is input by the user.
Information on OHDSI cohort creation and best practices can be found
[here](https://ohdsi.github.io/TheBookOfOhdsi/Cohorts.html). An example
cohort selecting for patients with NSCLC is provided with the package.

    df_json <- loadCohort()
    json <- df_json$json[1]
    name <- "examplecohort"

    #Manual
    #json <- CDMConnector::readCohortSet(path = here::here("myCohort/"))
    #name <- "customcohort"

Regimen data may be read in from the provided package, or may be
submitted directly by the user. All of the provided regimens will be
tested against all patients within a given cohort.

    regimens <- loadRegimens(condition = "all")
    regGroups <- loadGroups()

    #Manual
    #regimens <- read.csv("/path/to/my/regimens.csv")

A set of valid drugs may also be read in using the provided data, or may
be curated and submitted by the user. Only valid drugs will appear in
processed patient strings, and thus any drugs not included here will not
effect alignment. Drugs which are frequently taken outside of
chemotherapy regimens, such as antiemetics, should not be added to this
list.

    validDrugs <- loadDrugs()

    #Manual
    #validDrugs <- read.csv(here::here("data/myDrugs.csv"))

### Pipeline

The cdm connection is used to generate a dataframe containing the
relevant patient details for constructing regimen strings.

    con_df <- getConDF(connectionDetails = connectionDetails, 
                       json = json, 
                       name = name, 
                       cdmSchema = cdmSchema, 
                       writeSchema = writeSchema)

Regimen strings are then constructed, collated and filtered into a
stringDF dataframe containing all patients of interest.

    stringDF <- stringDF_from_cdm(con_df = con_df, validDrugs = validdrugs)

The TSW algorithm is then run using user input settings and the provided
regimen and patient data. Detailed information on user inputs, such as
the gap penalty, g, can be found [here](www.github.com/OHDIS/ARTEMIS).

    output_all <- stringDF %>% 
        generateRawAlignments(
            regimens = regimens,
            g = 0.4,
            Tfac = 0.5,
            verbose = 0,
            mem = -1,
            method = "PropDiff"
        )

Raw output alignments are then post-processed.
Post-processing steps include the handling of
overlapping regimen alignments, as well as formatting output for
submission to an episode era table.

    processedAll <- output_all %>% 
            processAlignments(regimenCombine = 28, regimens = regimens)

Treatment trajectories, or regimen eras, can then be calculated, adding
further information about the relative sequencing order of different
regimens and regimen types.

    pa <- processedAll %>% 
            calculateEras(discontinuationTime = 90)


Individual patient regimens can be visualized using `plotAlignment`.

```
p <- plotAlignment(pa)
p
```

<figure>
<img src="./img/alignment_example.png?" alt="ARTEMIS Workflow" />
<figcaption aria-hidden="true">Visualization of Aligned Regimens</figcaption>
</figure>


Data may then be further explored via several graphics which indicate
various information, such as regimen frequency or the score/length
distributions of a given regimen.

    plotFrequency(pa)
    plotScoreDistribution(pa)
    plotRegimenLengthDistribution(pa)

These functions display the most frequent regimens, but additional regimens can also be specified.

    plotScoreDistribution(pa, components = c("Pembrolizumab monotherapy"))
    plotRegimenLengthDistribution(pa, components = c("Pembrolizumab monotherapy"))


Finally, basic statistics is providedy by: 

    regStats <- processedEras %>% g
            enerateRegimenStats()


## Getting help

If you encounter a clear bug, please file an issue with a minimal
[reproducible example](https://reprex.tidyverse.org/) at the [GitHub
issues page](https://github.com/OHDSI/ARTEMIS/issues).
