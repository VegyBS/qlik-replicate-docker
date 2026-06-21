#!/usr/bin/env bash
set -euo pipefail

REPO="qlik-download/replicate"

# 1. Fetch all tags
RAW_TAGS=$(curl -s "https://api.github.com/repos/$REPO/tags?per_page=100")

# 2. Extract tag names like v2025.11.2
TAGS=$(echo "$RAW_TAGS" \
  | grep -oE '"name":\s*"v[0-9]{4}\.[0-9]{1,2}\.[0-9]+"' \
  | sed -E 's/"name":\s*"([^"]+)"/\1/' \
)

# 3. Normalise: v2025.11.2 → 2025.11.2 and sort newest → oldest
VERSIONS=$(echo "$TAGS" \
  | sed 's/^v//' \
  | sort -rV \
)

# 4. Extract base versions (YYYY.M)
BASES=$(echo "$VERSIONS" \
  | awk -F. '{print $1"."$2}' \
  | uniq \
)

# 5. Take the latest 2 version families
LATEST_TWO_BASES=$(echo "$BASES" | head -n 2)

echo "Latest 2 version families:"
echo "$LATEST_TWO_BASES"
echo

# 6. For each base version, output ONLY Linux installer tarballs
for BASE in $LATEST_TWO_BASES; do
  echo "Version family: $BASE"

  MATCHING=$(echo "$VERSIONS" | grep "^$BASE")

  for VERSION in $MATCHING; do
    TAG="v$VERSION"

    RELEASE_JSON=$(curl -s "https://api.github.com/repos/$REPO/releases/tags/$TAG")

    # Extract only Linux installer tarballs:
    # - must end with .tar.gz
    # - must contain Linux OR start with areplicate-
    echo "$RELEASE_JSON" \
      | grep -oE '"browser_download_url":\s*"[^"]+\.tar\.gz"' \
      | sed -E 's/"browser_download_url":\s*"([^"]+)"/\1/' \
      | grep -E 'Linux|areplicate-' \
      || true
  done

  echo
done
