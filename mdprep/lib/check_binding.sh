#!/usr/bin/env bash
# Ligand–aktif site bağ kontrolü (Zn, HSD, ligand RMSD) — VMD gerekmez
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${MDPREP_DIR}/config.sh"

WORKDIR="${WORKDIR:-$(cd "${MDPREP_DIR}/.." && pwd)}"
cd "${WORKDIR}"

GMX="${GMX:-gmx}"
CHECK_BINDING="${CHECK_BINDING:-yes}"
CHECK_BINDING_STRICT="${CHECK_BINDING_STRICT:-no}"
CHECK_LIG_RESNAME="${CHECK_LIG_RESNAME:-2Q38}"
CHECK_REF_TPR="${CHECK_REF_TPR:-${EM_TPR:-em.tpr}}"
CHECK_INDEX="${CHECK_INDEX:-${INDEX_NDX:-index.ndx}}"
CHECK_OUT_DIR="${CHECK_OUT_DIR:-mdprep/logs/binding_checks}"

# Eşikler (nm)
CHECK_ZN_LIG_WARN="${CHECK_ZN_LIG_WARN:-0.35}"
CHECK_ZN_LIG_FAIL="${CHECK_ZN_LIG_FAIL:-0.50}"
CHECK_HSD_LIG_WARN="${CHECK_HSD_LIG_WARN:-0.40}"
CHECK_HSD_LIG_FAIL="${CHECK_HSD_LIG_FAIL:-0.55}"
CHECK_LIG_RMSD_WARN="${CHECK_LIG_RMSD_WARN:-0.25}"
CHECK_LIG_RMSD_FAIL="${CHECK_LIG_RMSD_FAIL:-0.40}"

_warns=0
_fails=0

_cb_log()  { printf '[binding] %s\n' "$*"; }
_cb_warn() { _warns=$((_warns + 1)); printf '[binding][UYARI] %s\n' "$*" >&2; }
_cb_fail() { _fails=$((_fails + 1)); printf '[binding][HATA] %s\n' "$*" >&2; }

ndx_group_num() {
    local want="$1" ndx="$2"
    awk -v want="$want" '
        /^\[/ {
            line = $0
            gsub(/[\[\]]/, "", line)
            gsub(/^[ \t]+|[ \t]+$/, "", line)
            if (line == want) { print idx; exit }
            idx++
        }
    ' "${ndx}"
}

xvg_max() {
    awk '!/^[@#]/ && NF { v = $NF + 0; if (v > max) max = v } END { printf "%.4f\n", max + 0 }' "$1"
}

xvg_last() {
    awk '!/^[@#]/ && NF { v = $NF + 0 } END { printf "%.4f\n", v + 0 }' "$1"
}

_compare() {
    local label="$1" value="$2" warn="$3" fail="$4" unit="${5:-nm}"
    _cb_log "${label}: ${value} ${unit} (uyarı>${warn}, ciddi>${fail})"
    if awk -v v="$value" -v w="$warn" -v f="$fail" 'BEGIN {
        if (v+0 >= f+0) exit 2
        else if (v+0 >= w+0) exit 1
        else exit 0
    }'; then
        return 0
    fi
    local rc=$?
    if [[ ${rc} -eq 2 ]]; then
        _cb_fail "${label} eşiği aşıldı (${value} ${unit} >= ${fail})"
    else
        _cb_warn "${label} uyarı aralığında (${value} ${unit} >= ${warn})"
    fi
}

_mindist_groups() {
    local tpr="$1" traj="$2" ndx="$3" g1="$4" g2="$5" out="$6"
    local n1 n2
    n1="$(ndx_group_num "${g1}" "${ndx}")"
    n2="$(ndx_group_num "${g2}" "${ndx}")"
    if [[ -z "${n1}" || -z "${n2}" ]]; then
        _cb_fail "Index grubu bulunamadı: ${g1} / ${g2}"
        return 1
    fi
    printf '%s\n%s\n' "${n1}" "${n2}" | ${GMX} mindist -s "${tpr}" -f "${traj}" \
        -n "${ndx}" -od "${out}" -xvg none >/dev/null 2>&1
}

_make_hsd_ndx() {
    local gro="$1" base_ndx="$2" out_ndx="$3"
    local resid_list="${METAL_HSD_RESIDUES:-94 96 119}"
    local ngrps
    ngrps="$(grep -c '^\[' "${base_ndx}")"
    ${GMX} make_ndx -f "${gro}" -n "${base_ndx}" -o "${out_ndx}" <<EOF >/dev/null 2>&1
ri ${resid_list}
name ${ngrps} HSD_site
q
EOF
}

_ligand_rmsd() {
    local ref_tpr="$1" traj="$2" ndx="$3" out="$4"
    local fit_grp lig_grp
    fit_grp="$(_cb_ndx_nr "${ANALYSIS_FIT_GROUP:-Backbone}" Backbone "C-alpha")"
    lig_grp="$(_cb_ndx_nr "${CHECK_LIG_RESNAME}")"
    if [[ -z "${fit_grp}" || -z "${lig_grp}" ]]; then
        _cb_fail "RMSD index grupları bulunamadı"
        return 1
    fi
    printf '%s\n%s\n' "${fit_grp}" "${lig_grp}" | ${GMX} rms -s "${ref_tpr}" -f "${traj}" \
        -n "${ndx}" -o "${out}" -xvg none >/dev/null 2>&1
}

_cb_ndx_nr() {
    local py="${MDPREP_DIR}/.venv/bin/python3"
    [[ -x "${py}" ]] || py="$(command -v python3)"
    "${py}" "${MDPREP_DIR}/lib/ndx_tools.py" group-num "${CHECK_INDEX}" "$@"
}

check_binding_phase() {
    local phase="$1"
    local tpr="" traj="" struct="" tag=""

    if [[ "${CHECK_BINDING}" != "yes" ]]; then
        _cb_log "CHECK_BINDING=no — atlandı"
        return 0
    fi

    case "${phase}" in
        em)
            tpr="${EM_TPR:-em.tpr}"
            traj="${EM_GRO:-em.gro}"
            struct="${EM_GRO:-em.gro}"
            tag="em"
            ;;
        nvt)
            tpr="${NVT_TPR:-nvt.tpr}"
            traj="${NVT_DEFFNM:-nvt}.xtc"
            struct="${NVT_DEFFNM:-nvt}.gro"
            [[ -f "${traj}" ]] || traj="${struct}"
            tag="nvt"
            ;;
        npt)
            tpr="${NPT_TPR:-npt.tpr}"
            traj="${NPT_DEFFNM:-npt}.xtc"
            struct="${NPT_DEFFNM:-npt}.gro"
            [[ -f "${traj}" ]] || traj="${struct}"
            tag="npt"
            ;;
        md)
            tpr="${MD_TPR:-md_0_1.tpr}"
            traj="${CHECK_TRAJ:-}"
            if [[ -z "${traj}" && "${ANALYSIS_USE_PBC_FOR_BINDING:-yes}" == "yes" && -f "${ANALYSIS_PBC_XTC:-md_pbc.xtc}" ]]; then
                traj="${ANALYSIS_PBC_XTC}"
            fi
            [[ -n "${traj}" ]] || traj="${PROD_DEFFNM:-md_0_1}.xtc"
            struct="${PROD_DEFFNM:-md_0_1}.gro"
            [[ -f "${traj}" ]] || traj="${struct}"
            tag="md"
            ;;
        *)
            echo "Kullanım: $0 {em|nvt|npt|md}" >&2
            return 1
            ;;
    esac

    for f in "${tpr}" "${traj}" "${struct}" "${CHECK_REF_TPR}" "${CHECK_INDEX}"; do
        if [[ ! -f "${f}" ]]; then
            _cb_fail "Dosya yok: ${f}"
            return 1
        fi
    done

    _warns=0
    _fails=0

    mkdir -p "${CHECK_OUT_DIR}"
    local hsd_ndx="${CHECK_OUT_DIR}/${tag}_hsd.ndx"
    _make_hsd_ndx "${struct}" "${CHECK_INDEX}" "${hsd_ndx}" || {
        _cb_fail "HSD index oluşturulamadı"
        return 1
    }

    _cb_log "=== Bağ kontrolü: ${tag} ==="

    local zn_out="${CHECK_OUT_DIR}/${tag}_zn_lig.xvg"
    local hsd_out="${CHECK_OUT_DIR}/${tag}_hsd_lig.xvg"
    local rms_out="${CHECK_OUT_DIR}/${tag}_lig_rmsd.xvg"

    _mindist_groups "${tpr}" "${traj}" "${CHECK_INDEX}" \
        "${METAL_ION_RESNAME:-ZN}" "${CHECK_LIG_RESNAME}" "${zn_out}" || return 1
    _mindist_groups "${tpr}" "${traj}" "${hsd_ndx}" "HSD_site" "${CHECK_LIG_RESNAME}" "${hsd_out}" || return 1
    _ligand_rmsd "${CHECK_REF_TPR}" "${traj}" "${CHECK_INDEX}" "${rms_out}" || return 1

    local zn_val hsd_val rms_val
    zn_val="$(xvg_max "${zn_out}")"
    hsd_val="$(xvg_max "${hsd_out}")"
    rms_val="$(xvg_last "${rms_out}")"
    local rms_max
    rms_max="$(xvg_max "${rms_out}")"

    _compare "Zn–${CHECK_LIG_RESNAME} min mesafe (max frame)" "${zn_val}" \
        "${CHECK_ZN_LIG_WARN}" "${CHECK_ZN_LIG_FAIL}"
    _compare "HSD–${CHECK_LIG_RESNAME} min mesafe (max frame)" "${hsd_val}" \
        "${CHECK_HSD_LIG_WARN}" "${CHECK_HSD_LIG_FAIL}"
    _compare "Ligand RMSD son frame (ref: ${CHECK_REF_TPR})" "${rms_val}" \
        "${CHECK_LIG_RMSD_WARN}" "${CHECK_LIG_RMSD_FAIL}"

    _cb_log "Özet ${tag}: Zn–lig=${zn_val} nm, HSD–lig=${hsd_val} nm, RMSD=${rms_val} nm (max=${rms_max} nm)"
    _cb_log "Grafikler: ${CHECK_OUT_DIR}/${tag}_*.xvg"

    if [[ ${_fails} -gt 0 ]]; then
        if [[ "${CHECK_BINDING_STRICT}" == "yes" ]]; then
            _cb_fail "Strict mod: durduruluyor."
            return 2
        fi
        _cb_warn "Ligand aktif siteden uzaklaşmış olabilir — yapıyı kontrol edin."
    elif [[ ${_warns} -gt 0 ]]; then
        _cb_warn "Sınırda değerler — izlemeye devam."
    else
        _cb_log "OK — ligand aktif siteye yakın görünüyor."
    fi
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_binding_phase "${1:-}"
fi
