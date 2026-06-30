#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALLOW_ONLINE_FALLBACK="${ALLOW_ONLINE_FALLBACK:-false}"
SNOWFLAKE_ODBC_VERSION="${SNOWFLAKE_ODBC_VERSION:-3.17.0}"
DEFAULT_URL="https://sfc-repo.snowflakecomputing.com/odbc/linux/${SNOWFLAKE_ODBC_VERSION}/snowflake-odbc-${SNOWFLAKE_ODBC_VERSION}.x86_64.rpm"
RPM_URL="${SNOWFLAKE_RPM_URL:-$DEFAULT_URL}"

echo "Installing required dependency: unixODBC"
dnf install -y unixODBC
dnf clean all

# Offline-first
shopt -s nullglob
local_rpms=("$SCRIPT_DIR"/snowflake-odbc*.rpm)
shopt -u nullglob

if (( ${#local_rpms[@]} > 0 )); then
  echo "Installing Snowflake ODBC from local RPM(s)"
  dnf install -y "${local_rpms[@]}"
elif [[ "$ALLOW_ONLINE_FALLBACK" == "true" ]]; then
  echo "No local RPM found. Using online fallback."

  echo "Downloading: $RPM_URL"
  curl -fsSL "$RPM_URL" -o /tmp/snowflake-odbc.rpm
  dnf install -y /tmp/snowflake-odbc.rpm
  rm -f /tmp/snowflake-odbc.rpm
else
  echo "No local RPM found and online fallback disabled."
  exit 1
fi

# Validate ODBC registration
if ! odbcinst -q -d | grep -Eiq 'snowflake'; then
  echo "Snowflake ODBC installed but not registered."
  exit 1
fi

echo "Snowflake ODBC installation complete."
