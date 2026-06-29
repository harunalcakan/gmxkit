#!/usr/bin/env bash
# Remove project inputs/outputs mistakenly created in GMXKIT_HOME (install folder).
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
export GMXKIT_HOME="$(cd "${MDPREP_DIR}/.." && pwd)"
export GMXKIT_WORKDIR="${GMXKIT_HOME}"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

ASSUME_YES=0

for arg in "$@"; do
    case "${arg}" in
        -y|--yes) ASSUME_YES=1 ;;
        help|-h)
            cat <<EOF
$(t cleanup_install_help_title)

  gmxkit cleanup-install       Remove stray project files from install folder
  gmxkit cleanup-install -y    No confirmation

Removes: protein.pdb, ligand.mol2, pipeline outputs, prep checkpoints in install dir
Keeps: mdprep/, force field, *.mdp templates, cgenff scripts, install state
Example inputs: examples/metalloenzyme-sample/
EOF
            exit 0
            ;;
        *) die "$(t cleanup_install_unknown "${arg}")" ;;
    esac
done

_install_input_files() {
    printf '%s\n' \
        "${PROTEIN_PDB}" \
        "${PROTEIN_PDB_PREP}" \
        "${LIGAND_MOL2}" \
        "${LIGAND_MOL2_SORTED}" \
        "ligand_fix.mol2" \
        "${LIG_STR_ALT}" \
        "${LIG_STR}" \
        "gmxkit.env"
}

_preserve_install_state() {
    local tmp
    tmp="$(mktemp -d)"
    [[ -f "${STATE_DIR}/.installed" ]] && cp -f "${STATE_DIR}/.installed" "${tmp}/"
    [[ -f "${STATE_DIR}/install_report.txt" ]] && cp -f "${STATE_DIR}/install_report.txt" "${tmp}/"
    printf '%s' "${tmp}"
}

_restore_install_state() {
    local tmp="$1"
    mkdir -p "${STATE_DIR}"
    [[ -f "${tmp}/.installed" ]] && cp -f "${tmp}/.installed" "${STATE_DIR}/"
    [[ -f "${tmp}/install_report.txt" ]] && cp -f "${tmp}/install_report.txt" "${STATE_DIR}/"
    rm -rf "${tmp}"
}

main_cleanup_install_home() {
    is_install_home || die "$(t cleanup_install_not_home)"

    echo ""
    echo "======== $(t cleanup_install_title) ========"
    log_info "GMXKIT_HOME: ${GMXKIT_HOME}"
    echo ""
    echo "  $(t cleanup_install_remove_label)"
    local f
    while IFS= read -r f; do
        [[ -e "${GMXKIT_HOME}/${f}" ]] && printf '    · %s\n' "${f}"
    done < <(_install_input_files)
    echo "    $(t cleanup_install_remove_outputs)"
    echo ""
    echo "  $(t cleanup_install_keep_label)"
    echo "    mdprep/  ${FF_DIR}/  *.mdp  examples/"
    echo ""

    if [[ "${ASSUME_YES}" -ne 1 ]]; then
        read -r -p "$(t cleanup_install_confirm)" ans
        [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "evet" ]] || {
            log_info "$(t cleanup_install_cancelled)"
            exit 0
        }
    fi

    local preserved removed=0 tmp
    tmp="$(_preserve_install_state)"

    while IFS= read -r f; do
        [[ -e "${GMXKIT_HOME}/${f}" ]] || continue
        rm -f "${GMXKIT_HOME}/${f}"
        log_ok "$(t cleanup_install_removed "${f}")"
        removed=$((removed + 1))
    done < <(_install_input_files)

    set +e
    CLEAN_YES=yes CLEAN_REMOVE_BACKUPS=yes CLEAN_REMOVE_STR=yes \
        bash "${MDPREP_DIR}/lib/cleanup_workdir.sh" --yes --remove-backups --remove-str
    set -e

    rm -rf "${GMXKIT_HOME}/.gmxkit" 2>/dev/null || true
    _restore_install_state "${tmp}"

    echo ""
    if [[ "${removed}" -eq 0 ]]; then
        log_info "$(t cleanup_install_nothing)"
    fi
    log_ok "$(t cleanup_install_done)"
    log_info "$(t cleanup_install_next)"
}

main_cleanup_install_home "$@"
