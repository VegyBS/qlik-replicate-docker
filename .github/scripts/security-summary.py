#!/usr/bin/env python3
import json
import argparse
from collections import defaultdict
from enum import Enum, auto

# ------------------------------------------------------------------------------
# Script: security-summary.py
# Purpose:
#   Aggregate and classify vulnerability findings from Trivy and Grype scans
#   across three sources:
#       - Docker image
#       - Qlik install directory
#       - Qlik data directory
#
#   The script:
#       1. Normalises scanner output into a unified structure
#       2. Deduplicates findings
#       3. Classifies ownership, fixability, and noise level
#       4. Produces a structured Markdown security report
#
#   This is the main human‑readable security summary used in CI.
# ------------------------------------------------------------------------------

# Classification enums used throughout the report
class Ownership(Enum):
    MAINTAINER = auto()   # Fixable by you (base image / OS packages)
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
# Load JSON safely. Returns [] on failure to keep downstream logic simple.
# ------------------------------------------------------------------------------
def load_json(path):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except Exception:
        return []

# ------------------------------------------------------------------------------
# Normalise Trivy JSON into a consistent internal structure.
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
# Normalise Grype JSON into the same structure as Trivy.
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
# Merge findings from image/install/data scans and dedupe by (CVE, package, source).
# ------------------------------------------------------------------------------
def merge_findings(image, install, data):
    all_findings = image + install + data
    deduped = {}

    for f in all_findings:
        key = (f["cve"], f["package"], f["source"])
        if key not in deduped:
            deduped[key] = f
        else:
            # Merge fixed-version lists if both scanners reported them
            if isinstance(f["fixed"], list):
                deduped[key]["fixed"] = list(set(deduped[key]["fixed"] + f["fixed"]))

    return list(deduped.values())

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

    # Groupings for report sections
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
# Main entry point: load → normalise → merge → classify → report.
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

    # Load and normalise scanner outputs
    for p in args.image:
        data = load_json(p)
        image_findings += normalise_trivy(data, "image")
        image_findings += normalise_grype(data, "image")

    for p in args.install:
        data = load_json(p)
        install_findings += normalise_trivy(data, "install")
        install_findings += normalise_grype(data, "install")

    for p in args.data:
        data = load_json(p)
        data_findings += normalise_trivy(data, "data")
        data_findings += normalise_grype(data, "data")

    # Merge, classify, and output
    findings = merge_findings(image_findings, install_findings, data_findings)
    findings = enrich_findings(findings)
    generate_markdown(findings, args.output)

if __name__ == "__main__":
    main()
