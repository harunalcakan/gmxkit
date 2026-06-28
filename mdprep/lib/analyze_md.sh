#!/usr/bin/env bash
# =============================================================================
# analyze_md.sh — PBC düzeltmeli analiz (tek tarif, soru sormadan)
#
#   ./md analyze              tüm analizler (production MD varsa)
#   ./md analyze pbc          sadece md_pbc.xtc
#   ./md analyze rmsd|rmsf|rg|sasa|eq|binding|report
#
# Tarif (CA + ligand):
#   trjconv -pbc mol -ur compact -center Protein -fit Backbone
#   ligand RMSD: Backbone fit (trjconv) + 2Q38 RMSD (-fit none)
#   protein RMSD: Backbone / Backbone
# =============================================================================
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

NDX_PY="${MDPREP_DIR}/lib/ndx_tools.py"
BIND_SH="${MDPREP_DIR}/lib/check_binding.sh"

ANALYSIS_OUT_DIR="${ANALYSIS_OUT_DIR:-mdprep/logs/analysis}"
ANALYSIS_PBC_XTC="${ANALYSIS_PBC_XTC:-md_pbc.xtc}"
ANALYSIS_FIT_GROUP="${ANALYSIS_FIT_GROUP:-Backbone}"
ANALYSIS_CENTER_GROUP="${ANALYSIS_CENTER_GROUP:-Protein}"
ANALYSIS_LIG_GROUP="${ANALYSIS_LIG_GROUP:-${CHECK_LIG_RESNAME:-2Q38}}"
ANALYSIS_RMSD_BB_GROUP="${ANALYSIS_RMSD_BB_GROUP:-Backbone}"
ANALYSIS_RMSF_GROUP="${ANALYSIS_RMSF_GROUP:-C-alpha}"
ANALYSIS_RG_GROUP="${ANALYSIS_RG_GROUP:-Protein}"
ANALYSIS_SASA_PROTEIN="${ANALYSIS_SASA_PROTEIN:-Protein}"
ANALYSIS_SASA_LIG="${ANALYSIS_SASA_LIG:-${CHECK_LIG_RESNAME:-2Q38}}"

REPORT="${ANALYSIS_OUT_DIR}/ANALYSIS_REPORT.txt"
PY="$(find_python)" || die "python3 gerekli"

_ndx_nr() {
    "${PY}" "${NDX_PY}" group-num "${INDEX_NDX}" "$@" \
        || die "Index grubu yok: $* (${INDEX_NDX})"
}

_xvg_last() {
    awk '!/^[@#]/ && NF { v = $NF + 0 } END { printf "%.4f\n", v + 0 }' "$1"
}

_xvg_mean_last() {
    awk '!/^[@#]/ && NF { s += $NF; n++ } END { if (n) printf "%.4f\n", s/n; else print "nan" }' "$1"
}

_traj_nframes() {
    ${GMX} check -f "$1" 2>&1 | awk '/^Coords/ { print $2; exit }'
}

_require_md() {
    require_file "${INDEX_NDX}" "index.ndx"
    require_file "${MD_TPR}" "production tpr (${MD_TPR})"
    local xtc="${PROD_DEFFNM}.xtc"
    require_file "${xtc}" "production xtc (${xtc})"
}

_make_pbc_traj() {
    local tpr="$1" xtc="$2" out="$3"
    local step1="${ANALYSIS_OUT_DIR}/md_nopbc.xtc"
    if [[ -f "${out}" && "${out}" -nt "${xtc}" && ( ! -f "${step1}" || "${out}" -nt "${step1}" ) ]]; then
        log_info "PBC traj güncel: ${out}"
        return 0
    fi
    local g_out g_ctr g_fit
    g_out="$(_ndx_nr System)"
    g_ctr="$(_ndx_nr "${ANALYSIS_CENTER_GROUP}" Protein)"
    g_fit="$(_ndx_nr "${ANALYSIS_FIT_GROUP}" Backbone "C-alpha")"
    mkdir -p "${ANALYSIS_OUT_DIR}"

    log_info "trjconv 1/2 PBC (center=${ANALYSIS_CENTER_GROUP}) → ${step1}"
    local gmx_log1="${LOG_DIR}/gmx_trjconv_pbc1_$(date +%H%M%S).log"
    # Sıra: (1) center grubu  (2) çıktı = System
    printf '%s\n%s\n' "${g_ctr}" "${g_out}" \
        | ${GMX} trjconv -s "${tpr}" -f "${xtc}" -o "${step1}" -n "${INDEX_NDX}" \
            -pbc mol -ur compact -center >"${gmx_log1}" 2>&1 \
        || die "trjconv PBC adımı başarısız — ${gmx_log1}"

    log_info "trjconv 2/2 fit (${ANALYSIS_FIT_GROUP}) → ${out}"
    local gmx_log2="${LOG_DIR}/gmx_trjconv_pbc2_$(date +%H%M%S).log"
    # Sıra: (1) fit grubu  (2) çıktı = System
    printf '%s\n%s\n' "${g_fit}" "${g_out}" \
        | ${GMX} trjconv -s "${tpr}" -f "${step1}" -o "${out}" -n "${INDEX_NDX}" \
            -fit rot+trans >"${gmx_log2}" 2>&1 \
        || die "trjconv fit adımı başarısız — ${gmx_log2}"

    [[ -f "${out}" ]] || die "trjconv çıktı yok: ${out}"
    local nf
    nf="$(_traj_nframes "${out}")"
    log_ok "PBC traj: ${out} (${nf} frame)"
    if [[ "${nf:-0}" -lt 10 ]]; then
        log_warn "Trajektori çok kısa (${nf} frame) — RMSD/RMSF anlamlı değil; uzun MD sonrası tekrarlayın."
        [[ -f "${REPORT}" ]] && echo "  UYARI: traj ${nf} frame — analiz için ≥10 frame önerilir" >>"${REPORT}"
    fi
}

_analyze_rmsd() {
    local traj_pbc="$1"
    local traj_nopbc="${ANALYSIS_OUT_DIR}/md_nopbc.xtc"
    [[ -f "${traj_nopbc}" ]] || die "PBC ara traj yok: ${traj_nopbc}"
    local g_bb g_lig
    g_bb="$(_ndx_nr "${ANALYSIS_RMSD_BB_GROUP}" Backbone "C-alpha")"
    g_lig="$(_ndx_nr "${ANALYSIS_LIG_GROUP}" "${CHECK_LIG_RESNAME}")"
    local out_bb="${ANALYSIS_OUT_DIR}/rmsd_backbone.xvg"
    local out_lig="${ANALYSIS_OUT_DIR}/rmsd_ligand.xvg"
    log_info "RMSD protein (fit+meas ${ANALYSIS_RMSD_BB_GROUP} on nopbc traj)"
    printf '%s\n%s\n' "${g_bb}" "${g_bb}" \
        | ${GMX} rms -s "${MD_TPR}" -f "${traj_nopbc}" -n "${INDEX_NDX}" -o "${out_bb}" \
            -xvg none >/dev/null 2>&1 || die "backbone RMSD başarısız"
    log_info "RMSD ligand (fit ${ANALYSIS_FIT_GROUP}, meas ${ANALYSIS_LIG_GROUP})"
    printf '%s\n%s\n' "${g_bb}" "${g_lig}" \
        | ${GMX} rms -s "${MD_TPR}" -f "${traj_nopbc}" -n "${INDEX_NDX}" -o "${out_lig}" \
            -xvg none >/dev/null 2>&1 || die "ligand RMSD başarısız"
    log_ok "RMSD: ${out_bb}, ${out_lig}"
    echo "  backbone RMSD (son): $(_xvg_last "${out_bb}") nm" >>"${REPORT}"
    echo "  ligand RMSD (son):   $(_xvg_last "${out_lig}") nm" >>"${REPORT}"
}

_analyze_rmsf() {
    local traj="$1"
    local g_calc
    g_calc="$(_ndx_nr "${ANALYSIS_RMSF_GROUP}" "C-alpha" Backbone)"
    local out="${ANALYSIS_OUT_DIR}/rmsf.xvg"
    printf '%s\n' "${g_calc}" \
        | ${GMX} rmsf -s "${MD_TPR}" -f "${traj}" -n "${INDEX_NDX}" -o "${out}" -xvg none \
        >/dev/null 2>&1 || die "RMSF başarısız"
    log_ok "RMSF: ${out}"
    echo "  RMSF (${ANALYSIS_RMSF_GROUP}): ${out}" >>"${REPORT}"
}

_analyze_rg() {
    local traj="$1"
    local g="$(_ndx_nr "${ANALYSIS_RG_GROUP}" Protein)"
    local out="${ANALYSIS_OUT_DIR}/rg.xvg"
    printf '%s\n' "${g}" \
        | ${GMX} gyrate -s "${MD_TPR}" -f "${traj}" -n "${INDEX_NDX}" -o "${out}" -xvg none \
        >/dev/null 2>&1 || die "Rg başarısız"
    log_ok "Rg: ${out}"
    echo "  Rg (${ANALYSIS_RG_GROUP}, ort son 10%): $(_xvg_mean_last "${out}") nm" >>"${REPORT}"
}

_analyze_sasa() {
    local traj="$1"
    local g_prot g_lig
    g_prot="$(_ndx_nr "${ANALYSIS_SASA_PROTEIN}" Protein)"
    g_lig="$(_ndx_nr "${ANALYSIS_SASA_LIG}" "${CHECK_LIG_RESNAME}")"
    local out_p="${ANALYSIS_OUT_DIR}/sasa_protein.xvg"
    local out_l="${ANALYSIS_OUT_DIR}/sasa_ligand.xvg"
    printf '%s\n' "${g_prot}" \
        | ${GMX} sasa -s "${MD_TPR}" -f "${traj}" -n "${INDEX_NDX}" -o "${out_p}" -xvg none \
        >/dev/null 2>&1 || die "SASA protein başarısız"
    printf '%s\n' "${g_lig}" \
        | ${GMX} sasa -s "${MD_TPR}" -f "${traj}" -n "${INDEX_NDX}" -o "${out_l}" -xvg none \
        >/dev/null 2>&1 || die "SASA ligand başarısız"
    log_ok "SASA: ${out_p}, ${out_l}"
    echo "  SASA protein (son): $(_xvg_last "${out_p}") nm^2" >>"${REPORT}"
    echo "  SASA ligand (son):  $(_xvg_last "${out_l}") nm^2" >>"${REPORT}"
}

_analyze_equilibration() {
    echo "" >>"${REPORT}"
    echo "--- Dengeleme QC ---" >>"${REPORT}"
    local f out
    if [[ -f "${NVT_DEFFNM}.edr" ]]; then
        out="${ANALYSIS_OUT_DIR}/nvt_temperature.xvg"
        echo "Temperature" | ${GMX} energy -f "${NVT_DEFFNM}.edr" -o "${out}" -xvg none >/dev/null 2>&1 \
            && echo "  NVT T (son): $(_xvg_last "${out}") K" >>"${REPORT}"
    fi
    if [[ -f "${NPT_DEFFNM}.edr" ]]; then
        out="${ANALYSIS_OUT_DIR}/npt_density.xvg"
        echo "Density" | ${GMX} energy -f "${NPT_DEFFNM}.edr" -o "${out}" -xvg none >/dev/null 2>&1 \
            && echo "  NPT density (son): $(_xvg_last "${out}") kg/m^3" >>"${REPORT}"
        out="${ANALYSIS_OUT_DIR}/npt_pressure.xvg"
        echo "Pressure" | ${GMX} energy -f "${NPT_DEFFNM}.edr" -o "${out}" -xvg none >/dev/null 2>&1 \
            && echo "  NPT pressure (ort son): $(_xvg_mean_last "${out}") bar" >>"${REPORT}"
    fi
}

_analyze_binding() {
    echo "" >>"${REPORT}"
    echo "--- Binding (PBC traj) ---" >>"${REPORT}"
    local traj="${WORKDIR}/${ANALYSIS_PBC_XTC}"
    [[ -f "${traj}" ]] || traj="${ANALYSIS_OUT_DIR}/md_nopbc.xtc"
    CHECK_TRAJ="${traj}" CHECK_INDEX="${INDEX_NDX}" \
        bash "${BIND_SH}" md 2>&1 | tee -a "${REPORT}" || true
}

analyze_all() {
    _require_md
    mkdir -p "${ANALYSIS_OUT_DIR}"
    : >"${REPORT}"
    {
        echo "MD Analiz Raporu — $(date -Iseconds 2>/dev/null || date)"
        echo "WORKDIR: ${WORKDIR}"
        echo "PBC tarif: trjconv (1) mol+center ${ANALYSIS_CENTER_GROUP}; (2) fit ${ANALYSIS_FIT_GROUP} → ${ANALYSIS_PBC_XTC}"
        echo ""
    } >>"${REPORT}"

    local xtc="${PROD_DEFFNM}.xtc"
    local pbc="${WORKDIR}/${ANALYSIS_PBC_XTC}"
    _make_pbc_traj "${MD_TPR}" "${xtc}" "${pbc}"

    echo "--- RMSD ---" >>"${REPORT}"
    _analyze_rmsd "${pbc}"
    _analyze_rmsf "${pbc}"
    _analyze_rg "${pbc}"
    echo "" >>"${REPORT}"
    echo "--- SASA ---" >>"${REPORT}"
    _analyze_sasa "${pbc}"
    _analyze_equilibration
    if [[ "${ANALYSIS_USE_PBC_FOR_BINDING:-yes}" == "yes" ]]; then
        _analyze_binding
    fi

    echo "" >>"${REPORT}"
    echo "Çıktılar: ${ANALYSIS_OUT_DIR}/" >>"${REPORT}"
    log_ok "Analiz tamam — ${REPORT}"
    echo ""
    cat "${REPORT}"
}

usage_analyze() {
    cat <<EOF
Analiz (PBC + RMSD/RMSF/Rg/SASA):

  ./md analyze           hepsi
  ./md analyze pbc       md_pbc.xtc üret
  ./md analyze rmsd      backbone + ligand RMSD
  ./md analyze report    raporu göster

Grup tarifi: config.sh → ANALYSIS_* (Backbone fit, Protein center, 2Q38 ligand)
EOF
}

main_analyze() {
    local sub="${1:-all}"
    shift || true
    case "${sub}" in
        all|"") analyze_all ;;
        pbc)
            _require_md
            mkdir -p "${ANALYSIS_OUT_DIR}"
            _make_pbc_traj "${MD_TPR}" "${PROD_DEFFNM}.xtc" "${WORKDIR}/${ANALYSIS_PBC_XTC}"
            ;;
        rmsd)
            _require_md
            mkdir -p "${ANALYSIS_OUT_DIR}"
            : >"${REPORT}"
            _make_pbc_traj "${MD_TPR}" "${PROD_DEFFNM}.xtc" "${WORKDIR}/${ANALYSIS_PBC_XTC}"
            _analyze_rmsd "${WORKDIR}/${ANALYSIS_PBC_XTC}"
            ;;
        rmsf|rg|sasa|eq|binding) analyze_all ;;  # basit: all içinden ilgili kısım yeter
        report)
            [[ -f "${REPORT}" ]] && cat "${REPORT}" || die "Rapor yok — önce: ./md analyze"
            ;;
        help|-h) usage_analyze ;;
        *) die "Bilinmeyen: analyze ${sub}. ./md analyze help" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_analyze "$@"
fi
