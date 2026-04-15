# ARTEMIS Docker Image

This folder contains the Docker setup for the ARTEMIS RStudio image.

## Files

- `Dockerfile`: single multi-architecture Dockerfile (supports `linux/amd64` and `linux/arm64`).

## GitHub Actions publish to Docker Hub

Workflows:

- `.github/workflows/build-rstudio-image-amd64.yml`
- `.github/workflows/build-rstudio-image-arm64.yml`

Trigger: manual (`workflow_dispatch`) on each workflow.

Set these repository secrets:

- `DOCKERHUB_USER`: your Docker Hub username
- `DOCKERHUB_PAT`: Docker Hub personal access token

Optional repository variable:

- `DOCKERHUB_REPO`: target Docker Hub repo name (default: `artemis-rstudio`)

Each workflow builds and pushes architecture-specific tags using plain `docker build`:

- `*-amd64` from the amd64 workflow
- `*-arm64` from the arm64 workflow

## Pull the built image

Replace values as needed:

```bash
docker pull <DOCKERHUB_USER>/<DOCKERHUB_REPO>:latest-amd64
# or
docker pull <DOCKERHUB_USER>/<DOCKERHUB_REPO>:latest-arm64
```

Example:

```bash
docker pull myuser/artemis-rstudio:latest-amd64
```

## Run locally

Open RStudio at [http://127.0.0.1:8787](http://127.0.0.1:8787)

```bash
docker run --rm -p 8787:8787 myuser/artemis-rstudio:latest-amd64
```

Credentials:

- Username: `rstudio`
- Password: `artemis`

Notes:

- The image sets `WORKDIR` to `/home/rstudio/ARTEMIS`.
- This image is intended for development and convenience, not hardened production security.

## Build locally (optional)

Build for current architecture:

```bash
docker build -f docker/Dockerfile -t artemis-rstudio:local .
```

## Offline transfer via USB (tarball workflow)

1. Save image to tarball on online machine:

```bash
docker save -o /path/to/usb/artemis-rstudio-latest-amd64.tar myuser/artemis-rstudio:latest-amd64
```

2. Move USB to offline machine with Docker installed.
3. Load image on offline machine:

```bash
docker load -i /path/to/usb/artemis-rstudio-latest-amd64.tar
```

4. Run on offline machine:

```bash
docker run --rm -p 8787:8787 myuser/artemis-rstudio:latest-amd64
```

Login credentials remain:

- Username: `rstudio`
- Password: `artemis`
