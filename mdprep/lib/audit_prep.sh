#!/usr/bin/env bash
# Hazırlık + simülasyon çıktıları denetimi (./md audit)
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"
# shellcheck source=sync_mdp.sh
source "${MDPREP_DIR}/lib/sync_mdp.sh"

AUDIT_REPORT="${AUDIT_REPORT:-${LOG_DIR}/audit_report.txt}"
FIX_MDP="${FIX_MDP:-no}"

_audit_line() {
    local status="$1" msg="$2"
    printf '  %-5s %s\n' "${status}" "${msg}"
    printf '  %-5s %s\n' "${status}" "${msg}" >>"${AUDIT_REPORT}"
}

_audit_file() {
    local f="$1" note="${2:-}"
    if [[ -f "${WORKDIR}/${f}" ]] && [[ -s "${WORKDIR}/${f}" ]]; then
        _audit_line "OK" "${f}  ${note}"
        return 0
    fi
    _audit_line "EKSIK" "${f}  ${note}"
    return 1
}

_audit_grep_group() {
    local grp="$1"
    if grep -qF "[ ${grp} ]" "${INDEX_NDX}" 2>/dev/null; then
        _audit_line "OK" "index: [ ${grp} ]"
        return 0
    fi
    _audit_line "EKSIK" "index: [ ${grp} ] grubu yok"
    return 1
}

_audit_hsd_zn() {
    local gro="${1:-${PROTEIN_GRO:-processed.gro}}"
    [[ -f "${gro}" ]] || return 1
    local resid hsd_ok=0 zn_ok=0
    for resid in ${METAL_HSD_RESIDUES}; do
        if grep -qE "${resid}HSD" "${gro}" 2>/dev/null; then
            hsd_ok=$((hsd_ok + 1))
        else
            _audit_line "UYARI" "HSD resid ${resid} yok (${gro})"
        fi
    done
    [[ "${hsd_ok}" -ge 1 ]] && _audit_line "OK" "HSD (${hsd_ok}/$(echo ${METAL_HSD_RESIDUES} | wc -w)) ${gro}"
    if grep -qE '[[:space:]]'"${METAL_ION_RESNAME}"'[[:space:]]' "${gro}" 2>/dev/null; then
        _audit_line "OK" "Zn (${METAL_ION_RESNAME}) ${gro}"
        zn_ok=1
    else
        _audit_line "UYARI" "Zn (${METAL_ION_RESNAME}) ${gro} içinde bulunamadı"
    fi
    [[ "${zn_ok}" -eq 1 ]]
}

_audit_tc_grps() {
    local mdp="$1"
    [[ -f "${mdp}" ]] || return 1
    if grep -qF "${GRP_PROTEIN_LIG}" "${mdp}" && grep -qF "${GRP_WATER_IONS}" "${mdp}"; then
        _audit_line "OK" "tc-grps ${mdp}: ${GRP_PROTEIN_LIG} / ${GRP_WATER_IONS}"
        return 0
    fi
    _audit_line "UYARI" "tc-grps ${mdp} beklenen gruplarla uyuşmuyor"
    return 1
}

run_audit() {
    local ok=0 fail=0 warn=0
    mkdir -p "$(dirname "${AUDIT_REPORT}")"
    : >"${AUDIT_REPORT}"
    {
        echo "MD Hazırlık Denetimi — $(date -Iseconds 2>/dev/null || date)"
        echo "WORKDIR: ${WORKDIR}"
        echo ""
    } >>"${AUDIT_REPORT}"

    echo ""
    echo "======== DOSYA DENETİMİ ========"
    echo "--- Hazırlık ---" | tee -a "${AUDIT_REPORT}"
    local f
    for f in \
        "protein_prep.pdb:00b" \
        "processed.gro:01" \
        "topol.top:01" \
        "lig.itp:02" \
        "ligand.gro:02" \
        "complex.gro:03" \
        "solv_ions.gro:04" \
        "em.tpr:04 grompp" \
        "index.ndx:05" \
        "posre_lig.itp:05" \
        "run_local_md.sh:06" \
        "check_binding.sh:06"
    do
        local path="${f%%:*}" note="${f#*:}"
        if _audit_file "${path}" "${note}"; then ok=$((ok + 1)); else fail=$((fail + 1)); fi
    done

    echo "" | tee -a "${AUDIT_REPORT}"
    echo "--- Index grupları ---" | tee -a "${AUDIT_REPORT}"
    for f in "${GRP_PROTEIN_LIG}" "${GRP_WATER_IONS}" "Backbone" "${CHECK_LIG_RESNAME}"; do
        _audit_grep_group "${f}" && ok=$((ok + 1)) || fail=$((fail + 1))
    done

    echo "" | tee -a "${AUDIT_REPORT}"
    echo "--- Kimya (HSD / Zn) ---" | tee -a "${AUDIT_REPORT}"
    _audit_hsd_zn "processed.gro" && ok=$((ok + 1)) || warn=$((warn + 1))
    [[ -f em.gro ]] && _audit_hsd_zn "em.gro" >/dev/null && ok=$((ok + 1))

    echo "" | tee -a "${AUDIT_REPORT}"
    echo "--- MDP / config ---" | tee -a "${AUDIT_REPORT}"
    for f in nvt.mdp npt.mdp md.mdp; do
        _audit_tc_grps "${f}" && ok=$((ok + 1)) || warn=$((warn + 1))
    done
    if [[ "${FIX_MDP}" == "yes" ]]; then
        sync_mdp_from_config yes | tee -a "${AUDIT_REPORT}" || true
    else
        sync_mdp_from_config no | tee -a "${AUDIT_REPORT}" || warn=$((warn + 1))
    fi

    if [[ -f em.gro ]] || [[ -f nvt.gro ]]; then
        echo "" | tee -a "${AUDIT_REPORT}"
        echo "--- Simülasyon (varsa) ---" | tee -a "${AUDIT_REPORT}"
        for f in \
            "em.gro:EM" \
            "nvt.gro:NVT" \
            "nvt.cpt:NVT ckpt" \
            "npt.gro:NPT" \
            "npt.cpt:NPT ckpt" \
            "${PROD_DEFFNM}.gro:MD" \
            "${PROD_DEFFNM}.xtc:MD traj"
        do
            local path="${f%%:*}" note="${f#*:}"
            if [[ -f "${path}" ]]; then
                _audit_file "${path}" "${note}" && ok=$((ok + 1))
            fi
        done
    fi

    echo "" >>"${AUDIT_REPORT}"
    echo "Özet: OK≈${ok}  EKSIK=${fail}  UYARI≈${warn}" >>"${AUDIT_REPORT}"
    echo "" | tee -a "${AUDIT_REPORT}"
    echo "Rapor: ${AUDIT_REPORT}" | tee -a "${AUDIT_REPORT}"

    if [[ "${fail}" -eq 0 ]]; then
        log_ok "Denetim tamam — kritik eksik yok"
        return 0
    fi
    log_warn "Denetim: ${fail} kritik eksik — rapora bakın"
    return 1
}

main_audit() {
    case "${1:-}" in
        --fix-mdp) FIX_MDP=yes; shift ;;
        help|-h)
            cat <<EOF
Hazırlık denetimi:

  ./md audit              dosya + index + HSD/Zn + mdp kontrol
  ./md audit --fix-mdp    denetim + config'ten mdp nsteps senkronize

Rapor: ${AUDIT_REPORT}
EOF
            return 0
            ;;
    esac
    run_audit
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_audit "$@"
fi
