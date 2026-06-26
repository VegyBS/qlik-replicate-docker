#!/bin/bash
# Shared helpers for Replicate scripts

# Prevent double-loading
if [[ -n "${_COMMON_SH_LOADED:-}" ]]; then
    return 0
fi
_COMMON_SH_LOADED=1

# Defaults (can be overridden by env)
_log_prefix="${LOG_PREFIX:-script}"
_replicate_user="${REPLICATE_USER:-attunity}"
_curl_connect_timeout="${CURL_CONNECT_TIMEOUT:-2}"
_curl_max_time="${CURL_MAX_TIME:-8}"

# API context (internal)
_api_base="${_API_BASE:-}"
_api_auth="${_API_AUTH:-}"

log()   { echo "[${_log_prefix}] $*"; }
warn()  { echo "[${_log_prefix}] WARNING: $*" >&2; }
error() { echo "[${_log_prefix}] ERROR: $*" >&2; }

run_as_user() {
    local user="$1"
    shift
    runuser -u "${user}" -- "$@"
}

set_api_context() {
    local base_url="$1"
    local username="$2"
    local password="$3"

    _api_base="${base_url}"
    _api_auth="${username}:${password}"
}

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

require_cmd() {
    local cmd="$1"
    if ! command -v "${cmd}" >/dev/null 2>&1; then
        error "Required command not found: ${cmd}"
        return 1
    fi
}
