#!/bin/bash

# -----------------------------------------------------------------------------
# Script: common.sh
# Purpose:
#   Provide shared helper functions and common runtime defaults for Replicate
#   shell scripts.
#
#   This includes:
#     - consistent log/error output helpers
#     - a wrapper for running commands as the Replicate service user
#     - shared API context setup for authenticated HTTP calls
#     - a reusable command-availability check
#
#   This ensures:
#     - less duplication across operational scripts
#     - consistent logging and error handling
#     - centralized API request configuration
#     - safer sourcing through load-once protection
#
# Requirements:
#   - bash
#   - curl for API calls
#   - runuser for user context switching
#
# Notes:
#   This file is intended to be sourced by other scripts rather than executed
#   directly. It uses internal variables for API state and guards against being
#   loaded more than once in the same shell.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Prevent double-loading when the file is sourced multiple times.
# If already loaded, return immediately without redefining functions/variables.
# -----------------------------------------------------------------------------
if [[ -n "${_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
_COMMON_SH_LOADED=1

# -----------------------------------------------------------------------------
# Default configuration values.
# These can be overridden by environment variables before sourcing this file.
#
#   LOG_PREFIX           Prefix used in log output
#   REPLICATE_USER       Default operating system user for Replicate commands
#   CURL_CONNECT_TIMEOUT Connection timeout for API calls in seconds
#   CURL_MAX_TIME        Total API call timeout in seconds
# -----------------------------------------------------------------------------
_log_prefix="${LOG_PREFIX:-script}"
_replicate_user="${REPLICATE_USER:-attunity}"
_curl_connect_timeout="${CURL_CONNECT_TIMEOUT:-2}"
_curl_max_time="${CURL_MAX_TIME:-8}"

# -----------------------------------------------------------------------------
# Internal API context.
# These values are populated by set_api_context() and then consumed by api_call().
# -----------------------------------------------------------------------------
_api_base="${_API_BASE:-}"
_api_auth="${_API_AUTH:-}"

# -----------------------------------------------------------------------------
# Emit a standard informational log message to stdout.
# -----------------------------------------------------------------------------
log()   { echo "[${_log_prefix}] $*"; }

# -----------------------------------------------------------------------------
# Emit a warning message to stderr using a consistent prefix.
# -----------------------------------------------------------------------------
warn()  { echo "[${_log_prefix}] WARNING: $*" >&2; }

# -----------------------------------------------------------------------------
# Emit an error message to stderr using a consistent prefix.
# -----------------------------------------------------------------------------
error() { echo "[${_log_prefix}] ERROR: $*" >&2; }

# -----------------------------------------------------------------------------
# Run the given command as a specific operating system user.
#
# Example:
#   run_as_user attunity /opt/attunity/bin/repctl status
# -----------------------------------------------------------------------------
run_as_user() {
    local user="$1"
    shift
    runuser -u "${user}" -- "$@"
}

# -----------------------------------------------------------------------------
# Store API connection details for later use by api_call().
#
# Parameters:
#   $1 - base API URL
#   $2 - username
#   $3 - password
# -----------------------------------------------------------------------------
set_api_context() {
    local base_url="$1"
    local username="$2"
    local password="$3"

    _api_base="${base_url}"
    _api_auth="${username}:${password}"
}

# -----------------------------------------------------------------------------
# Perform an authenticated API request using the shared API context.
#
# Parameters:
#   $1 - HTTP method
#   $2 - request path appended to the configured base URL
#   $@ - any additional curl arguments such as headers or request body
#
# Behaviour:
#   - fails if API context has not been initialized
#   - uses shared timeout settings
#   - returns curl's exit code on failure
# -----------------------------------------------------------------------------
api_call() {
    local method="$1"
    local path="$2"
    shift 2 || true

    [[ -n "${_api_base}" ]] || { error "API base URL is not set"; return 1; }
    [[ -n "${_api_auth}" ]] || { error "API auth is not set"; return 1; }

    curl --silent --show-error --fail \
        --connect-timeout "${_curl_connect_timeout}" \
        --max-time "${_curl_max_time}" \
        -u "${_api_auth}" \
        -X "${method}" \
        "${_api_base}${path}" \
        "$@"
}

# -----------------------------------------------------------------------------
# Verify that a required command is available in PATH.
#
# Parameters:
#   $1 - command name to check
#
# Returns:
#   0 if present
#   1 if missing
# -----------------------------------------------------------------------------
require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        error "Required command not found: ${cmd}"
        return 1
    fi
}