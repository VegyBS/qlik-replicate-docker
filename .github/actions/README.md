
---

## Custom GitHub Actions

This repository includes three custom composite GitHub Actions that standardise how Qlik Replicate versions are scanned and processed. These actions are used throughout the CI pipeline to ensure consistent behaviour, predictable output formats, and a clean separation of responsibilities.

Each action is documented below.

---

### 1. scan-image

**Location:** `.github/actions/scan-image`
**Purpose:**
Perform a full vulnerability and SBOM scan on a Docker image using Trivy, Grype, and Syft (via Anchore’s SBOM action).

**What it does:**
- Runs a Trivy image scan and outputs JSON
- Runs a Grype image scan and outputs JSON
- Generates a JSON SBOM for the image
- Produces version‑specific output filenames for downstream processing

**Inputs:**

| Name    | Required | Description                                |
|---------|----------|--------------------------------------------|
| image   | Yes      | Docker image reference to scan             |
| version | Yes      | Version identifier used in output filenames |

**Outputs:**
This action does not define explicit outputs, but it generates the following files:

- `image-trivy-<version>.json`
- `image-grype-<version>.json`
- `image-sbom-<version>.json`

**Used by:**
The build-and-scan job to perform image‑level vulnerability scanning.

---

### 2. scan-directories

**Location:** `.github/actions/scan-directories`
**Purpose:**
Perform a full vulnerability and SBOM scan on a filesystem directory using Trivy, Grype, and Syft.

**What it does:**
- Runs a Trivy filesystem scan
- Runs a Grype filesystem scan
- Generates a JSON SBOM for the directory
- Produces version‑specific, prefix‑specific output filenames

**Inputs:**

| Name    | Required | Description                                      |
|---------|----------|--------------------------------------------------|
| version | Yes      | Version identifier used in output filenames      |
| path    | Yes      | Directory to scan                                |
| prefix  | Yes      | Prefix used to distinguish output file groups    |

**Outputs:**
This action does not define explicit outputs, but it generates:

- `<prefix>-trivy-<version>.json`
- `<prefix>-grype-<version>.json`
- `<prefix>-sbom-<version>.json`

**Used by:**
The build-and-scan job to scan the extracted Qlik Replicate install and data directories.

---

### 3. extract-directories

**Location:** `.github/actions/extract-directories`
**Purpose:**
Extract the Qlik Replicate installation directory and data directory from a running container so they can be scanned independently.

**What it does:**
- Creates version‑specific output directories
- Copies the installation directory from the container to the host
- Copies the data directory from the container to the host
- Exposes the resolved output paths as GitHub Action outputs

**Inputs:**

| Name           | Required | Description                                           |
|----------------|----------|-------------------------------------------------------|
| version        | Yes      | Version identifier used to suffix output directories |
| container_name | Yes      | Name of the running container to extract from        |
| install_dir    | Yes      | Path to the installation directory inside container  |
| install_output | Yes      | Host path prefix for extracted installation content  |
| data_dir       | Yes      | Path to the data directory inside container          |
| data_output    | Yes      | Host path prefix for extracted data content          |

**Outputs:**

| Name           | Description                                      |
|----------------|--------------------------------------------------|
| install_output | Full path to the extracted installation directory |
| data_output    | Full path to the extracted data directory         |

**Used by:**
The build-and-scan job immediately after the container is started and verified as healthy.
