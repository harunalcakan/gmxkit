#!/usr/bin/env bash
# Üretilmiş GROMACS/pipeline dosyalarını siler; girdi dosyaları ve mdprep/ kalır.
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${MDPREP_DIR}/lib/common.sh"

CLEAN_REMOVE_BACKUPS="${CLEAN_REMOVE_BACKUPS:-no}"
CLEAN_REMOVE_STR="${CLEAN_REMOVE_STR:-no}"   # yes → lig.str / ligand_fix.str de silinir
CLEAN_YES="${CLEAN_YES:-no}"
CLEAN_DRY="${CLEAN_DRY:-no}"

usage() {
    cat <<EOF
Kullanım: cleanup_workdir.sh [seçenekler]

  --dry-run          Silinecekleri listele, silme
  --yes              Onay sormadan sil
  --keep-backups     mdprep/backups/ dokunma (varsayılan)
  --remove-backups   mdprep/backups/ de sil
  --remove-str       CGenFF .str dosyalarını da sil (lig.str, ligand_fix.str)
  -h, --help

Korunanlar: protein.pdb, ligand.mol2, *.mdp, force field (.ff), mdprep/ scriptleri,
            cgenff scriptleri, spc216.gro, (varsayılan) lig.str / ligand_fix.str
EOF
}

_parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)       CLEAN_DRY=yes ;;
            --yes|-y)        CLEAN_YES=yes ;;
            --remove-backups) CLEAN_REMOVE_BACKUPS=yes ;;
            --keep-backups)  CLEAN_REMOVE_BACKUPS=no ;;
            --remove-str)    CLEAN_REMOVE_STR=yes ;;
            -h|--help)       usage; exit 0 ;;
            *) die "Bilinmeyen seçenek: $1" ;;
        esac
        shift
    done
}

_collect_removable() {
    local -n _out=$1
    _out=()

    local names=(
        "${PROTEIN_PDB_PREP}"
        "${PROTEIN_GRO}" "${PROTEIN_TOP}" "${PROTEIN_POSRE}"
        "${LIGAND_MOL2_SORTED}"
        "${LIG_ITP}" "${LIG_PRM}" "${LIG_TOP}" "${LIG_INI_PDB}" "${LIGAND_GRO}"
        "${LIG_POSRE_ITP}"
        "${COMPLEX_GRO}" "${NEWBOX_GRO}" "${SOLV_GRO}" "${SOLV_IONS_GRO}"
        "${INDEX_NDX}" "${INDEX_LIG_NDX}"
        "${EM_TPR}" "${EM_GRO}"
        "${NVT_TPR}" "${NPT_TPR}"
        "ions.tpr" "mdout.mdp"
        "run_local_md.sh" "check_binding.sh"
        "${MDPREP_DIR}/ANALYSIS.md"
    )

    local base deffnms d ext
    for base in "${NVT_DEFFNM}" "${NPT_DEFFNM}" "${PROD_DEFFNM}"; do
        for ext in gro tpr cpt edr log xtc trr xvg; do
            names+=("${base}.${ext}")
        done
    done

    local f
    for f in "${names[@]}"; do
        [[ -n "${f}" && -e "${WORKDIR}/${f}" ]] && _out+=("${WORKDIR}/${f}")
    done

    if [[ "${CLEAN_REMOVE_STR}" == "yes" ]]; then
        for f in "${LIG_STR}" "${LIG_STR_ALT}"; do
            [[ -n "${f}" && -f "${WORKDIR}/${f}" ]] && _out+=("${WORKDIR}/${f}")
        done
    fi

    shopt -s nullglob
    local g
    for g in \
        "${WORKDIR}"/topol_*.itp \
        "${WORKDIR}"/*.xvg \
        "${WORKDIR}"/#* \
        "${LOG_DIR}/binding_checks"/* \
        "${LOG_DIR}/analysis"/* \
        "${LOG_DIR}/queue"/*; do
        [[ -e "${g}" ]] && _out+=("${g}")
    done
    shopt -u nullglob

    if [[ "${CLEAN_REMOVE_BACKUPS}" == "yes" && -d "${BACKUP_DIR}" ]]; then
        while IFS= read -r -d '' g; do _out+=("${g}"); done \
            < <(find "${BACKUP_DIR}" -mindepth 1 -print0 2>/dev/null)
    fi
}

_clear_checkpoints() {
    rm -f "${STATE_DIR}"/*.done 2>/dev/null || true
    log_ok "Checkpoint'ler temizlendi."
}

cleanup_workdir() {
    _parse_args "$@"

    local files=()
    _collect_removable files

    if [[ ${#files[@]} -eq 0 ]]; then
        log_info "Silinecek üretilmiş dosya bulunamadı."
        _clear_checkpoints
        return 0
    fi

    log_info "Silinecek dosya sayısı: ${#files[@]}"
    local p
    for p in "${files[@]}"; do
        printf '  - %s\n' "${p#${WORKDIR}/}"
    done

    if [[ "${CLEAN_DRY}" == "yes" ]]; then
        log_warn "DRY-RUN: dosyalar silinmedi."
        return 0
    fi

    if [[ "${CLEAN_YES}" != "yes" ]]; then
        echo ""
        if ! confirm "$(t clean_confirm1)"; then
            log_info "Temizlik iptal edildi."
            return 0
        fi
        if ! confirm "$(t clean_confirm2)"; then
            log_info "Temizlik iptal edildi."
            return 0
        fi
    fi

    for p in "${files[@]}"; do
        rm -f "${p}" 2>/dev/null || true
    done
    _clear_checkpoints
    log_ok "Sistem temizlendi — baştan prep için hazır."
    log_info "Sonraki: ./mdprep/md.sh check && ./mdprep/md.sh prep"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cleanup_workdir "$@"
fi
