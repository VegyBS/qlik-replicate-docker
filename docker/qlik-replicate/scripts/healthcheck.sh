#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script: healthcheck.sh
# Purpose:
#   Verify that the Qlik Replicate service is reachable and reports a healthy
#   running state through its REST API.
#
#   This includes:
#     - loading shared helpers from common.sh
#     - reading the admin password from the mounted secret file
#     - configuring authenticated API access to the local Replicate endpoint
#     - querying the server status endpoint and evaluating the returned state
#
#   This ensures:
#     - container health checks reflect actual service readiness
#     - API authentication is handled consistently
#     - unhealthy or inaccessible Replicate instances fail clearly
#     - health status is logged in a predictable format
#
# Requirements:
#   - bash
#   - common.sh in the same scripts directory
#   - jq for parsing the JSON API response
#   - readable admin password secret at /run/secrets/replicate_admin_password
#
# Notes:
#   This script is intended for container health check use. It treats only the
#   Replicate state "Running" as healthy and returns a non-zero exit code for
#   any other state, missing secret, or API failure.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Resolve the directory containing this script so common.sh can be sourced
# reliably regardless of the current working directory.
# -----------------------------------------------------------------------------
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Set the shared log prefix to the current script name before loading common
# helpers so log(), warn(), and error() use a meaningful identifier.
# -----------------------------------------------------------------------------
LOG_PREFIX="$(basename "${BASH_SOURCE[0]}" .sh)"

# -----------------------------------------------------------------------------
# Load shared logging and API helper functions used throughout the script.
# -----------------------------------------------------------------------------
# shellcheck source=/common.sh
source "${script_dir}/common.sh"

# -----------------------------------------------------------------------------
# Default runtime configuration.
#
#   _replicate_rest_port  Local Replicate REST API port, overridable via
#                         REPLICATERESTPORT
#   _secret_file          Mounted secret containing the admin password
# -----------------------------------------------------------------------------
_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_secret_file="/run/secrets/replicate_admin_password"

# -----------------------------------------------------------------------------
# Fail early if the admin password secret is missing or unreadable.
# -----------------------------------------------------------------------------
if [[ ! -r "${_secret_file}" ]]; then
    error "Secret file not readable: ${_secret_file}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Read the admin password from the mounted secret file.
# -----------------------------------------------------------------------------
read -r _replicate_admin_password < "${_secret_file}"

# -----------------------------------------------------------------------------
# Build the local Replicate API base URL and store authenticated API context
# for subsequent calls through api_call().
# -----------------------------------------------------------------------------
_api_base="http://localhost:${_replicate_rest_port}/attunityreplicate/api/v1"
set_api_context "${_api_base}" "admin" "${_replicate_admin_password}"

# -----------------------------------------------------------------------------
# Query the Replicate server status endpoint.
# API call failures are tolerated here so the script can convert them into a
# controlled unhealthy result instead of exiting immediately.
# -----------------------------------------------------------------------------
_response="$(api_call GET "/server/status" 2>/dev/null || true)"

# -----------------------------------------------------------------------------
# Extract the reported Replicate state from the JSON response.
# If parsing fails or the field is absent, fall back to "unknown".
# -----------------------------------------------------------------------------
_replicate_status="$(jq -r '.state // "unknown"' <<< "${_response}" 2>/dev/null || echo "unknown")"

# -----------------------------------------------------------------------------
# Only the explicit state "Running" is considered healthy.
# -----------------------------------------------------------------------------
if [[ "${_replicate_status}" == "Running" ]]; then
    log "Replicate is healthy"
    exit 0
fi

# -----------------------------------------------------------------------------
# Any other state is treated as unhealthy for container health reporting.
# -----------------------------------------------------------------------------
error "Replicate unhealthy (state: ${_replicate_status})"
exit 1