#!/bin/bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script: entrypoint.sh
# Purpose:
#   Act as the container entrypoint for Qlik Replicate by starting the main
#   service process and coordinating graceful shutdown when termination signals
#   are received.
#
#   This includes:
#     - loading shared helpers from common.sh
#     - validating required helper scripts are present and executable
#     - launching the Replicate startup script as the main child process
#     - trapping SIGTERM/SIGINT and invoking shutdown handling
#
#   This ensures:
#     - predictable container startup behaviour
#     - proper signal handling in PID 1 context
#     - graceful Replicate shutdown before container exit
#     - consistent logging through shared helpers
#
# Requirements:
#   - bash
#   - common.sh in the same scripts directory
#   - start_replicate.sh and shutdown_handler.sh present and executable
#
# Notes:
#   This script is intended to run as the container's foreground entrypoint.
#   It starts the Replicate service in the background, tracks its PID, and
#   waits on that process so container lifecycle follows the main service.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Resolve the directory containing this script so sibling helper scripts can be
# referenced reliably regardless of the current working directory.
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
# Define the helper scripts used for startup and graceful shutdown.
# _main_pid is populated after the service is launched.
# -----------------------------------------------------------------------------
_start_script="${script_dir}/start_replicate.sh"
_shutdown_script="${script_dir}/shutdown_handler.sh"
_main_pid=""

# -----------------------------------------------------------------------------
# Fail early if the startup helper is missing or not executable.
# -----------------------------------------------------------------------------
if [[ ! -x "${_start_script}" ]]; then
    error "start script not found or not executable: ${_start_script}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Fail early if the shutdown helper is missing or not executable.
# -----------------------------------------------------------------------------
if [[ ! -x "${_shutdown_script}" ]]; then
    error "shutdown script not found or not executable: ${_shutdown_script}"
    exit 1
fi

# -----------------------------------------------------------------------------
# Handle container termination signals.
#
# Behaviour:
#   - log receipt of the signal
#   - invoke the shutdown helper to stop Replicate cleanly
#   - if the tracked child process is still running, send SIGTERM and wait
#
# Errors during shutdown are ignored so signal handling can continue to
# completion without masking the termination flow.
# -----------------------------------------------------------------------------
on_term() {
    log "Caught termination signal, shutting down Replicate..."
    "${_shutdown_script}" || true

    if [[ -n "${_main_pid}" ]] && kill -0 "${_main_pid}" 2>/dev/null; then
        kill -TERM "${_main_pid}" 2>/dev/null || true
        wait "${_main_pid}" 2>/dev/null || true
    fi
}

# -----------------------------------------------------------------------------
# Register the termination handler for standard container stop signals.
# -----------------------------------------------------------------------------
trap on_term SIGTERM SIGINT

# -----------------------------------------------------------------------------
# Start the Replicate service via the helper script in the background and
# capture its PID so this entrypoint can forward shutdown and wait on it.
# -----------------------------------------------------------------------------
log "Starting Replicate service..."
"${_start_script}" &
_main_pid=$!

# -----------------------------------------------------------------------------
# Wait for the main child process to exit so container lifetime is tied to the
# Replicate service process.
# -----------------------------------------------------------------------------
wait "${_main_pid}"