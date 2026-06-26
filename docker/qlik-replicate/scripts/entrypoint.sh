#!/bin/bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_PREFIX="$(basename "${BASH_SOURCE[0]}" .sh)"
# shellcheck source=/common.sh
source "${script_dir}/common.sh"

_start_script="${script_dir}/start_replicate.sh"
_shutdown_script="${script_dir}/shutdown_handler.sh"
_main_pid=""

if [[ ! -x "${_start_script}" ]]; then
    error "start script not found or not executable: ${_start_script}"
    exit 1
fi

if [[ ! -x "${_shutdown_script}" ]]; then
    error "shutdown script not found or not executable: ${_shutdown_script}"
    exit 1
fi

on_term() {
    log "Caught termination signal, shutting down Replicate..."
    "${_shutdown_script}" || true

    if [[ -n "${_main_pid}" ]] && kill -0 "${_main_pid}" 2>/dev/null; then
        kill -TERM "${_main_pid}" 2>/dev/null || true
        wait "${_main_pid}" 2>/dev/null || true
    fi
}

trap on_term SIGTERM SIGINT

log "Starting Replicate service..."
"${_start_script}" &
_main_pid=$!

wait "${_main_pid}"