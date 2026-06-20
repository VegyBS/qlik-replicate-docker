#!/bin/bash
# Expect four parameters:
#    1. Data folder
#    2. Admin password
#    3. Rest port
#    4. license file, or empty to indicate that no license needs to be imported.
# Create data folder and grant user attunity ownership of it

if [ -z $ReplicateDataFolder ] || [ -z $ReplicateAdminPassword ] || [ -z $ReplicateRestPort ]; then
  echo "Usage: start-replicate.sh <Data folder> <Admin password> <Rest port> [<license file>]"
  exit 1
fi

_ReplicateDataFolder="$1"
_ReplicateAdminPassword="$2"
_ReplicateRestPort="$3"
_ReplicateLicense="$4"
_ReplicateBin="/opt/attunity/replicate/bin"
_ReplicateLogs="${_ReplicateDataFolder}/logs"

if [ ! -d "${_ReplicateBin}" ]; then
  echo "Error: Replicate bin folder not found at ${_ReplicateBin}"
  exit 1
fi

if [ ! -d "${_ReplicateDataFolder}" ]; then
  echo "Creating data folder at ${_ReplicateDataFolder} and granting ownership to user attunity"
  mkdir -p "${_ReplicateDataFolder}"
  chown attunity:attunity "${_ReplicateDataFolder}"
fi

echo "Setting Replicate admin password"
su attunity -c "${_ReplicateBin}/repctl.sh -d ${_ReplicateDataFolder} setserverpassword ${_ReplicateAdminPassword}" >> /dev/null 2>&1
if [ ! -z "${_ReplicateLicense}" ]; then
  echo "Importing Replicate license from ${_ReplicateLicense}"
	su attunity -c "${_ReplicateBin}/repctl.sh -d ${_ReplicateDataFolder} importlicense license_file=${_ReplicateLicense}" >> /dev/null 2>&1
fi

# Run Attunity Replicate
echo "Starting Replicate service on port ${_ReplicateRestPort}"
su attunity -c "${_ReplicateBin}/repctl.sh -d ${_ReplicateDataFolder} service start rest_port=${_ReplicateRestPort}" >> /dev/null 2>&1

declare -A tailed
start_tail() {
    local logfile="$1"

    # Skip archived logs
    if [[ "$logfile" == *__*.log ]]; then
        return
    fi

    # Skip if already tailed
    if [[ ${tailed["$logfile"]} ]]; then
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