#!/usr/bin/env bash
# index.ndx tc-grps doğrulama ve (gerekirse) complex-index yeniden üretimi
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

NDX_PY="${MDPREP_DIR}/lib/ndx_tools.py"

ndx_has_group() {
    local ndx="$1" grp="$2"
    [[ -f "${ndx}" ]] || return 1
    grep -qF "[ ${grp} ]" "${ndx}" 2>/dev/null
}

ndx_list_groups() {
    local ndx="$1"
    [[ -f "${ndx}" ]] || return 1
    grep -E '^\[.*\]' "${ndx}" | sed -E 's/^\[ *//; s/ *\]$//'
}

read_mdp_tc_grps() {
    local mdp="$1"
    awk '
        /^[[:space:]]*tc-grps[[:space:]]*=/ {
            line = $0
            sub(/;.*/, "", line)
            sub(/^[[:space:]]*tc-grps[[:space:]]*=[[:space:]]*/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            print line
            exit
        }
    ' "${mdp}"
}

verify_index_tc_groups() {
    local ndx="${1:-${INDEX_NDX}}"
    local quiet="${2:-no}"
    local missing=() g

    for g in "${GRP_PROTEIN_LIG}" "${GRP_WATER_IONS}"; do
        if ! ndx_has_group "${ndx}" "${g}"; then
            missing+=("${g}")
        fi
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        [[ "${quiet}" == "yes" ]] || log_ok "index: [ ${GRP_PROTEIN_LIG} ] + [ ${GRP_WATER_IONS} ] OK (${ndx})"
        return 0
    fi

    if [[ "${quiet}" != "yes" ]]; then
        log_err "index.ndx tc-grps grupları eksik: ${missing[*]}"
        log_info "  Beklenen: [ ${GRP_PROTEIN_LIG} ], [ ${GRP_WATER_IONS} ]"
        if [[ -f "${ndx}" ]]; then
            log_info "  Mevcut gruplar (son 12):"
            ndx_list_groups "${ndx}" | tail -12 | while read -r line; do
                log_info "    [ ${line} ]"
            done
        else
            log_info "  Dosya yok: ${ndx}"
        fi
        log_info "  Düzelt: FORCE=1 gmxkit stage index   veya   gmxkit audit --fix-index"
    fi
    return 1
}

verify_mdp_index_tc_groups() {
    local ndx="${1:-${INDEX_NDX}}"
    local quiet="${2:-no}"
    local mdp grps grp issues=0

    for mdp in "${NVT_MDP}" "${NPT_MDP}" "${PROD_MDP}"; do
        [[ -f "${mdp}" ]] || continue
        grps="$(read_mdp_tc_grps "${mdp}")"
        [[ -n "${grps}" ]] || continue
        for grp in ${grps}; do
            if ! ndx_has_group "${ndx}" "${grp}"; then
                issues=$((issues + 1))
                [[ "${quiet}" == "yes" ]] || log_err "${mdp}: tc-grps '${grp}' index.ndx içinde yok"
            fi
        done
    done

    if [[ "${issues}" -eq 0 ]]; then
        [[ "${quiet}" == "yes" ]] || log_ok "MDP tc-grps ↔ index.ndx uyumlu"
        return 0
    fi
    [[ "${quiet}" == "yes" ]] || log_info "  Düzelt: gmxkit audit --fix-index  (index yeniden üret + mdp senkron)"
    return 1
}

verify_index_for_grompp() {
    verify_index_tc_groups "${INDEX_NDX}" no \
        && verify_mdp_index_tc_groups "${INDEX_NDX}" no
}

_index_struct_gro() {
    local gro="${EM_GRO}"
    [[ -f "${gro}" ]] || gro="${SOLV_IONS_GRO}"
    printf '%s' "${gro}"
}

regenerate_complex_index() {
    local struct_gro
    struct_gro="$(_index_struct_gro)"
    require_file "${struct_gro}" "em.gro veya solv_ions.gro (index için yapı)"
    require_file "${LIG_ITP}" "lig.itp"
    require_file "${NDX_PY}" "ndx_tools.py"

    local py lig_ndx_name
    py="$(find_python)" || die "python3 gerekli"
    lig_ndx_name="$("${py}" -c "import sys; sys.path.insert(0,'${MDPREP_DIR}/lib'); from top_tools import read_moleculetype; print(read_moleculetype('${LIG_ITP}'))")"

    log_info "index yeniden üretiliyor: ${struct_gro} (ligand make_ndx: ${lig_ndx_name})"
    [[ -f "${INDEX_NDX}" ]] && backup_file "${INDEX_NDX}"

    run_cmd "${py}" "${NDX_PY}" complex-index --gmx "${GMX}" \
        "${struct_gro}" "${INDEX_NDX}" \
        --lig-resname "${lig_ndx_name}" \
        --grp-pl "${GRP_PROTEIN_LIG}" \
        --grp-wi "${GRP_WATER_IONS}" \
        $([[ "${METAL_ENZYME}" == "yes" ]] && echo "--metal-resname ${METAL_ION_RESNAME}") \
        || die "complex-index başarısız"

    verify_index_tc_groups "${INDEX_NDX}" no || die "index doğrulama başarısız"
    log_ok "index.ndx güncellendi (${GRP_PROTEIN_LIG}, ${GRP_WATER_IONS})"
}

sync_mdp_tc_grps() {
    local mdp
    for mdp in "${NVT_MDP}" "${NPT_MDP}" "${PROD_MDP}"; do
        [[ -f "${mdp}" ]] || continue
        sed -i "s/tc-grps[[:space:]]*=.*/tc-grps                 = ${GRP_PROTEIN_LIG} ${GRP_WATER_IONS}/" "${mdp}" 2>/dev/null || true
    done
    log_ok "MDP tc-grps senkronize: ${GRP_PROTEIN_LIG} / ${GRP_WATER_IONS}"
}

fix_index_and_mdp() {
    is_done "04_solvate_ions" || die "Önce solvasyon (stage 04) tamamlanmalı"
    regenerate_complex_index
    sync_mdp_tc_grps
    if is_done "05_index_posre"; then
        log_info "Checkpoint 05_index_posre zaten var (index güncellendi)."
    else
        mark_done "05_index_posre"
    fi
}

main_verify_index() {
    case "${1:-}" in
        --check|-c)
            verify_index_for_grompp
            ;;
        --regenerate|--fix)
            fix_index_and_mdp
            ;;
        --help|-h)
            cat <<EOF
index.ndx tc-grps doğrulama:

  $(basename "$0") --check          index + mdp tc-grps kontrolü (grompp öncesi)
  $(basename "$0") --regenerate     complex-index yeniden üret + mdp tc-grps senkron

gmxkit:  gmxkit audit --fix-index
EOF
            return 0
            ;;
        *)
            echo "Kullanım: $(basename "$0") --check | --regenerate" >&2
            return 1
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_verify_index "$@"
fi
