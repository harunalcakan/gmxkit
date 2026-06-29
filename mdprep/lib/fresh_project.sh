#!/usr/bin/env bash
# Reset project folder to inputs-only (remove symlinks, scaffold, outputs, .gmxkit).
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

ASSUME_YES=0

for arg in "$@"; do
    case "${arg}" in
        -y|--yes) ASSUME_YES=1 ;;
        help|-h)
            cat <<EOF
$(t fresh_help_title)

  gmxkit fresh              Reset project (keeps inputs, removes symlinks + outputs)
  gmxkit fresh -y           No confirmation

Keeps:  protein.pdb, ligand.mol2, ligand_fix.mol2, ligand_fix.str, gmxkit.env
Removes: symlinks (FF, cgenff scripts), copied *.mdp, GROMACS outputs, .gmxkit/
Next run of gmxkit re-scaffolds templates and symlinks automatically.
EOF
            exit 0
            ;;
        *) die "$(t fresh_unknown "${arg}")" ;;
    esac
done

_fresh_keep_files() {
    printf '%s\n' \
        "${PROTEIN_PDB}" \
        "${LIGAND_MOL2}" \
        "${LIG_STR_ALT}" \
        "ligand_fix.mol2" \
        "gmxkit.env"
}

_fresh_remove_symlinks_and_scaffold() {
    local f removed=0
    for f in sort_mol2_bonds.pl cgenff_charmm2gmx_py3_nx2.py cgenff_charmm2gmx_py2.py "${FF_DIR}"; do
        [[ -e "${WORKDIR}/${f}" ]] || continue
        if [[ -L "${WORKDIR}/${f}" ]]; then
            rm -f "${WORKDIR}/${f}"
            log_ok "$(t fresh_removed_link "${f}")"
            removed=$((removed + 1))
        fi
    done
    for f in em.mdp nvt.mdp npt.mdp md.mdp ions.mdp; do
        [[ -f "${WORKDIR}/${f}" ]] || continue
        rm -f "${WORKDIR}/${f}"
        log_ok "$(t fresh_removed_file "${f}")"
        removed=$((removed + 1))
    done
    [[ "${removed}" -eq 0 ]] && log_info "$(t fresh_nothing_scaffold)"
}

main_fresh() {
    [[ "${WORKDIR}" != "${GMXKIT_HOME}" ]] || die "$(t fresh_not_project)"

    echo ""
    echo "======== $(t fresh_title) ========"
    log_info "WORKDIR: ${WORKDIR}"

    echo ""
    echo "  $(t fresh_keep_label)"
    local k
    while IFS= read -r k; do
        [[ -f "${WORKDIR}/${k}" ]] && printf '    ✓ %s\n' "${k}" || printf '    · %s\n' "${k}"
    done < <(_fresh_keep_files)
    echo ""
    echo "  $(t fresh_remove_label)"
    echo "    $(t fresh_remove_symlinks)"
    echo "    $(t fresh_remove_mdp)"
    echo "    $(t fresh_remove_outputs)"
    echo "    $(t fresh_remove_gmxkit)"
    echo ""

    if [[ "${ASSUME_YES}" -ne 1 ]]; then
        read -r -p "$(t fresh_confirm)" ans
        [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "evet" ]] || {
            log_info "$(t fresh_cancelled)"
            exit 0
        }
    fi

    set +e
    CLEAN_YES=yes bash "${MDPREP_DIR}/lib/cleanup_workdir.sh" --yes --remove-backups
    _fresh_remove_symlinks_and_scaffold
    find "${WORKDIR}/.gmxkit" -mindepth 1 -delete 2>/dev/null
    rm -rf "${WORKDIR}/.gmxkit" 2>/dev/null
    set -e

    echo ""
    printf '[ OK ] %s\n' "$(t fresh_done)"
    printf '[INFO] %s\n' "$(t fresh_next)"
}

main_fresh "$@"
