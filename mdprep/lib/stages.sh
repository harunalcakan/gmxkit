#!/usr/bin/env bash
# Central prep stage list + short names (check, protein, ligand, …)
# shellcheck shell=bash

stages_init() {
    if [[ "${RUN_TARGET:-local}" == "truba" ]]; then
        STAGE_06_NAME="06_truba_pack"
        STAGE_06_SHORT="slurm"
    else
        STAGE_06_NAME="06_local_md"
        STAGE_06_SHORT="scripts"
    fi

    STAGES=(
        "00_check_env"
        "00b_prepare_metallo"
        "01_protein"
        "02_ligand"
        "03_complex"
        "04_solvate_ions"
        "05_index_posre"
        "${STAGE_06_NAME}"
    )

    STAGE_SHORTS=(
        "check"
        "metal"
        "protein"
        "ligand"
        "complex"
        "solvate"
        "index"
        "${STAGE_06_SHORT}"
    )

    STAGE_LEGACY_IDS=( "00" "00b" "01" "02" "03" "04" "05" "06" )
}

# Resolve CLI/menu token → full stage script basename (e.g. 01_protein)
# Accepts: menu number 1–8, legacy 00/01/00b, short name, prefix match
resolve_stage_name() {
    local target="${1:-}"
    local i n="${#STAGES[@]}"

    [[ -n "${target}" ]] || return 1
    stages_init 2>/dev/null || true

    if [[ "${target}" =~ ^[1-8]$ ]]; then
        echo "${STAGES[$((target - 1))]}"
        return 0
    fi

    target="${target,,}"

    for i in $(seq 0 $((n - 1))); do
        [[ "${STAGE_SHORTS[$i]}" == "${target}" ]] && { echo "${STAGES[$i]}"; return 0; }
    done

    case "${target}" in
        env)     echo "00_check_env"; return 0 ;;
        prot)    echo "01_protein"; return 0 ;;
        lig)     echo "02_ligand"; return 0 ;;
        cx|cmp)  echo "03_complex"; return 0 ;;
        solv|box) echo "04_solvate_ions"; return 0 ;;
        idx)     echo "05_index_posre"; return 0 ;;
        run)     echo "${STAGE_06_NAME:-06_local_md}"; return 0 ;;
    esac

    for i in "${STAGES[@]}"; do
        [[ "${i}" == "${target}"* ]] && { echo "${i}"; return 0; }
    done

    if [[ "${target}" == "06_truba" || "${target}" == "slurm" ]]; then
        echo "06_truba_pack"
        return 0
    fi

    return 1
}

stage_short_for() {
    local name="$1"
    local i
    stages_init 2>/dev/null || true
    for i in "${!STAGES[@]}"; do
        [[ "${STAGES[$i]}" == "${name}" ]] && { echo "${STAGE_SHORTS[$i]}"; return 0; }
    done
    echo "${name}"
}

stage_menu_number_for() {
    local name="$1"
    local i
    stages_init 2>/dev/null || true
    for i in "${!STAGES[@]}"; do
        [[ "${STAGES[$i]}" == "${name}" ]] && { echo "$((i + 1))"; return 0; }
    done
    echo "?"
}

stages_usage_line() {
    stages_init 2>/dev/null || true
    local parts=() i
    for i in "${!STAGE_SHORTS[@]}"; do
        parts+=("${STAGE_SHORTS[$i]}")
    done
    local IFS=' | '
    echo "${parts[*]}"
}
