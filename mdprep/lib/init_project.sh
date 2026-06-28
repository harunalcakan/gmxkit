#!/usr/bin/env bash
# New project folder — templates + .gmxkit/ runtime (logs/state isolated per project)
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "${LIB_DIR}/common.sh"

cmd_init_project() {
    local target="${1:-.}"
    [[ -d "${target}" ]] || mkdir -p "${target}"
    target="$(cd "${target}" && pwd)"

    mkdir -p "${target}/.gmxkit/logs" "${target}/.gmxkit/state" "${target}/.gmxkit/backups"

    local f
    for f in em.mdp nvt.mdp npt.mdp md.mdp ions.mdp; do
        if [[ ! -f "${target}/${f}" && -f "${GMXKIT_HOME}/${f}" ]]; then
            cp -f "${GMXKIT_HOME}/${f}" "${target}/${f}"
            log_info "$(t init_copied_mdp "${f}")"
        fi
    done

    for f in sort_mol2_bonds.pl cgenff_charmm2gmx_py3_nx2.py cgenff_charmm2gmx_py2.py; do
        if [[ ! -e "${target}/${f}" && -f "${GMXKIT_HOME}/${f}" ]]; then
            ln -snf "${GMXKIT_HOME}/${f}" "${target}/${f}"
        fi
    done

    if [[ ! -e "${target}/${FF_DIR}" && -d "${GMXKIT_HOME}/${FF_DIR}" ]]; then
        ln -snf "${GMXKIT_HOME}/${FF_DIR}" "${target}/${FF_DIR}"
        log_info "$(t init_ff_link "${FF_DIR}")"
    fi

    if [[ ! -f "${target}/gmxkit.env" ]]; then
        cp -f "${MDPREP_DIR}/profiles/gmxkit.env.example" "${target}/gmxkit.env" 2>/dev/null || \
            cat >"${target}/gmxkit.env" <<'EOF'
# Project settings (optional overrides for mdprep/config.sh)
# CHECK_LIG_RESNAME="2Q38"
# METAL_ENZYME="no"
EOF
    fi

    log_ok "$(t init_ready "${target}")"
    echo ""
    echo "  $(t init_next_steps)"
    echo "    cd ${target}"
    echo "    # add protein.pdb, ligand.mol2"
    echo "    ${GMXKIT_HOME}/md check"
    echo "    ${GMXKIT_HOME}/md"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    cmd_init_project "${1:-.}"
fi
