#!/bin/bash
set -euo pipefail

_ReplicateBin="/opt/attunity/replicate/bin"
_StartScript="/opt/attunity/replicate/bin/start_replicate.sh"
_ShutdownScript="/opt/attunity/replicate/bin/shutdown_handler.sh"
_MainPid=""

on_term() {
    echo "[entrypoint] Caught termination signal, shutting down Replicate..."
    "${_ShutdownScript}" || true

    if [[ -n "${_MainPid}" ]] && kill -0 "${_MainPid}" 2>/dev/null; then
        kill -TERM "${_MainPid}" 2>/dev/null || true
        wait "${_MainPid}" 2>/dev/null || true
    fi
}

trap on_term SIGTERM SIGINT

"${_StartScript}" &
_MainPid=$!

wait "${_MainPid}"