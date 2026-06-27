#!/usr/bin/env bash
set -euo pipefail

profile="${DRIVER_PROFILE:-none}"
profile="${profile// /}"

IFS=',' read -ra selected <<< "$profile"

if [[ "$profile" == "none" ]]; then
  echo "No drivers selected (DRIVER_PROFILE=none)"
  exit 0
fi

for driver in "${selected[@]}"; do
  if [[ ! -d "/tmp/drivers/$driver" ]]; then
    echo "ERROR: Unknown driver '$driver'. Available drivers:"
    ls -1 /tmp/drivers
    exit 1
  fi
done

if [[ "$profile" == "all" ]]; then
  selected=()
  for d in /tmp/drivers/*; do
    [[ -d "$d" ]] && selected+=("$(basename "$d")")
  done
fi

echo "Driver profile: $profile"
echo "Drivers to install: ${selected[*]}"

for driver in "${selected[@]}"; do
  script="/tmp/drivers/$driver/install.sh"

  if [[ ! -f "$script" ]]; then
    echo "ERROR: Missing installer: $script"
    exit 1
  fi

  echo "Installing driver: $driver"
  bash "$script"
done

echo "Driver installation complete."
