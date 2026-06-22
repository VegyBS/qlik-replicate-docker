
---

## How the CI Pipeline Works

This repository uses a unified CI and security‑scanning pipeline designed to automatically discover new Qlik Replicate versions, build and test each version, perform vulnerability scanning, generate security reports, and maintain long‑term vulnerability baselines.

The pipeline is composed of three major stages:

1. Version discovery
2. Build, test, and security scanning
3. Daily delta analysis and baseline maintenance

Each stage is described below.

---

### 1. Version Discovery

Job: `discover-qlik-versions`
Workflow: `.github/workflows/discover-qlik-versions.yml`

Purpose:
Determine which Qlik Replicate versions should be built and scanned.

How it works:
- Calls the GitHub API to fetch all tags from the `qlik-download/replicate` repository
- Normalises and sorts version numbers
- Extracts the latest two version families (for example, 2025.11 and 2025.10)
- Produces a JSON matrix containing:
  - version number
  - download URL for the Linux installer

Output:
A matrix consumed by the next stage of the pipeline.

---

### 2. Build, Test, and Security Scan

Job: `build-and-scan`
Triggered by:
- Pushes to any branch
- Pull requests
- Manual workflow dispatch
- Scheduled nightly run

Purpose:
Build the Docker image for each discovered Qlik Replicate version, run the service, extract relevant directories, and perform vulnerability scanning.

Key steps:

1. **Checkout repository**
   Retrieves the code and workflow scripts.

2. **Determine build parameters**
   Extracts image name, container name, build context, and Dockerfile path from the Compose configuration.

3. **Build Docker image**
   Uses Buildx with caching enabled.
   Injects:
   - REPLICATE_URL
   - REPLICATE_VERSION

4. **Start the service**
   Runs the container via Docker Compose and waits for the Replicate endpoint to become ready.

5. **Extract Qlik directories**
   Copies:
   - `/opt/attunity/replicate` (install directory)
   - `/replicate/data` (runtime data directory)

6. **Vulnerability scanning**
   Runs Trivy and Grype against:
   - The Docker image
   - The install directory
   - The data directory

7. **Artifact upload**
   Stores all scan results for later processing.

8. **Generate security summary**
   Runs `security-summary.py` to produce a structured Markdown report containing:
   - Fixable vulnerabilities
   - Vendor-owned vulnerabilities
   - Likely noise
   - Full deduped findings

9. **Upload summary**
   Stores the security summary as a build artifact.

This stage ensures every version is fully built, tested, scanned, and documented.

---

### 3. Daily Vulnerability Delta Analysis

Job: `deltas`
Triggered only on the scheduled nightly run.

Purpose:
Compare the latest scan results with the long‑term baseline and detect changes in vulnerability posture.

How it works:

1. **Checkout baseline branch**
   Retrieves the `security-baseline` branch, which stores historical scan results.

2. **Download scan artifacts**
   Retrieves the results produced by the `build-and-scan` job.

3. **Run delta engine**
   Executes `security-delta.py` to compute:
   - New vulnerabilities
   - Resolved vulnerabilities

4. **Generate delta summary**
   Produces a Markdown report for each version.

5. **Combine reports**
   Merges the security summary and delta summary into a single combined report.

6. **Update baselines**
   Commits the new scan results back to the `security-baseline` branch.

This stage provides daily visibility into vulnerability drift and maintains a complete historical record.

---

### Summary of Pipeline Flow

1. Discover latest Qlik Replicate versions
2. Build Docker images for each version
3. Start service and extract directories
4. Run vulnerability scans
5. Generate security summary
6. On scheduled runs:
   - Compare against baseline
   - Generate delta report
   - Update baseline branch

This creates a fully automated, reproducible, and auditable security pipeline.