#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="$(basename "${BASH_SOURCE[0]}" .sh)"
# shellcheck source=/common.sh
source "${script_dir}/common.sh"

if [[ -z "${REPLICATEDATAFOLDER:-}" ]]; then
    error "REPLICATEDATAFOLDER is required"
    exit 1
fi

for cmd in runuser inotifywait tail sed; do
    require_cmd "${cmd}" || exit 1
done

_replicate_data_folder="${REPLICATEDATAFOLDER}"
_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_replicate_bin="${REPLICATEBIN:-/opt/attunity/replicate/bin}"
_replicate_logs="${_replicate_data_folder}/logs"

log "Replicate data folder: ${_replicate_data_folder}"
log "Replicate logs folder: ${_replicate_logs}"
log "Replicate REST port: ${_replicate_rest_port}"
log "Replicate bin folder: ${_replicate_bin}"

_admin_password_file="${REPLICATEADMINPASSWORDFILE:-/run/secrets/replicate_admin_password}"
if [[ -n "${REPLICATEADMINPASSWORD:-}" ]]; then
    log "Using REPLICATEADMINPASSWORD from environment"
    _replicate_admin_password="${REPLICATEADMINPASSWORD}"
elif [[ -r "${_admin_password_file}" ]]; then
    IFS= read -r _replicate_admin_password < "${_admin_password_file}" || [[ -n "${_replicate_admin_password:-}" ]]

    # Normalize common file artifacts (Windows CRLF / UTF-8 BOM)
    _replicate_admin_password="${_replicate_admin_password#$'\xEF\xBB\xBF'}"
    _replicate_admin_password="${_replicate_admin_password%$'\r'}"

    log "Replicate admin password read from secret file"
else
    error "REPLICATEADMINPASSWORD or readable ${_admin_password_file} is required"
    exit 1
fi

# license can be passed as env path or default secret file
_replicate_license="${REPLICATELICENSE:-}"
if [[ -z "${_replicate_license}" && -r "/run/secrets/replicate_license" ]]; then
    _replicate_license="/run/secrets/replicate_license"
    log "Replicate license read from secret file"
fi
_replicate_master_key="${REPLICATEMASTERKEY:-}"
if [[ -z "${_replicate_master_key}" && -r "/run/secrets/replicate_master_key" ]]; then
    _replicate_master_key="/run/secrets/replicate_master_key"
    log "Replicate master key read from secret file"
fi

_watcher_pid=""

cleanup() {
    if [[ -n "${_watcher_pid}" ]] && kill -0 "${_watcher_pid}" 2>/dev/null; then
        kill "${_watcher_pid}" 2>/dev/null || true
        wait "${_watcher_pid}" 2>/dev/null || true
    fi
}
trap cleanup SIGTERM SIGINT EXIT

for cmd in inotifywait tail sed; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        error "missing command: ${cmd}"
        exit 1
    }
done

if [[ ! -d "${_replicate_bin}" ]]; then
    error "Replicate bin folder not found at ${_replicate_bin}"
    exit 1
fi

if [[ ! -d "${_replicate_data_folder}" ]]; then
    log "Creating data folder at ${_replicate_data_folder}"
    mkdir -p "${_replicate_data_folder}"
fi

chown -R attunity:attunity "${_replicate_data_folder}"

printf "%s" "${_replicate_admin_password}" | \
    run_as_user attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" setserverpassword ${_replicate_admin_password} || {
        error "Failed to set admin password"
        exit 1
    }

if [[ -n "${_replicate_license}" ]]; then
    run_as_user attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" importlicense "license_file=${_replicate_license}" || \
        warn "License import failed — continuing without valid license"
fi

if [[ -n "${_replicate_master_key}" ]]; then
    printf "%s" "${_replicate_master_key}" | \
        run_as_user attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" setmasterkey ${_replicate_master_key} || \
        warn "Master key import failed — continuing without master key"
fi

run_as_user attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" service start "rest_port=${_replicate_rest_port}"

declare -A _tailed
start_tail() {
    local logfile="$1"

    [[ "${logfile}" == *__*.log ]] && return
    [[ -n "${_tailed["$logfile"]+x}" ]] && return
    _tailed["$logfile"]=1

    log "Tailing log file: ${logfile}"
    tail -F "${logfile}" 2>/dev/null | sed -u "s|^|[$(basename "${logfile}")] |" &
}

shopt -s nullglob
for logfile in "${_replicate_logs}"/*.log; do
    start_tail "${logfile}"
done
shopt -u nullglob

while read -r file; do
    [[ "${file}" == *.log ]] && start_tail "${_replicate_logs}/${file}"
done < <(inotifywait -m -e create --format '%f' "${_replicate_logs}") &

_watcher_pid=$!
wait "${_watcher_pid}"