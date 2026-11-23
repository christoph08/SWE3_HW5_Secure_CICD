# SWE3 – Homework 5: Secure CI/CD

This repository contains the implementation of a university assignment focused on **Docker containerization and a security-focused CI/CD pipeline with GitHub Actions**.

The pipeline builds and publishes a Docker image, scans the source code and image for vulnerabilities, generates a Software Bill of Materials (SBOM), and creates a verifiable attestation for the SBOM.

## Provided application

The original C# / ASP.NET Core URL Shortener application was provided as the starting project for this assignment. **The application source code is not my own work.** The Dockerfiles, Docker Compose configuration, and GitHub Actions workflow in this repository are the work completed for this exercise.

The application creates and manages short links and redirects requests to their original URLs. Data is persisted in PostgreSQL using Entity Framework Core.

## Assignment scope

- An intentionally inefficient Dockerfile and an optimized Dockerfile
- A Docker Compose configuration that starts the URL Shortener and PostgreSQL
- A GitHub Actions pipeline that builds the Docker image and publishes it to GitHub Container Registry (GHCR)
- Source-code and container-image vulnerability scans with Trivy
- Generation and publication of a CycloneDX SBOM
- Creation and verification of an SBOM attestation

## Repository structure

| File | Purpose |
|---|---|
| `Dockerfile` | Deliberately inefficient single-stage build using the .NET SDK image |
| `Dockerfile.optimized` | Multi-stage build with a smaller ASP.NET runtime image and better layer caching |
| `compose.yaml` | Starts the application and PostgreSQL with a persistent volume and database healthcheck |
| `.github/workflows/docker-publish.yml` | Secure CI/CD workflow: scans, builds, publishes, generates the SBOM and attests it |
| `.dockerignore` | Excludes local build output and development files from the Docker build context |

## Run locally with Docker Compose

Requirements: Docker Engine and Docker Compose v2.

1. Optionally create a local environment file:

   ```bash
   cp .env.example .env
   ```

2. Start the services:

   ```bash
   docker compose up --build -d
   ```

3. Open the API documentation:

   - Swagger UI: http://localhost:8080/swagger
   - Health endpoint: http://localhost:8080/healthz

4. Stop the services:

   ```bash
   docker compose down
   ```

PostgreSQL data is stored in the named Docker volume `postgres_data`. To remove the volume as well (this deletes the database data):

```bash
docker compose down -v
```

The application applies its Entity Framework Core migrations on startup and seeds two example links: `/dotnet` and `/docker`.

## Example endpoints

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/links` | Create a short link |
| `GET` | `/api/links` | List all short links |
| `GET` | `/api/links/{code}` | Get a short link |
| `DELETE` | `/api/links/{code}` | Delete a short link |
| `GET` | `/{code}` | Redirect to the original URL |
| `GET` | `/healthz` | Application and database health |

Example: open http://localhost:8080/dotnet to follow the seeded redirect.

## Dockerfile comparison

### Inefficient build

The root `Dockerfile` uses the full .NET SDK image for both building and running the application. It copies the complete source tree before restoring packages, so ordinary source changes can invalidate the restore layer. The final image also contains the SDK and build tooling.

### Optimized build

`Dockerfile.optimized` uses a multi-stage build. The SDK image is used only to restore and publish the application; the final stage uses the smaller ASP.NET runtime image. Project files are copied and restored before the source files, allowing Docker to reuse the NuGet restore layer when only application code changes.

### Measured image size

Both images were built locally on the same machine and compared using `docker images url-shortener`.

| Metric | Inefficient | Optimized | Improvement |
|---|---:|---:|---:|
| Docker disk usage | 1.81 GB | 354 MB | **~80.4% smaller** |
| Image content size | 547 MB | 101 MB | **~81.5% smaller** |

The optimized image uses approximately one fifth of the disk space of the inefficient image. This is mainly because the final stage contains only the ASP.NET runtime and published application, not the full .NET SDK and build tools.

The measured build durations were 186.3 seconds for the inefficient build and 52.4 seconds for the optimized build. These times are **not a controlled performance comparison**, because the optimized build could reuse base-image layers that had already been downloaded during the first build. The image-size comparison is the more meaningful result of this test.

Both Dockerfiles are provided for comparison. Docker Compose and CI use the optimized Dockerfile.

## Secure CI/CD pipeline

The workflow is defined in `.github/workflows/docker-publish.yml`.

### Triggers

The workflow runs on:

- Pushes to the `main` branch
- Pushes of version tags matching `v*`
- Pull requests targeting `main`
- Manual execution using `workflow_dispatch`

Pull requests run the source scan and Docker build, but do not publish an image. The image scan and SBOM attestation run only for events that publish an image.

### Pipeline jobs

The workflow is split into four jobs. Dependencies are configured with `needs`, so a later job only runs after its required jobs have completed successfully.

| Job | Purpose | Implementation |
|---|---|---|
| `source-scan` | Scans the repository filesystem for HIGH and CRITICAL vulnerabilities. The job fails if findings at these severities are detected. | Trivy |
| `build-and-push` | Builds the optimized Docker image and publishes it to GHCR. The resulting image digest is exposed as a job output for the following jobs. | Docker Buildx and Buildx GitHub Actions |
| `image-security` | Scans the published image for HIGH and CRITICAL vulnerabilities and generates a CycloneDX SBOM. The SBOM is uploaded as a workflow artifact and retained for 30 days. | Trivy and GitHub Actions artifacts |
| `attest` | Creates an SBOM attestation for the exact image digest and publishes the attestation to the container registry. | `actions/attest` |

Both Trivy scans use `exit-code: '1'` for HIGH and CRITICAL findings. This makes the scan a pipeline gate: detected findings at the configured severities cause the corresponding job to fail.

### Image publishing

The optimized image is published to **GitHub Container Registry (GHCR)**:

```text
ghcr.io/christoph08/swe3_hw5_secure_cicd:latest
```

The workflow uses the automatically provided `GITHUB_TOKEN` with the required package permissions. No personal access token needs to be stored as a repository secret.

The build job passes the image digest to the security and attestation jobs. Using the digest rather than relying only on a mutable tag ensures that the SBOM and attestation refer to the exact image produced by that workflow run.

### SBOM generation

A Software Bill of Materials (SBOM) is generated from the published Docker image in **CycloneDX** format:

```text
sbom.cyclonedx.json
```

The SBOM lists the software components detected in the image. It is uploaded as a GitHub Actions artifact named `docker-image-sbom` and retained for 30 days.

### SBOM attestation

The workflow uses `actions/attest` to create an attestation for the generated SBOM. The attestation is associated with the image name and the image digest from the build job and is pushed to GHCR.

GitHub Actions uses OIDC to establish the workflow identity. This allows the attestation to be verified against its source repository and workflow without maintaining a long-lived signing key in the repository.

## Verify the SBOM attestation

The attestation can be verified locally with the GitHub CLI. Use a recent version of `gh` that supports the `attestation` command (version 2.50.0 or newer).

1. Check the GitHub CLI version:

   ```bash
   gh --version
   ```

2. Authenticate with GitHub and make sure the account can read the package:

   ```bash
   gh auth login
   gh auth refresh -s read:packages
   ```

3. Log Docker in to GHCR:

   ```bash
   gh auth token | docker login ghcr.io \
     -u "$(gh api user --jq .login)" \
     --password-stdin
   ```

4. Verify the attestation for the published image:

   ```bash
   gh attestation verify \
     oci://ghcr.io/christoph08/swe3_hw5_secure_cicd:latest \
     --repo christoph08/SWE3_HW5_Secure_CICD \
     --predicate-type https://cyclonedx.org/bom
   ```

A successful verification ends with:

```text
✓ Verification succeeded!
```

The verification checks that a matching attestation exists for the image and that its predicate type, source repository, workflow identity, and OIDC issuer satisfy GitHub's verification policy. The output also identifies the repository and workflow that produced the attestation.

## Original application

The original URL Shortener implementation was supplied as part of the course assignment. This repository focuses on the containerization and secure CI/CD tasks listed above; it does not claim authorship of the provided application code.
