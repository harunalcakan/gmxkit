#!/usr/bin/env bash
# GmxKit — proje kökünden tek komut (./md)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/mdprep/md.sh" "$@"
