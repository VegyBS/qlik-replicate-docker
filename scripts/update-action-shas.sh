#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# update-action-shas.sh
#
# Scans your workflow files for GitHub Actions references and replaces
# tag-based versions with the latest commit SHA from the GitHub API.
#
# Requirements:
#   - curl
#   - jq
#
# This script is intentionally simple and transparent.
# -----------------------------------------------------------------------------

WORKFLOW_DIR=".github/workflows"

echo "🔍 Scanning workflow files in: $WORKFLOW_DIR"
echo

# Find all actions in the form: uses: owner/repo@version
grep -RhoP 'uses:\s*\K[\w\-/]+@[\w\.\-]+' "$WORKFLOW_DIR" | sort -u | while read -r action; do
    OWNER_REPO=$(echo "$action" | cut -d'@' -f1)
    VERSION=$(echo "$action" | cut -d'@' -f2)

    # Skip if already pinned to a SHA
    if [[ "$VERSION" =~ ^[0-9a-f]{40}$ ]]; then
        echo "✔ Already pinned: $OWNER_REPO@$VERSION"
        continue
    fi

    echo "⏳ Fetching latest commit SHA for: $OWNER_REPO (tag: $VERSION)"

    # Query GitHub API for the tag reference
    API_URL="https://api.github.com/repos/$OWNER_REPO/commits/$VERSION"
    SHA=$(curl -s "$API_URL" | jq -r '.sha // empty')

    if [[ -z "$SHA" ]]; then
        echo "❌ Failed to resolve SHA for $OWNER_REPO@$VERSION"
        continue
    fi

    echo "➡ Updating to SHA: $SHA"

    # Replace version with SHA in all workflow files
    sed -i "s|$OWNER_REPO@$VERSION|$OWNER_REPO@$SHA|g" "$WORKFLOW_DIR"/*.yml
done

echo
echo "🎉 SHA pinning update complete."