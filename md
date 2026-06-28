#!/usr/bin/env bash
# GROMACS MD Orkestratör — proje kökünden tek komut
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/mdprep/md.sh" "$@"
