#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ALLOW_ONLINE_FALLBACK="${ALLOW_ONLINE_FALLBACK:-false}"
MSSQL_VERSION="${MSSQL_VERSION:-18}"

# Base package names
ODBC_PKG="msodbcsql"
TOOLS_PKG="mssql-tools"

# If version is provided, append it
if [[ -n "$MSSQL_VERSION" ]]; then
  ODBC_PKG="${ODBC_PKG}${MSSQL_VERSION}"
  TOOLS_PKG="${TOOLS_PKG}${MSSQL_VERSION}"
fi

echo "Preparing base ODBC deps..."
dnf remove -q -y unixODBC-utf16 unixODBC-utf16-devel || true
dnf install -y unixODBC unixODBC-devel

# Offline-first RPM detection
shopt -s nullglob
local_rpms=(
  "$SCRIPT_DIR"/msodbcsql*.rpm
  "$SCRIPT_DIR"/mssql-tools*.rpm
)
shopt -u nullglob

if (( ${#local_rpms[@]} > 0 )); then
  echo "Installing MSSQL ODBC from local RPMs"
  ACCEPT_EULA=Y dnf install -y "${local_rpms[@]}"
else
  if [[ "$ALLOW_ONLINE_FALLBACK" == "true" ]]; then
    echo "No local RPMs found. Using online fallback."

    curl -fsSL https://packages.microsoft.com/config/rhel/9/prod.repo \
      -o /etc/yum.repos.d/mssql-release.repo

    ACCEPT_EULA=Y dnf install -y "$ODBC_PKG" "$TOOLS_PKG"
  else
    echo "No local RPMs found and online fallback disabled."
    exit 1
  fi
fi

echo "MSSQL ODBC installation complete."
