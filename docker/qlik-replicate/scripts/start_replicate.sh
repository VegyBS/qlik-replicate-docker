#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script: start_replicate.sh
# Purpose:
#   Initialize and start the Qlik Replicate service inside the container, then
#   stream Replicate log files to stdout for container-friendly observability.
#
#   This includes:
#     - loading shared helpers from common.sh
#     - validating required runtime configuration and external commands
#     - resolving admin password, license, and master key inputs
#     - creating and preparing the Replicate data directory
#     - applying server password, optional license, and optional master key
#     - starting the Replicate service and tailing log output
#
#   This ensures:
#     - predictable Replicate startup behaviour
#     - required secrets and paths are validated early
#     - optional licensing and key material are applied consistently
#     - the configured Replicate service user is used consistently
#     - Replicate logs are visible through normal container log collection
#
# Requirements:
#   - bash
#   - common.sh in the same scripts directory
#   - runuser, inotifywait, tail, and sed available in PATH
#   - REPLICATEDATAFOLDER set to a writable Replicate data directory
#   - repctl.sh available under the configured REPLICATEBIN directory
#
# Notes:
#   This script is intended to run as the main Replicate startup helper. It
#   starts the service, tails existing and newly created log files, and keeps
#   running in the foreground by waiting on the log watcher process.
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
# Load shared logging and utility functions used throughout the script.
# -----------------------------------------------------------------------------
# shellcheck source=/common.sh
source "${script_dir}/common.sh"

# -----------------------------------------------------------------------------
# REPLICATEDATAFOLDER is mandatory because Replicate state, configuration, and
# logs are all rooted under this directory.
# -----------------------------------------------------------------------------
if [[ -z "${REPLICATEDATAFOLDER:-}" ]]; then
    error "REPLICATEDATAFOLDER is required"
    exit 1
fi

# -----------------------------------------------------------------------------
# Verify that required external commands are available before startup begins.
# -----------------------------------------------------------------------------
for cmd in runuser inotifywait tail sed; do
    require_cmd "${cmd}" || exit 1
done

# -----------------------------------------------------------------------------
# Default runtime configuration.
#
#   _replicate_data_folder  Required Replicate data directory
#   _replicate_rest_port    Local Replicate REST API port, overridable via
#                           REPLICATERESTPORT
#   _replicate_bin          Replicate binary directory, overridable via
#                           REPLICATEBIN
#   _replicate_logs         Replicate log directory under the data folder
# -----------------------------------------------------------------------------
_replicate_data_folder="${REPLICATEDATAFOLDER}"
_replicate_rest_port="${REPLICATERESTPORT:-3562}"
_replicate_bin="${REPLICATEBIN:-/opt/attunity/replicate/bin}"
_replicate_logs="${_replicate_data_folder}/logs"

log "Replicate data folder: ${_replicate_data_folder}"
log "Replicate logs folder: ${_replicate_logs}"
log "Replicate REST port: ${_replicate_rest_port}"
log "Replicate bin folder: ${_replicate_bin}"

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

# -----------------------------------------------------------------------------
# Resolve optional license and master key inputs.
#
# Preference order for each:
#   1. explicit environment variable value
#   2. default mounted secret file
#
# These values are optional. Startup continues even if they are not provided.
# -----------------------------------------------------------------------------
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

# -----------------------------------------------------------------------------
# Track the background inotify watcher process so it can be stopped cleanly on
# exit or when container termination signals are received.
# -----------------------------------------------------------------------------
_watcher_pid=""

# -----------------------------------------------------------------------------
# Best-effort cleanup for the background log watcher process.
# This prevents orphaned watcher processes during shutdown.
# -----------------------------------------------------------------------------
cleanup() {
    if [[ -n "${_watcher_pid}" ]] && kill -0 "${_watcher_pid}" 2>/dev/null; then
        kill "${_watcher_pid}" 2>/dev/null || true
        wait "${_watcher_pid}" 2>/dev/null || true
    fi
}
trap cleanup SIGTERM SIGINT EXIT

# -----------------------------------------------------------------------------
# Defensive re-check for commands used specifically by log tailing.
# This is redundant with the earlier validation, but keeps the dependency near
# the section that relies on it.
# -----------------------------------------------------------------------------
for cmd in inotifywait tail sed; do
    command -v "${cmd}" >/dev/null 2>&1 || {
        error "missing command: ${cmd}"
        exit 1
    }
done

# -----------------------------------------------------------------------------
# Validate that the configured Replicate binary directory exists.
# -----------------------------------------------------------------------------
if [[ ! -d "${_replicate_bin}" ]]; then
    error "Replicate bin folder not found at ${_replicate_bin}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Ensure the Replicate data directory exists before initialization.
# -----------------------------------------------------------------------------
if [[ ! -d "${_replicate_data_folder}" ]]; then
    log "Creating data folder at ${_replicate_data_folder}"
    mkdir -p "${_replicate_data_folder}"
fi

# -----------------------------------------------------------------------------
# Ensure the configured Replicate service user owns the data directory so
# startup and runtime file operations can succeed.
#
# Note:
#   This assumes the primary group name matches the user name.
# -----------------------------------------------------------------------------
chown -R "${_replicate_user}:${_replicate_user}" "${_replicate_data_folder}"

# -----------------------------------------------------------------------------
# Configure the Replicate admin password before starting the service.
# The shared _replicate_user from common.sh is used for all Replicate commands.
# -----------------------------------------------------------------------------
printf "%s" "${_replicate_admin_password}" | \
    run_as_user "${_replicate_user}" "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" setserverpassword ${_replicate_admin_password} || {
        error "Failed to set admin password"
        exit 1
    }

# -----------------------------------------------------------------------------
# Import the Replicate license when one has been provided.
# License import failure is non-fatal so the container can still start.
# -----------------------------------------------------------------------------
if [[ -n "${_replicate_license}" ]]; then
    run_as_user "${_replicate_user}" "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" importlicense "license_file=${_replicate_license}" || \
        warn "License import failed — continuing without valid license"
fi

# -----------------------------------------------------------------------------
# Import the Replicate master key when one has been provided.
# Master key import failure is non-fatal so the container can still start.
# -----------------------------------------------------------------------------
if [[ -n "${_replicate_master_key}" ]]; then
    printf "%s" "${_replicate_master_key}" | \
        run_as_user "${_replicate_user}" "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" setmasterkey ${_replicate_master_key} || \
        warn "Master key import failed — continuing without master key"
fi

# -----------------------------------------------------------------------------
# Start the Replicate service using the configured data directory and REST port.
# -----------------------------------------------------------------------------
run_as_user "${_replicate_user}" "${_replicate_bin}/repctl.sh" -d "${_replicate_data_folder}" service start "rest_port=${_replicate_rest_port}"

# -----------------------------------------------------------------------------
# Track which log files are already being tailed so duplicate tail processes
# are not created for the same file.
# -----------------------------------------------------------------------------
declare -A _tailed

# -----------------------------------------------------------------------------
# Start tailing a Replicate log file to stdout.
#
# Behaviour:
#   - ignores files matching *__*.log
#   - skips files already being tailed
#   - prefixes each log line with the source file name
# -----------------------------------------------------------------------------
start_tail() {
    local logfile="$1"

    [[ "${logfile}" == *__*.log ]] && return
    [[ -n "${_tailed["$logfile"]+x}" ]] && return
    _tailed["$logfile"]=1

    log "Tailing log file: ${logfile}"
    tail -F "${logfile}" 2>/dev/null | sed -u "s|^|[$(basename "${logfile}")] |" &
}

# -----------------------------------------------------------------------------
# Tail any log files that already exist at startup.
# nullglob avoids passing a literal *.log pattern when no files are present.
# -----------------------------------------------------------------------------
shopt -s nullglob
for logfile in "${_replicate_logs}"/*.log; do
    start_tail "${logfile}"
done
shopt -u nullglob

# -----------------------------------------------------------------------------
# Watch for newly created log files and begin tailing them as they appear.
# The watcher runs in the background and becomes the foreground wait target.
# -----------------------------------------------------------------------------
while read -r file; do
    [[ "${file}" == *.log ]] && start_tail "${_replicate_logs}/${file}"
done < <(inotifywait -m -e create --format '%f' "${_replicate_logs}") &

_watcher_pid=$!

# -----------------------------------------------------------------------------
# Keep the script in the foreground by waiting on the log watcher process.
# This allows the caller to treat this script as the main long-running process.
# -----------------------------------------------------------------------------
wait "${_watcher_pid}"