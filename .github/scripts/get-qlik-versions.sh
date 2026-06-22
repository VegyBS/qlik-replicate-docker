#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# Script: get-qlik-versions.sh
# Purpose:
#   Discover the latest Qlik Replicate release families and output only the
#   Linux installer tarball URLs for those versions.
#
#   This script is used by the CI pipeline to dynamically determine which
#   Replicate versions should be built and scanned.
# ------------------------------------------------------------------------------

REPO="qlik-download/replicate"

# ------------------------------------------------------------------------------
# 1. Fetch all GitHub tags for the Qlik Replicate repository
#    The GitHub API returns tag objects; we only need the tag names.
# ------------------------------------------------------------------------------
RAW_TAGS=$(curl -s "https://api.github.com/repos/$REPO/tags?per_page=100")

# ------------------------------------------------------------------------------
# 2. Extract tag names matching the pattern vYYYY.M.P
#    Example: v2025.11.2
# ------------------------------------------------------------------------------
TAGS=$(echo "$RAW_TAGS" \
  | grep -oE '"name":\s*"v[0-9]{4}\.[0-9]{1,2}\.[0-9]+"' \
  | sed -E 's/"name":\s*"([^"]+)"/\1/' \
)

# ------------------------------------------------------------------------------
# 3. Normalise tag names by removing the leading 'v'
#    Then sort versions in descending order (newest first).
# ------------------------------------------------------------------------------
VERSIONS=$(echo "$TAGS" \
  | sed 's/^v//' \
  | sort -rV \
)

# ------------------------------------------------------------------------------
# 4. Extract the base version family (YYYY.M)
#    Example: 2025.11.2 → 2025.11
#    uniq preserves order because input is already sorted.
# ------------------------------------------------------------------------------
BASES=$(echo "$VERSIONS" \
  | awk -F. '{print $1"."$2}' \
  | uniq \
)

# ------------------------------------------------------------------------------
# 5. Select the latest two version families
#    These represent the most recent major/minor release lines.
# ------------------------------------------------------------------------------
LATEST_TWO_BASES=$(echo "$BASES" | head -n 2)

echo "Latest 2 version families:"
echo "$LATEST_TWO_BASES"
echo

# ------------------------------------------------------------------------------
# 6. For each version family, enumerate all patch versions and extract ONLY
#    the Linux installer tarball URLs.
#
#    Rules:
#      - Must end with .tar.gz
#      - Must contain 'Linux' OR start with 'areplicate-'
#    This filters out Windows installers and unrelated assets.
# ------------------------------------------------------------------------------
for BASE in $LATEST_TWO_BASES; do
  echo "Version family: $BASE"

  # All versions matching the base (e.g., 2025.11.*)
  MATCHING=$(echo "$VERSIONS" | grep "^$BASE")

  for VERSION in $MATCHING; do
    TAG="v$VERSION"

    # Fetch release metadata for this specific tag
    RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/tags/$TAG")

    # Extract Linux installer URLs
    echo "$RELEASE_JSON" \
      | grep -oE '"browser_download_url":\s*"[^"]+\.tar\.gz"' \
      | sed -E 's/"browser_download_url":\s*"([^"]+)"/\1/' \
      | grep -E 'Linux|areplicate-' \
      || true
  done

  echo
done
