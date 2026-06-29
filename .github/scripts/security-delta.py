#!/usr/bin/env python3
import json
import argparse
from pathlib import Path
from collections import defaultdict
import shutil

# ------------------------------------------------------------------------------
# Script: security-delta.py
# Purpose:
#   Compare the current vulnerability scan results with the stored baseline
#   and produce a delta report showing:
#       - New vulnerabilities introduced since the last scan
#       - Vulnerabilities that have been resolved
#
#   This script is used in scheduled CI runs to track daily changes in the
#   security posture of each Qlik Replicate version.
# ------------------------------------------------------------------------------

SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]

# ------------------------------------------------------------------------------
# Load a JSON file safely. Returns {} on failure.
# ------------------------------------------------------------------------------
def load_json(path):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return {}

# ------------------------------------------------------------------------------
# Normalise Trivy JSON into a consistent internal structure.
# Each entry represents a single vulnerability finding.
# ------------------------------------------------------------------------------
def normalise_trivy(data, source):
    results = []
    for result in data.get("Results", []):
        for vuln in result.get("Vulnerabilities", []):
            results.append({
                "cve": vuln.get("VulnerabilityID"),
                "severity": vuln.get("Severity", "UNKNOWN").upper(),
                "package": vuln.get("PkgName"),
                "version": vuln.get("InstalledVersion"),
                "fixed": vuln.get("FixedVersion"),
                "source": source,
                "scanner": "trivy",
            })
    return results

# ------------------------------------------------------------------------------
# Normalise Grype JSON into the same internal structure as Trivy.
# ------------------------------------------------------------------------------
def normalise_grype(data, source):
    results = []
    for match in data.get("matches", []):
        vuln = match.get("vulnerability", {})
        artifact = match.get("artifact", {})
        results.append({
            "cve": vuln.get("id"),
            "severity": vuln.get("severity", "UNKNOWN").upper(),
            "package": artifact.get("name"),
            "version": artifact.get("version"),
            "fixed": vuln.get("fix", {}).get("versions", []),
            "source": source,
            "scanner": "grype",
        })
    return results

# ------------------------------------------------------------------------------
# Detect whether a file is Trivy or Grype based on its JSON structure.
# ------------------------------------------------------------------------------
def normalise_file(path, source):
    data = load_json(path)

    # Ignore empty files, lists, or unexpected formats
    if not isinstance(data, dict):
        print(f"Ignoring non-dict JSON file: {path}")
        return []

    if "Results" in data:
        return normalise_trivy(data, source)

    if "matches" in data:
        return normalise_grype(data, source)

    # Ignore SBOMs or unknown formats
    return []


# ------------------------------------------------------------------------------
# Convert a list of findings into a dict keyed by (CVE, package, source).
# This allows fast comparison between current and baseline results.
# ------------------------------------------------------------------------------
def index_by_key(findings):
    indexed = {}
    for f in findings:
        key = (f["cve"], f["package"], f["source"])
        indexed[key] = f
    return indexed

# ------------------------------------------------------------------------------
# Write the delta report to a Markdown file.
# Includes:
#   - New vulnerabilities
#   - Resolved vulnerabilities
# ------------------------------------------------------------------------------
def generate_markdown(new, resolved, version, output_path):
    with open(output_path, "w") as out:
        out.write(f"# Vulnerability Delta Report — {version}\n\n")

        # New vulnerabilities
        out.write("## 🔺 New Vulnerabilities\n\n")
        if not new:
            out.write("_None_\n\n")
        else:
            out.write("| CVE | Severity | Package | Source | Scanner |\n")
            out.write("|-----|----------|---------|--------|---------|\n")
            for f in new:
                out.write(f"| {f['cve']} | {f['severity']} | {f['package']} | {f['source']} | {f['scanner']} |\n")
            out.write("\n")

        # Resolved vulnerabilities
        out.write("## 🟢 Resolved Vulnerabilities\n\n")
        if not resolved:
            out.write("_None_\n\n")
        else:
            out.write("| CVE | Package | Source |\n")
            out.write("|-----|---------|--------|\n")
            for f in resolved:
                out.write(f"| {f['cve']} | {f['package']} | {f['source']} |\n")
            out.write("\n")

def persist_baseline(current_files, baseline_dir: Path):
    baseline_dir.mkdir(parents=True, exist_ok=True)

    # Keep only scanner JSON files in baseline
    scanner_files = [f for f in current_files if ("trivy" in f.name or "grype" in f.name)]

    # Remove old scanner files not present anymore
    keep = {f.name for f in scanner_files}
    for old in baseline_dir.glob("*.json"):
        if ("trivy" in old.name or "grype" in old.name) and old.name not in keep:
            old.unlink()

    # Copy current scanner results into baseline
    for src in scanner_files:
        shutil.copy2(src, baseline_dir / src.name)

# ------------------------------------------------------------------------------
# Main entry point:
#   - Load current and baseline JSON files
#   - Normalise findings
#   - Compare to detect new/resolved vulnerabilities
#   - Output Markdown + GitHub summary
# ------------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--current-dir", required=True)
    parser.add_argument("--baseline-dir", required=True)
    parser.add_argument("--version", required=True)
    args = parser.parse_args()

    current_dir = Path(args.current_dir)
    baseline_dir = Path(args.baseline_dir)

    # All JSON files from current scan and baseline
    current_files = list(current_dir.glob("*.json"))
    baseline_files = list(baseline_dir.glob("*.json"))

    current_findings = []
    baseline_findings = []

    # Normalise current scan results
    for f in current_files:
        if "trivy" in f.name:
            source = "image" if "image" in f.name else ("install" if "install" in f.name else "data")
            current_findings += normalise_file(f, source)
        if "grype" in f.name:
            source = "image" if "image" in f.name else ("install" if "install" in f.name else "data")
            current_findings += normalise_file(f, source)

    # Normalise baseline scan results
    for f in baseline_files:
        if "trivy" in f.name:
            source = "image" if "image" in f.name else ("install" if "install" in f.name else "data")
            baseline_findings += normalise_file(f, source)
        if "grype" in f.name:
            source = "image" if "image" in f.name else ("install" if "install" in f.name else "data")
            baseline_findings += normalise_file(f, source)

    # Index findings for fast comparison
    current_index = index_by_key(current_findings)
    baseline_index = index_by_key(baseline_findings)

    new = [v for k, v in current_index.items() if k not in baseline_index]
    resolved = [v for k, v in baseline_index.items() if k not in current_index]

    # Persist current scans as next baseline
    persist_baseline(current_files, baseline_dir)

    # Write Markdown report
    output_path = f"delta-summary-{args.version}.md"
    generate_markdown(new, resolved, args.version, output_path)

    # Also output to GitHub step summary
    print(f"## Vulnerability Delta Report — {args.version}")
    print(open(output_path).read())

if __name__ == "__main__":
    main()
