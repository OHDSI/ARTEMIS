FROM rocker/rstudio:4.4.3

LABEL org.opencontainers.image.title="ARTEMIS RStudio"
LABEL org.opencontainers.image.description="ARTEMIS development image with RStudio Server, Java, Python 3.12, and JDBC drivers."

ENV DEBIAN_FRONTEND=noninteractive
ENV ARTEMIS_HOME=/home/rstudio/ARTEMIS
ENV DATABASECONNECTOR_JAR_FOLDER=/opt/hades/jdbc_drivers
ENV ARTEMIS_PYTHON=/usr/local/bin/python

RUN mkdir -p "${ARTEMIS_HOME}"

RUN apt-get update && apt-get install -y --no-install-recommends \
    sudo \
    ca-certificates \
    curl \
    git \
    gnupg \
    default-jdk \
    build-essential \
    pandoc \
    python3 \
    python3-dev \
    python3-venv \
    python3-pip \
    libbz2-dev \
    libcurl4-openssl-dev \
    libgit2-dev \
    libssh2-1-dev \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libfribidi-dev \
    libharfbuzz-dev \
    libpng-dev \
    libjpeg-dev \
    libtiff5-dev \
    zlib1g-dev \
  && ln -sf /usr/bin/python3 /usr/local/bin/python \
  && ln -sf /usr/bin/python3 /usr/local/bin/python3 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && R CMD javareconf

RUN python -m pip install --no-cache-dir --break-system-packages \
    numpy \
    pandas==2.3.3 \
    cython \
    tqdm

RUN echo 'options(repos = c(CRAN = "https://cloud.r-project.org"))' >> "${R_HOME}/etc/Rprofile.site"

RUN install2.r --error rJava remotes devtools \
  && rm -rf /tmp/download_packages/ /tmp/*.rds

RUN install2.r --error DatabaseConnector \
  && rm -rf /tmp/download_packages/ /tmp/*.rds

RUN printf '%s\n' \
    "DATABASECONNECTOR_JAR_FOLDER=${DATABASECONNECTOR_JAR_FOLDER}" \
    >> /usr/local/lib/R/etc/Renviron \
  && mkdir -p "${DATABASECONNECTOR_JAR_FOLDER}" \
  && R -e "DatabaseConnector::downloadJdbcDrivers('all')"

COPY --chown=rstudio:rstudio DESCRIPTION ${ARTEMIS_HOME}/DESCRIPTION

RUN R -e "remotes::install_deps('${ARTEMIS_HOME}', dependencies = c('Depends', 'Imports'), upgrade = 'never')"

COPY --chown=rstudio:rstudio . ${ARTEMIS_HOME}

RUN R -e "devtools::install('${ARTEMIS_HOME}', dependencies = FALSE, upgrade = 'never')"

RUN HOME=/home/rstudio R -e "webshot::install_phantomjs(force = TRUE)"

RUN chown -R rstudio:rstudio /home/rstudio

RUN R -e "library(ARTEMIS)"

ENV R_HOME=/usr/local/lib/R
ENV LD_LIBRARY_PATH=/usr/local/lib/R/lib

RUN printf '%s\n' "/usr/local/lib/R/lib" > /etc/ld.so.conf.d/r-local.conf \
  && ldconfig

RUN printf '%s\n' \
    "session-default-working-dir=${ARTEMIS_HOME}" \
    >> /etc/rstudio/rsession.conf

RUN install2.r --error CirceR CohortGenerator RSQLite \
  && rm -rf /tmp/download_packages/ /tmp/*.rds

WORKDIR ${ARTEMIS_HOME}

ENV PASSWORD=artemis

EXPOSE 8787

CMD ["/init"]
