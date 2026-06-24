#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="start"
# shellcheck source=lib/common.sh
source "${script_dir}/lib/common.sh"

if [[ -z "${REPLICATEDATAFOLDER:-}" ]]; then
    error "REPLICATEDATAFOLDER is required"
    exit 1
fi

_replicate_data_folder="${REPLICATEDATAFOLDER}"
_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_replicate_bin="${REPLICATEBIN:-/opt/attunity/replicate/bin}"
_replicate_logs="${_replicate_data_folder}/logs"

_admin_password_file="${REPLICATEADMINPASSWORDFILE:-/run/secrets/replicate_admin_password}"
if [[ -n "${REPLICATEADMINPASSWORD:-}" ]]; then
    _replicate_admin_password="${REPLICATEADMINPASSWORD}"
elif [[ -r "${_admin_password_file}" ]]; then
    read -r _replicate_admin_password < "${_admin_password_file}"
else
    error "REPLICATEADMINPASSWORD or readable ${_admin_password_file} is required"
    exit 1
fi

# license can be passed as env path or default secret file
_replicate_license="${REPLICATELICENSE:-}"
if [[ -z "${_replicate_license}" && -r "/run/secrets/replicate_license" ]]; then
    _replicate_license="/run/secrets/replicate_license"
fi
_replicate_master_key="${REPLICATEMASTERKEY:-}"
if [[ -z "${_replicate_master_key}" && -r "/run/secrets/replicate_master_key" ]]; then
    _replicate_master_key="/run/secrets/replicate_master_key"
fi
_replicate_bin="${REPLICATEBIN:-/opt/attunity/replicate/bin}"
_replicate_logs="${_replicate_data_folder}/logs"
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

mkdir -p "${_replicate_logs}"
chown -R attunity:attunity "${_replicate_data_folder}"

log "Setting Replicate admin password"
printf "%s" "${_replicate_admin_password}" | \
    run_as_attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" setserverpassword -

if [[ -n "${_replicate_license}" ]]; then
    log "Importing Replicate license from ${_replicate_license}"
    run_as_attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" importlicense "license_file=${_replicate_license}"
fi

if [[ -n "${_replicate_master_key}" ]]; then
    log "Setting Replicate master key"
    printf "%s" "${_replicate_master_key}" | \
        run_as_attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" setmasterkey -
fi

log "Starting Replicate service on port ${_replicate_rest_port}"
run_as_attunity "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" service start "rest_port=${_replicate_rest_port}"

declare -A _tailed
start_tail() {
    local logfile="$1"

    [[ "${logfile}" == *__*.log ]] && return
    [[ -n "${_tailed["$logfile"]+x}" ]] && return
    _tailed["$logfile"]=1

    log "Tailing log file: ${logfile}"
    tail -F "${logfile}" 2>/dev/null | sed -u "s|^|$(basename "${logfile}"): |" &
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