# SWE3 – Homework 4: Docker & CI/CD

This repository contains the implementation of a university assignment focused on **Docker containerization and CI/CD with GitHub Actions**.

## Provided application

The original C# / ASP.NET Core URL Shortener application was provided as the starting project for this assignment. **The application source code is not my own work.** The Dockerfiles, Docker Compose configuration, and GitHub Actions workflow in this repository are the work completed for this exercise.

The application creates and manages short links and redirects requests to their original URLs. Data is persisted in PostgreSQL using Entity Framework Core.

## Assignment requirements

- An intentionally inefficient Dockerfile
- An optimized Dockerfile
- A Docker Compose configuration that starts the URL Shortener and PostgreSQL
- A GitHub Actions pipeline that builds the Docker image and publishes it to GitHub Container Registry (GHCR)

## Repository structure

| File | Purpose |
|---|---|
| `Dockerfile` | Deliberately inefficient single-stage build using the .NET SDK image |
| `Dockerfile.optimized` | Multi-stage build with a smaller ASP.NET runtime image and better layer caching |
| `compose.yaml` | Starts the application and PostgreSQL with a persistent volume and database healthcheck |
| `.github/workflows/docker-publish.yml` | Builds the optimized image and publishes it to GHCR |
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

## GitHub Actions and image publishing

The workflow at `.github/workflows/docker-publish.yml` builds the optimized image. It publishes images to **GitHub Container Registry (GHCR)** when code is pushed to `main` or a version tag (`v*`). Pull requests trigger a build without publishing an image.

The workflow uses the automatically provided `GITHUB_TOKEN` with the `packages: write` permission; no personal access token needs to be stored as a repository secret.

After the first successful publish, the image is available at:

```text
ghcr.io/christoph08/swe3_hw4_docker:latest
```

Depending on package visibility settings, the package may need to be made public in the GitHub Packages settings.

## Original application

The original URL Shortener implementation was supplied as part of the course assignment. This repository focuses on the containerization and CI/CD tasks listed above; it does not claim authorship of the provided application code.
