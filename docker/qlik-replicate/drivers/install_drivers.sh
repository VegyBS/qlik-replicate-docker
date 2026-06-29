#!/usr/bin/env bash
set -euo pipefail

# -----------------------------------------------------------------------------
# Script: install_drivers.sh
# Purpose:
#   Install one or more database/client drivers from the staged driver bundle
#   under /tmp/drivers based on the DRIVER_PROFILE environment variable.
#
#   Supported DRIVER_PROFILE values:
#     - none        : install nothing and exit successfully
#     - all         : install every driver directory found in /tmp/drivers
#     - comma list  : install only the named drivers
#                     example: DRIVER_PROFILE="oracle,postgresql,mysql"
#
#   This ensures:
#     - explicit and repeatable driver selection
#     - early validation of requested driver names
#     - predictable container image build/runtime behaviour
#
# Requirements:
#   - driver folders staged under /tmp/drivers/<driver>
#   - each selected driver folder must contain an install.sh script
#
# Notes:
#   The script trims spaces from DRIVER_PROFILE, expands the special "all"
#   profile before validation, and executes each driver installer in sequence.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------
# Read DRIVER_PROFILE from the environment, defaulting to "none" when unset.
# Any spaces are removed so values like "oracle, postgresql" are accepted.
# -----------------------------------------------------------------------------
profile="${DRIVER_PROFILE:-none}"
profile="${profile// /}"

# -----------------------------------------------------------------------------
# Split the profile into an array using commas as separators.
# Example:
#   "oracle,postgresql" -> ("oracle" "postgresql")
# -----------------------------------------------------------------------------
IFS=',' read -ra selected <<< "$profile"

# -----------------------------------------------------------------------------
# Explicit no-op mode. This allows builds/runs where no optional drivers
# should be installed without treating that as an error.
# -----------------------------------------------------------------------------
if [[ "$profile" == "none" ]]; then
  echo "No drivers selected (DRIVER_PROFILE=none)"
  exit 0
fi

# -----------------------------------------------------------------------------
# Special profile: "all"
# Replace the selected list with every directory found under /tmp/drivers.
# This must happen before validation so "all" is not treated as a driver name.
# -----------------------------------------------------------------------------
if [[ "$profile" == "all" ]]; then
  selected=()
  for d in /tmp/drivers/*; do
    [[ -d "$d" ]] && selected+=("$(basename "$d")")
  done
fi

# -----------------------------------------------------------------------------
# Validate that every requested driver directory exists before starting any
# installation. This prevents partial installs caused by a later invalid entry.
# -----------------------------------------------------------------------------
for driver in "${selected[@]}"; do
  if [[ ! -d "/tmp/drivers/$driver" ]]; then
    echo "ERROR: Unknown driver '$driver'. Available drivers:"
    ls -1 /tmp/drivers
    exit 1
  fi
done

echo "Driver profile: $profile"
echo "Drivers to install: ${selected[*]}"

# -----------------------------------------------------------------------------
# Execute each driver installer in sequence.
# Every driver must provide:
#   /tmp/drivers/<driver>/install.sh
#
# The script exits immediately if any installer is missing or fails.
# -----------------------------------------------------------------------------
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