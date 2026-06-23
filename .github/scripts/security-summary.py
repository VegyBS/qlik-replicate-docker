#!/usr/bin/env python3
import json
import argparse
from collections import defaultdict
from enum import Enum, auto

# ------------------------------------------------------------------------------
# Script: security-summary.py
#
# Purpose:
#   Produce a unified, human‑readable security summary from multiple vulnerability
#   scanners (Trivy, Grype, Syft) across three scan sources:
#
#       - Docker image
#       - Qlik install directory
#       - Qlik data directory
#
#   The script:
#       1. Loads JSON output from all scanners
#       2. Detects which scanner produced each file
#       3. Normalises findings into a consistent internal structure
#       4. Merges and deduplicates findings across scanners and sources
#       5. Classifies ownership, fixability, and noise level
#       6. Generates a structured Markdown report for CI consumption
#
#   Syft SBOMs contain no vulnerabilities, but are accepted safely and ignored
#   for vulnerability aggregation.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Classification enums used throughout the report
# ------------------------------------------------------------------------------
class Ownership(Enum):
    MAINTAINER = auto()   # Fixable by the image maintainer (OS/base image)
    VENDOR = auto()       # Qlik-owned components
    UNKNOWN = auto()

class Fixability(Enum):
    FIXABLE = auto()      # A fixed version exists
    UNFIXED = auto()      # No fix available
    UNKNOWN = auto()

class NoiseLevel(Enum):
    SIGNAL = auto()       # Relevant / actionable
    NOISY = auto()        # Likely non-exploitable
    UNKNOWN = auto()

# Severity ordering for consistent output
SEVERITY_ORDER = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]

# ------------------------------------------------------------------------------
# Load JSON safely. Returns None on failure so caller can decide how to handle.
# ------------------------------------------------------------------------------
def load_json(path):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return None

# ------------------------------------------------------------------------------
# Normalise Trivy JSON into a consistent internal structure.
#
# Expected structure:
#   {
#     "Results": [
#       {
#         "Vulnerabilities": [
#           {
#             "VulnerabilityID": "...",
#             "Severity": "...",
#             "PkgName": "...",
#             "InstalledVersion": "...",
#             "FixedVersion": "..."
#           }
#         ]
#       }
#     ]
#   }
# ------------------------------------------------------------------------------
def normalise_trivy(data, source):
    if not isinstance(data, dict):
        return []
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
# Normalise Grype JSON into the same structure as Trivy.
#
# Expected structure:
#   {
#     "matches": [
#       {
#         "vulnerability": { "id": "...", "severity": "...", "fix": {...} },
#         "artifact": { "name": "...", "version": "..." }
#       }
#     ]
#   }
# ------------------------------------------------------------------------------
def normalise_grype(data, source):
    if not isinstance(data, dict):
        return []
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
# Normalise Syft SBOMs.
#
# Syft produces SBOMs, not vulnerability reports. These contain package metadata
# but no CVEs. For the purposes of this script, Syft contributes zero findings.
# ------------------------------------------------------------------------------
def normalise_syft(data, source):
    return []

# ------------------------------------------------------------------------------
# Detect which scanner produced a given JSON file.
#
# Rules:
#   - Trivy: dict with "Results"
#   - Grype: dict with "matches"
#   - Syft:  list (SBOMs are always lists)
#   - Unknown: anything else
# ------------------------------------------------------------------------------
def detect_scanner(data):
    if isinstance(data, dict):
        if "Results" in data:
            return "trivy"
        if "matches" in data:
            return "grype"
    if isinstance(data, list):
        return "syft"
    return "unknown"

# ------------------------------------------------------------------------------
# Merge findings from image/install/data scans and dedupe by (CVE, package, source).
#
# If both scanners report fixed versions, merge them into a unified list.
# ------------------------------------------------------------------------------
def merge_findings(image, install, data):
    all_findings = image + install + data
    deduped = {}

    for f in all_findings:
        key = (f["cve"], f["package"], f["source"])
        if key not in deduped:
            deduped[key] = f
        else:
            if isinstance(f["fixed"], list):
                deduped[key]["fixed"] = list(set(deduped[key]["fixed"] + f["fixed"]))

    return list(deduped.values())

# ------------------------------------------------------------------------------
# Qlik vendor heuristics used to classify ownership.
# ------------------------------------------------------------------------------
QLIK_VENDOR_PACKAGES = {
    "libssl", "libcrypto", "libxml2", "libcurl",
    "java", "jre", "jvm", "attunity", "replicate"
}

def is_likely_qlik_component(finding):
    pkg = (finding.get("package") or "").lower()
    return any(p in pkg for p in QLIK_VENDOR_PACKAGES)

# ------------------------------------------------------------------------------
# Ownership classification: determines whether a finding is yours or Qlik's.
# ------------------------------------------------------------------------------
def classify_ownership(finding):
    source = finding.get("source")

    # Install/data directories are always Qlik-owned
    if source in ("install", "data"):
        return Ownership.VENDOR

    # Image scan but package matches Qlik patterns
    if source == "image" and is_likely_qlik_component(finding):
        return Ownership.VENDOR

    # Otherwise, image findings belong to the maintainer
    if source == "image":
        return Ownership.MAINTAINER

    return Ownership.UNKNOWN

# ------------------------------------------------------------------------------
# Fixability classification: determines whether a fix exists.
# ------------------------------------------------------------------------------
def classify_fixability(finding, ownership):
    fixed = finding.get("fixed")

    if not fixed or (isinstance(fixed, str) and not fixed.strip()):
        return Fixability.UNFIXED

    return Fixability.FIXABLE

# ------------------------------------------------------------------------------
# Noise classification: filters out low-severity, unfixed, vendor-owned issues.
# ------------------------------------------------------------------------------
def classify_noise(finding, ownership, fixability):
    severity = finding.get("severity", "UNKNOWN").upper()

    if severity in ("CRITICAL", "HIGH"):
        return NoiseLevel.SIGNAL

    if ownership == Ownership.VENDOR and fixability == Fixability.UNFIXED and severity in ("LOW", "UNKNOWN"):
        return NoiseLevel.NOISY

    if ownership == Ownership.MAINTAINER and fixability == Fixability.UNFIXED and severity == "LOW":
        return NoiseLevel.NOISY

    return NoiseLevel.UNKNOWN

# ------------------------------------------------------------------------------
# Apply ownership, fixability, and noise classification to each finding.
# ------------------------------------------------------------------------------
def enrich_findings(findings):
    enriched = []
    for f in findings:
        ownership = classify_ownership(f)
        fixability = classify_fixability(f, ownership)
        noise = classify_noise(f, ownership, fixability)

        f["ownership"] = ownership
        f["fixability"] = fixability
        f["noise"] = noise
        enriched.append(f)
    return enriched

# ------------------------------------------------------------------------------
# Generate the final Markdown report with grouped sections.
# ------------------------------------------------------------------------------
def generate_markdown(findings, output_path):
    by_severity = defaultdict(list)
    for f in findings:
        by_severity[f["severity"]].append(f)

    maintainer_fixable = [
        f for f in findings
        if f["ownership"] == Ownership.MAINTAINER
        and f["fixability"] == Fixability.FIXABLE
    ]

    vendor_owned = [f for f in findings if f["ownership"] == Ownership.VENDOR]
    noisy = [f for f in findings if f["noise"] == NoiseLevel.NOISY]

    with open(output_path, "w") as out:
        out.write("# Security Summary\n\n")

        # ----------------------------------------------------------------------
        # Severity overview table
        # ----------------------------------------------------------------------
        out.write("## Severity Overview\n\n")
        out.write("| Severity | Count |\n|---------|-------|\n")
        for sev in SEVERITY_ORDER:
            out.write(f"| {sev} | {len(by_severity.get(sev, []))} |\n")
        out.write("\n")

        # ----------------------------------------------------------------------
        # Fixable by maintainer
        # ----------------------------------------------------------------------
        out.write("## 🔧 Fixable by Maintainer\n\n")
        if not maintainer_fixable:
            out.write("_None_\n\n")
        else:
            out.write("| CVE | Severity | Package | Source | Fixed |\n")
            out.write("|-----|----------|---------|--------|-------|\n")
            for f in maintainer_fixable:
                fixed = f["fixed"]
                if isinstance(fixed, list):
                    fixed = ", ".join(fixed) or "None"
                out.write(f"| {f['cve']} | {f['severity']} | {f['package']} | {f['source']} | {fixed} |\n")
            out.write("\n")

        # ----------------------------------------------------------------------
        # Vendor-owned (Qlik)
        # ----------------------------------------------------------------------
        out.write("## 🏢 Vendor-Owned (Qlik)\n\n")
        if not vendor_owned:
            out.write("_None_\n\n")
        else:
            out.write("| CVE | Severity | Package | Source |\n")
            out.write("|-----|----------|---------|--------|\n")
            for f in vendor_owned:
                out.write(f"| {f['cve']} | {f['severity']} | {f['package']} | {f['source']} |\n")
            out.write("\n")

        # ----------------------------------------------------------------------
        # Likely noise / non-exploitable
        # ----------------------------------------------------------------------
        out.write("## 💤 Likely Noise / Non-Exploitable\n\n")
        if not noisy:
            out.write("_None_\n\n")
        else:
            out.write("| CVE | Severity | Package | Source |\n")
            out.write("|-----|----------|---------|--------|\n")
            for f in noisy:
                out.write(f"| {f['cve']} | {f['severity']} | {f['package']} | {f['source']} |\n")
            out.write("\n")

        # ----------------------------------------------------------------------
        # Full deduped findings
        # ----------------------------------------------------------------------
        out.write("## 📦 Full Findings (Deduped)\n\n")
        out.write("| CVE | Severity | Package | Version | Fixed | Source | Ownership |\n")
        out.write("|-----|----------|---------|---------|-------|--------|-----------|\n")
        for f in findings:
            fixed = f["fixed"]
            if isinstance(fixed, list):
                fixed = ", ".join(fixed) or "None"
            out.write(
                f"| {f['cve']} | {f['severity']} | {f['package']} | "
                f"{f['version']} | {fixed} | {f['source']} | {f['ownership'].name} |\n"
            )

# ------------------------------------------------------------------------------
# Main entry point: load → detect → normalise → merge → classify → report.
# ------------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--image", nargs="+", required=True)
    parser.add_argument("--install", nargs="+", required=True)
    parser.add_argument("--data", nargs="+", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    image_findings = []
    install_findings = []
    data_findings = []

    # Helper to process a single file
    def process(path, source):
        data = load_json(path)
        if data is None:
            return []

        scanner = detect_scanner(data)

        if scanner == "trivy":
            return normalise_trivy(data, source)
        if scanner == "grype":
            return normalise_grype(data, source)
        if scanner == "syft":
            return normalise_syft(data, source)

        return []

    # Process all image scan files
    for p in args.image:
        image_findings += process(p, "image")

    # Process install directory scan files
    for p in args.install:
        install_findings += process(p, "install")

    # Process data directory scan files
    for p in args.data:
        data_findings += process(p, "data")

    # Merge, classify, and output
    findings = merge_findings(image_findings, install_findings, data_findings)
    findings = enrich_findings(findings)
    generate_markdown(findings, args.output)

if __name__ == "__main__":
    main()
