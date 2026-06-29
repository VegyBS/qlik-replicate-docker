#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script: update-action-shas.sh
# Purpose:
#   Scan all workflow files for GitHub Actions references and replace any
#   tag-based versions (e.g., @v4, @main) with the corresponding immutable
#   commit SHA retrieved from the GitHub API.
#
#   This ensures:
#     - deterministic CI behaviour
#     - protection against tag hijacking
#     - reproducible builds
#
# Requirements:
#   - curl
#   - jq
#
# Notes:
#   The script is intentionally simple and transparent. It performs no caching
#   and makes one API call per action reference.
# -----------------------------------------------------------------------------

WORKFLOW_DIR=".github/workflows"

echo "🔍 Scanning workflow files in: $WORKFLOW_DIR"
echo

# -----------------------------------------------------------------------------
# Locate all 'uses:' references of the form:
#     uses: owner/repo@version
#
# The grep expression extracts only the owner/repo@version portion.
# Sorting ensures each unique action is processed once.
# -----------------------------------------------------------------------------
grep -RhoP 'uses:\s*\K[\w\-/]+@[\w\.\-]+' "$WORKFLOW_DIR" | sort -u | while read -r action; do
    OWNER_REPO=$(echo "$action" | cut -d'@' -f1)
    VERSION=$(echo "$action" | cut -d'@' -f2)

    # -------------------------------------------------------------------------
    # Skip entries already pinned to a 40‑character SHA
    # -------------------------------------------------------------------------
    if [[ "$VERSION" =~ ^[0-9a-f]{40}$ ]]; then
        echo "✔ Already pinned: $OWNER_REPO@$VERSION"
        continue
    fi

    echo "⏳ Fetching latest commit SHA for: $OWNER_REPO (tag: $VERSION)"

    # -------------------------------------------------------------------------
    # Query GitHub API for the commit referenced by the tag
    # Example:
    #   https://api.github.com/repos/actions/checkout/commits/v4
    #
    # jq extracts the `.sha` field or returns empty if not found.
    # -------------------------------------------------------------------------
    API_URL="https://api.github.com/repos/$OWNER_REPO/commits/$VERSION"
    SHA=$(curl -s "$API_URL" | jq -r '.sha // empty')

    if [[ -z "$SHA" ]]; then
        echo "❌ Failed to resolve SHA for $OWNER_REPO@$VERSION"
        continue
    fi

    echo "➡ Updating to SHA: $SHA"

    # -------------------------------------------------------------------------
    # Replace the tag with the resolved SHA across all workflow files.
    # sed -i performs an in-place update.
    # -------------------------------------------------------------------------
    sed -i "s|$OWNER_REPO@$VERSION|$OWNER_REPO@$SHA|g" "$WORKFLOW_DIR"/*.yml
done

echo
echo "🎉 SHA pinning update complete."
