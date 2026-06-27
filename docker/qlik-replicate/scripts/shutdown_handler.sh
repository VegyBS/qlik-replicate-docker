#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="$(basename "${BASH_SOURCE[0]}" .sh)"
# shellcheck source=/common.sh
source "${script_dir}/common.sh"

_replicate_bin="${REPLICATEBIN:-/opt/attunity/replicate/bin}"
_replicate_data_folder="${REPLICATEDATAFOLDER:-/replicate/data}"
_secret_file="${REPLICATEADMINPASSWORDFILE:-/run/secrets/replicate_admin_password}"
_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_api_base="http://localhost:${_replicate_rest_port}/attunityreplicate/api/v1"

stop_service_fallback() {
    if [[ -x "${_replicate_bin}/repctl.sh" ]]; then
        warn "Stopping Replicate service via fallback"
        run_as_attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" service stop || true
    fi
}

for cmd in curl jq; do
    require_cmd "${cmd}" || exit 1
done

log "SIGTERM received — starting graceful shutdown"

if [[ ! -r "${_secret_file}" ]]; then
    warn "Secret file not readable: ${_secret_file}"
    stop_service_fallback
    exit 0
fi

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

set_api_context "${_api_base}" "admin" "${_replicate_admin_password}"

_task_list="$(api_call GET "/tasks" 2>/dev/null || echo "[]")"
mapfile -t _tasks < <(jq -r '.[]?.name // empty' <<< "${_task_list}" 2>/dev/null || true)

if (( ${#_tasks[@]} == 0 )); then
    log "No tasks found"
else
    for _task in "${_tasks[@]}"; do
        log "Stopping task: ${_task}"

        _task_enc="$(jq -rn --arg t "${_task}" '$t|@uri')"
        api_call POST "/tasks/${_task_enc}/stop" >/dev/null 2>&1 || \
            warn "Stop request failed for task: ${_task}"

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

log "Stopping Replicate service"
api_call POST "/server/stop" >/dev/null 2>&1 || stop_service_fallback

log "Shutdown sequence complete"
exit 0