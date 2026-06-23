
---

## Repository Scripts

This repository includes several utility scripts that support the CI/CD and security‑scanning workflow. Each script is designed to be small, focused, and easy to maintain. The following sections describe what each script does and how it fits into the overall pipeline.

### 1. get-qlik-versions.sh

Purpose:
Discovers the latest Qlik Replicate release families and outputs the Linux installer tarball URLs for those versions.

How it works:
- Fetches all tags from the qlik-download/replicate GitHub repository
- Normalises and sorts version numbers
- Extracts the latest two version families (for example, 2025.11 and 2025.10)
- Lists only Linux installer .tar.gz assets for each version

Used by:
The discover-qlik-versions workflow to dynamically build the CI matrix.

---

### 2. security-delta.py

Purpose:
Compares the latest vulnerability scan results with the stored baseline and generates a delta report showing new and resolved vulnerabilities.

How it works:
- Loads all Trivy and Grype JSON files from the current scan
- Loads the corresponding baseline JSON files
- Normalises both into a unified structure
- Compares findings by (CVE, package, source)
- Outputs a Markdown delta report
- Also prints the report to the GitHub Actions summary

Used by:
The scheduled deltas workflow for daily security drift detection.

---

### 3. security-summary.py

Purpose:
Aggregates and classifies all vulnerabilities found in the Docker image, the Qlik install directory, and the Qlik data directory. Produces a structured, human-readable Markdown security report.

Key features:
- Normalises Trivy and Grype output
- Deduplicates findings
- Classifies each finding by ownership (maintainer or vendor), fixability, and noise level
- Groups results into actionable sections:
  - Fixable by Maintainer
  - Vendor-Owned (Qlik)
  - Likely Noise
  - Full Findings

Used by:
The main build-and-scan workflow for every version built.

---

### 4. update-action-shas.sh

Purpose:
Pins all GitHub Actions in workflow files to immutable commit SHAs. This ensures deterministic CI behaviour, protects against tag hijacking, and improves reproducibility.

How it works:
- Scans .github/workflows for uses: owner/repo@version references
- Skips entries already pinned to a SHA
- Resolves tags (such as v4 or main) to their latest commit SHA using the GitHub API
- Rewrites workflow files in place

Used by:
Developers, manually or via automation, to keep workflows secure and reproducible.
