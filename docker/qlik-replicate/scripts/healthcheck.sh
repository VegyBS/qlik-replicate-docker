#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="healthcheck"
# shellcheck source=lib/common.sh
source "${script_dir}/lib/common.sh"

_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_secret_file="/run/secrets/replicate_admin_password"

if [[ ! -r "${_secret_file}" ]]; then
    error "Secret file not readable: ${_secret_file}"
    exit 1
fi

read -r _replicate_admin_password < "${_secret_file}"

_api_base="http://localhost:${_replicate_rest_port}/attunityreplicate/api/v1"
set_api_context "${_api_base}" "admin" "${_replicate_admin_password}"

_response="$(api_call GET "/server/status" 2>/dev/null || true)"
_replicate_status="$(jq -r '.state // "unknown"' <<< "${_response}" 2>/dev/null || echo "unknown")"

if [[ "${_replicate_status}" == "Running" ]]; then
    log "Replicate is healthy"
    exit 0
fi

error "Replicate unhealthy (state: ${_replicate_status})"
exit 1