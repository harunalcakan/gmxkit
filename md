#!/usr/bin/env bash
# GmxKit — alias for ./gmxkit (same launcher)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GMXKIT_HOME="${ROOT}"
exec bash "${ROOT}/mdprep/md.sh" "$@"
