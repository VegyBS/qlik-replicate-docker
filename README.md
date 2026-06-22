
---

# Qlik Replicate — Minimal Amazon Linux 2023 Image with Automated Security Pipeline

This repository provides two major capabilities:

1. A minimal, production‑ready Docker image for running Qlik Replicate 2026.x on Amazon Linux 2023
2. A fully automated CI pipeline that discovers new Replicate versions, builds and tests them, performs vulnerability scanning, generates security reports, and maintains long‑term baselines

The goal is to provide a secure, reproducible, and extensible foundation for running Qlik Replicate in Docker, AWS Fargate, and automated CI environments.

---

## Repository Overview

This project contains:

- A minimal Amazon Linux 2023–based Replicate image
- A unified CI pipeline that:
  - Discovers the latest Replicate versions
  - Builds and tests each version
  - Extracts install and data directories
  - Runs Trivy, Grype, and SBOM scans
  - Generates a security summary
  - Computes daily deltas
  - Updates long‑term baselines
- Custom GitHub Actions for scanning and extraction
- Python tooling for normalisation, classification, and reporting
- A roadmap for endpoint driver support
- Documentation on running locally, with Docker Compose, and on AWS Fargate

This repository is designed for both development and production use.

---

## Why This Image Is Minimal

The image intentionally includes only what Qlik Replicate requires to run:

- Minimal Amazon Linux 2023 base
- No systemd or init system
- No debugging tools or unnecessary utilities
- No bundled endpoint drivers
- Pinned base image digest for reproducibility
- Clean, deterministic build layers

A minimal image is smaller, more secure, faster to deploy, and easier to maintain.
Downstream Dockerfiles can extend this base to add endpoint drivers or custom integrations.

---

## Why Amazon Linux 2023

Qlik’s official example uses CentOS 8, which is end‑of‑life and unpatched.

Amazon Linux 2023 provides:

- Active security patching
- Hardened, minimal base
- Long‑term support
- Modern glibc toolchain
- No systemd by default
- Smaller attack surface
- Strong alignment with AWS Fargate

This makes it the natural choice for production workloads.

---

## Security Posture

This project is designed with security as a first‑class concern:

- Base image pinned by digest
- Minimal dependency footprint
- No legacy CentOS packages
- No unnecessary daemons
- No embedded drivers
- Amazon Linux 2023 continuous CVE patching

Compared to Qlik’s CentOS‑based example, this image has significantly fewer vulnerabilities and is suitable for regulated environments.

---

## Features

- Minimal Amazon Linux 2023 base
- Silent, non‑systemd Replicate installation
- Custom entrypoint that:
  - Creates data directory
  - Sets admin password
  - Imports license if provided
  - Starts Replicate
  - Tails logs and watches for new ones
- Fully compatible with AWS Fargate
- Clean separation of install and data directories
- Designed as a base image for downstream builds
- Future support for AWS Secrets Manager

---

## Build Instructions

Clone the repository:

```
git clone https://github.com/VegyBS/qlik-replicate-docker
cd qlik-replicate-docker
```

Build the image:

```
docker build -t qlik-replicate:latest .
```

Force rebuild of the installer layer:

```
docker build --build-arg CACHE_BUST=$(date +%s) -t qlik-replicate:latest .
```

---

## Running Locally

```
docker run \
  -p 3563:3563 \
  -e ReplicateDataFolder=/data \
  -e ReplicateAdminPassword=admin \
  -e ReplicateRestPort=3563 \
  -e ReplicateLicense="$(base64 -w0 license.txt)" \
  qlik-replicate:latest
```

Open the UI at:

http://localhost:3563

---

## Running with Docker Compose

```
services:
  replicate:
    image: qlik-replicate:latest
    build:
      context: .
      dockerfile: ./qlik-replicate/Dockerfile
    container_name: replicate
    ports:
      - "3562:3562"
    environment:
      ReplicateDataFolder: /replicate/data
      ReplicateAdminPassword: SomeLongPassword1
      ReplicateRestPort: 3562
    volumes:
       - replicate-data:/replicate/data

volumes:
  replicate-data:
```

Start:

```
docker compose up --build
```

Stop:

```
docker compose down
```

Reset data:

```
docker compose down -v
```

---

## Running on AWS Fargate

This image is designed to run as‑is on Fargate.

Recommended configuration:

- Store license in AWS Secrets Manager
- Mount EFS for `/data`
- Pass admin password via environment variables
- Expose the REST port

Future versions will include native Secrets Manager integration.

---

## Environment Variables

- **ReplicateDataFolder** – Path for data and logs
- **ReplicateAdminPassword** – UI password
- **ReplicateRestPort** – REST API/UI port
- **ReplicateLicense** – Optional license (file path or base64 text)

---

## How the Entrypoint Works

The entrypoint:

1. Validates required environment variables
2. Creates the data directory
3. Sets the admin password
4. Imports a license if provided
5. Starts Replicate
6. Tails all existing logs
7. Watches for new logs
8. Keeps the container alive

This makes the container suitable for both development and production.

---

## Differences from Qlik’s Official Example

- Uses Amazon Linux 2023 instead of CentOS 8
- Minimal, container‑native build
- Production‑oriented entrypoint
- Clean data separation
- Designed as a base image
- Suitable for real workloads, not just demos

---

## Roadmap for Endpoint Driver Support

Planned enhancements:

- Optional driver installation
- Modular driver system
- Runtime‑mounted drivers
- Multi‑stage builds
- Automated validation
- Example downstream Dockerfiles
- AWS Secrets Manager integration

---

# Automated CI and Security Pipeline

This repository includes a unified CI pipeline that:

1. Discovers the latest Qlik Replicate versions
2. Builds and tests each version
3. Extracts install and data directories
4. Runs vulnerability scans
5. Generates a security summary
6. Computes daily deltas
7. Updates long‑term baselines

This provides continuous visibility into security posture and drift.

---

## Version Discovery

The pipeline automatically:

- Fetches all tags from `qlik-download/replicate`
- Normalises and sorts versions
- Extracts the latest two version families
- Produces a CI matrix with version and download URL

This ensures new Replicate releases are scanned automatically.

---

## How the CI Pipeline Works

The pipeline consists of three stages:

### 1. Version Discovery
Discovers the latest Replicate versions and generates a build matrix.

### 2. Build, Test, and Scan
For each version:

- Build Docker image
- Start service
- Extract install and data directories
- Run Trivy, Grype, and SBOM scans
- Generate security summary

### 3. Daily Delta Analysis
On scheduled runs:

- Compare latest scan with baseline
- Generate delta report
- Update baseline branch

This provides daily vulnerability drift detection.

---

# Custom GitHub Actions

This repository includes three custom composite actions:

### scan-image
Scans a Docker image with Trivy, Grype, and SBOM.

### scan-directories
Scans a filesystem directory with Trivy, Grype, and SBOM.

### extract-directories
Extracts install and data directories from a running container.

Each action produces consistent JSON output for downstream processing.

---

# Repository Scripts

This repository includes several utility scripts:

- **get-qlik-versions.sh** – Discover latest Replicate versions
- **security-summary.py** – Generate full security summary
- **security-delta.py** – Compute new/resolved vulnerabilities
- **update-action-shas.sh** – Pin GitHub Actions to commit SHAs

These scripts support the CI pipeline and security automation.

---

# Baseline Branch Strategy

The `security-baseline` branch stores long‑term vulnerability baselines.

Daily scheduled runs:

- Download latest scan results
- Compare with baseline
- Generate delta report
- Commit updated baselines

This provides historical tracking and drift detection.

---

# Repository Structure

```
.
├── docker
│   ├── docker-compose.yml
│   └── qlik-replicate
│       ├── Dockerfile
│       └── scripts
├── .github
│   ├── workflows
│   └── actions
├── qlik-docker-example
├── .github/scripts
├── README.md
└── LICENSE
```

---

# Legal and Licensing Boundaries

This repository cannot provide:

- Qlik Replicate binaries
- Qlik licenses
- Proprietary endpoint drivers
- Any mechanism to bypass licensing

You must supply your own valid license.

---

# About the Author

This project is maintained by an engineer with decades of experience in data engineering, ETL/ELT, and Qlik Replicate in containerised environments.

Contributions and improvements are welcome.

---