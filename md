#!/usr/bin/env bash
# GmxKit — proje kökünden tek komut (./md)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GMXKIT_HOME="${ROOT}"
exec bash "${ROOT}/mdprep/md.sh" "$@"
