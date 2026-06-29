#!/usr/bin/env bash
# Quick regression: prep menu numbers 2-9 → expected stage short codes
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${MDPREP_DIR}/lib/common.sh"
# shellcheck source=lib/stages.sh
source "${MDPREP_DIR}/lib/stages.sh"

stages_init

expected=( check metal protein ligand complex solvate index scripts )
fail=0

for n in $(seq 2 9); do
    idx=$((n - 2))
    got="$(stage_short_for "$(resolve_stage_name "${n}")")"
    want="${expected[$idx]}"
    if [[ "${got}" != "${want}" ]]; then
        echo "FAIL menu #${n}: got '${got}', want '${want}'" >&2
        fail=$((fail + 1))
    else
        echo "OK  #${n} → ${got}"
    fi
done

for pair in check:00_check_env protein:01_protein ligand:02_ligand 5:02_ligand; do
    tok="${pair%%:*}"
    want="${pair#*:}"
    got="$(resolve_stage_name "${tok}")"
    if [[ "${got}" != "${want}" ]]; then
        echo "FAIL token '${tok}': got '${got}', want '${want}'" >&2
        fail=$((fail + 1))
    else
        echo "OK  ${tok} → ${got}"
    fi
done

exit "${fail}"
