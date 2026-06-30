#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script: shutdown_handler.sh
# Purpose:
#   Perform a graceful Qlik Replicate shutdown by stopping active tasks through
#   the REST API and then requesting server shutdown.
#
#   This includes:
#     - loading shared helpers from common.sh
#     - validating required external commands are available
#     - reading the admin password from environment or secret file
#     - querying all configured tasks and requesting each task to stop
#     - polling task state until stopped before shutting down the server
#     - falling back to repctl.sh if API-based shutdown is unavailable
#
#   This ensures:
#     - active work is stopped cleanly before process termination
#     - shutdown behaviour is consistent and observable in logs
#     - API failures degrade to a best-effort local service stop
#     - container stop events do not rely solely on abrupt termination
#
# Requirements:
#   - bash
#   - common.sh in the same scripts directory
#   - curl and jq available in PATH
#   - readable admin password via environment or secret file for API shutdown
#   - repctl.sh available for fallback service stop
#
# Notes:
#   This script is intended to be invoked during container termination. It
#   prefers API-driven task and server shutdown, but falls back to a direct
#   service stop when credentials or API access are unavailable.
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
#   _replicate_bin          Replicate binary directory, overridable via
#                           REPLICATEBIN
#   _replicate_data_folder  Replicate data directory, overridable via
#                           REPLICATEDATAFOLDER
#   _secret_file            Mounted secret file containing the admin password,
#                           overridable via REPLICATEADMINPASSWORDFILE
#   _replicate_rest_port    Local Replicate REST API port, overridable via
#                           REPLICATERESTPORT
#   _api_base               Base URL for authenticated Replicate API calls
# -----------------------------------------------------------------------------
_replicate_bin="${REPLICATEBIN:-/opt/attunity/replicate/bin}"
_replicate_data_folder="${REPLICATEDATAFOLDER:-/replicate/data}"
_secret_file="${REPLICATEADMINPASSWORDFILE:-/run/secrets/replicate_admin_password}"
_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_api_base="http://localhost:${_replicate_rest_port}/attunityreplicate/api/v1"

# -----------------------------------------------------------------------------
# Fallback shutdown path.
# If API-based shutdown cannot be completed, attempt to stop the Replicate
# service directly through repctl.sh. Errors are ignored because this is a
# best-effort last resort during termination handling.
# -----------------------------------------------------------------------------
stop_service_fallback() {
    if [[ -x "${_replicate_bin}/repctl.sh" ]]; then
        warn "Stopping Replicate service via fallback"
        run_as_user "${_replicate_user}" "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" service stop || true
    fi
}

# -----------------------------------------------------------------------------
# Verify that required external commands are available before attempting API
# calls or JSON parsing.
# -----------------------------------------------------------------------------
for cmd in curl jq; do
    require_cmd "${cmd}" || exit 1
done

log "SIGTERM received — starting graceful shutdown"

# -----------------------------------------------------------------------------
# If the admin password secret is not readable, API shutdown cannot proceed.
# Fall back to a direct service stop and exit successfully.
# -----------------------------------------------------------------------------
if [[ ! -r "${_secret_file}" ]]; then
    warn "Secret file not readable: ${_secret_file}"
    stop_service_fallback
    exit 0
fi

# -----------------------------------------------------------------------------
# Resolve the admin password.
#
# Preference order:
#   1. REPLICATEADMINPASSWORD environment variable
#   2. mounted secret file
#
# When reading from file, strip a UTF-8 BOM and trailing carriage return so
# credentials remain valid across different secret creation methods/platforms.
# -----------------------------------------------------------------------------
if [[ -n "${REPLICATEADMINPASSWORD:-}" ]]; then
    _replicate_admin_password="${REPLICATEADMINPASSWORD}"
elif [[ -r "${_secret_file}" ]]; then
    IFS= read -r _replicate_admin_password < "${_secret_file}" || [[ -n "${_replicate_admin_password:-}" ]]

    _replicate_admin_password="${_replicate_admin_password#$'\xEF\xBB\xBF'}"
    _replicate_admin_password="${_replicate_admin_password%$'\r'}"
else
    warn "No admin password provided (env or readable secret file). Using fallback stop."
    stop_service_fallback
    exit 0
fi

# -----------------------------------------------------------------------------
# Store authenticated API context for subsequent calls through api_call().
# -----------------------------------------------------------------------------
set_api_context "${_api_base}" "admin" "${_replicate_admin_password}"

# -----------------------------------------------------------------------------
# Retrieve the current task list.
# API failure is tolerated here so shutdown can continue with an empty task set
# rather than aborting the whole termination sequence.
# -----------------------------------------------------------------------------
_task_list="$(api_call GET "/tasks" 2>/dev/null || echo "[]")"
mapfile -t _tasks < <(jq -r '.[]?.name // empty' <<< "${_task_list}" 2>/dev/null || true)

# -----------------------------------------------------------------------------
# If no tasks are returned, skip task shutdown and proceed directly to server
# shutdown. Otherwise, stop each task individually and wait for confirmation.
# -----------------------------------------------------------------------------
if (( ${#_tasks[@]} == 0 )); then
    log "No tasks found"
else
    for _task in "${_tasks[@]}"; do
        log "Stopping task: ${_task}"

        # ---------------------------------------------------------------------
        # URL-encode the task name so API paths remain valid for names
        # containing spaces or special characters.
        # ---------------------------------------------------------------------
        _task_enc="$(jq -rn --arg t "${_task}" '$t|@uri')"
        api_call POST "/tasks/${_task_enc}/stop" >/dev/null 2>&1 || \
            warn "Stop request failed for task: ${_task}"

        # ---------------------------------------------------------------------
        # Poll task state for up to 30 seconds, waiting for the explicit
        # "Stopped" state before moving on to the next task.
        # ---------------------------------------------------------------------
        for _i in {1..30}; do
            _state="$(api_call GET "/tasks/${_task_enc}" 2>/dev/null | jq -r '.state // "unknown"' 2>/dev/null || echo "unknown")"
            if [[ "${_state}" == "Stopped" ]]; then
                log "Task stopped: ${_task}"
                break
            fi
            sleep 1
        done
    done
fi

# -----------------------------------------------------------------------------
# Request server shutdown through the REST API.
# If the API call fails, fall back to the local repctl.sh stop path.
# -----------------------------------------------------------------------------
log "Stopping Replicate service"
api_call POST "/server/stop" >/dev/null 2>&1 || stop_service_fallback

# -----------------------------------------------------------------------------
# Shutdown handling is complete. Exit successfully so the caller can continue
# termination flow without treating shutdown as a script error.
# -----------------------------------------------------------------------------
log "Shutdown sequence complete"
exit 0