#!/bin/bash
set -euo pipefail

if [[ -z "${ReplicateDataFolder:-}" || -z "${ReplicateAdminPassword:-}" || -z "${ReplicateRestPort:-}" ]]; then
    echo "Usage: start-replicate.sh <Data folder> <Admin password> <Rest port> [<license file>]"
    exit 1
fi

_ReplicateBin="/opt/attunity/replicate/bin"
_ReplicateLogs="${ReplicateDataFolder}/logs"

if [ ! -d "${_ReplicateBin}" ]; then
  echo "Error: Replicate bin folder not found at ${_ReplicateBin}"
  exit 1
fi

if [ ! -d "${ReplicateDataFolder}" ]; then
  echo "Creating data folder at ${ReplicateDataFolder} and granting ownership to user attunity"
  mkdir -p "${ReplicateDataFolder}"
fi

chown -R attunity:attunity "${ReplicateDataFolder}"

echo "Setting Replicate admin password"
su attunity -c "${_ReplicateBin}/repctl.sh -d ${ReplicateDataFolder} setserverpassword ${ReplicateAdminPassword}"

if [ ! -z "${ReplicateLicense:-}" ]; then
  echo "Importing Replicate license from ${ReplicateLicense}"
	su attunity -c "${_ReplicateBin}/repctl.sh -d ${ReplicateDataFolder} importlicense license_file=${ReplicateLicense}"
fi

# Run Attunity Replicate
echo "Starting Replicate service on port ${ReplicateRestPort}"
su attunity -c "${_ReplicateBin}/repctl.sh -d ${ReplicateDataFolder} service start rest_port=${ReplicateRestPort}"

declare -A tailed
start_tail() {
    local logfile="$1"

    # Skip archived logs
    if [[ "$logfile" == *__*.log ]]; then
        return
    fi

    # Skip if already tailed
    if [[ -n "${tailed["$logfile"]+x}" ]]; then
        return
    fi
    tailed["$logfile"]=1

    echo "Tailing log file: $logfile"
    tail -F "$logfile" 2>/dev/null | sed -u "s|^|$(basename "$logfile"): |" &
}

# Tail all existing active logs
for logfile in "$_ReplicateLogs"/*.log; do
    start_tail "$logfile"
done

# Watch for new log files
inotifywait -m -e create "$_ReplicateLogs" |
while read -r path action file; do
    if [[ "$file" == *.log ]]; then
        start_tail "$_ReplicateLogs/$file"
    fi
done &

# Keep container alive forever
wait -n