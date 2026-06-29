#!/usr/bin/env bash
# =============================================================================
# 00_check_env.sh - Ortam doğrulaması (kurulum veya proje)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="00_check_env"
fail=0
note_fail() { log_err "$1"; fail=1; }

INSTALL_CHECK=0
_is_install_check && INSTALL_CHECK=1

if [[ "${INSTALL_CHECK}" -eq 1 ]]; then
    log_info "$(t check_install_hdr)"
else
    log_info "$(t check_project_hdr)"
fi
log_info "WORKDIR : ${WORKDIR}"
log_info "CGENFF_BACKEND : ${CGENFF_BACKEND}"

# --- Komutlar ---
log_info "$(t check_section_tools)"
if command -v "${GMX}" >/dev/null 2>&1; then
    gmxver="$("${GMX}" --version 2>/dev/null | grep -i 'GROMACS version' | head -n1 | sed 's/^[[:space:]]*//')"
    log_ok "$(t check_gmx_ok "${gmxver:-?}")"
else
    note_fail "$(t check_gmx_missing)"
fi

command -v perl >/dev/null 2>&1 && log_ok "$(t check_perl_ok "$(perl -e 'print $^V' 2>/dev/null)")" \
    || note_fail "$(t check_perl_missing)"

# --- Python 3 (pipeline yardımcıları) ---
log_info "$(t check_section_python)"
if PY3="$(find_python 2>/dev/null)"; then
    log_ok "python3: ${PY3} ($("${PY3}" -c 'import sys;print(sys.version.split()[0])' 2>/dev/null))"
else
    note_fail "$(t check_python_missing)"
fi

# --- cgenff ortamı ---
log_info "$(t check_section_cgenff "${CGENFF_BACKEND}")"
cgenff_script="$(resolve_cgenff_script)"
log_info "script: ${cgenff_script}"
script_root="${GMXKIT_HOME}"
[[ -f "${WORKDIR}/${cgenff_script}" ]] && script_root="${WORKDIR}"
if [[ -f "${script_root}/${cgenff_script}" ]]; then
    log_ok "$(t check_file_ok "${cgenff_script}")"
else
    note_fail "$(t check_file_missing "${cgenff_script}")"
fi

if CGENFF_PY="$(find_cgenff_python 2>/dev/null)"; then
    log_ok "$(t check_cgenff_py_ok "${CGENFF_PY}")"
    dep_out="$(cgenff_deps_ok "${CGENFF_PY}" 2>&1)" || dep_rc=$?
    dep_rc="${dep_rc:-0}"
    if [[ "${dep_rc}" -eq 0 ]]; then
        log_ok "${dep_out}"
    else
        note_fail "$(t check_cgenff_deps_fail)"
        echo "${dep_out}" | while read -r line; do [[ -n "${line}" ]] && log_err "  ${line}"; done
        log_info "$(t check_install_hint)"
    fi
else
    note_fail "$(t check_cgenff_py_missing)"
fi

# --- Force field (kurulum dizininde) ---
log_info "$(t check_section_ff)"
ff_root="${GMXKIT_HOME}"
[[ -d "${WORKDIR}/${FF_DIR}" ]] && ff_root="${WORKDIR}"
if [[ -d "${ff_root}/${FF_DIR}" ]]; then
    log_ok "$(t check_ff_ok "${FF_DIR}")"
    wmdat="${ff_root}/${FF_DIR}/watermodels.dat"
    if [[ -f "${wmdat}" ]] && grep -qE "^[[:space:]]*${WATER_MODEL}[[:space:]]" "${wmdat}"; then
        log_ok "$(t check_water_ok "${WATER_MODEL}")"
    elif [[ -f "${wmdat}" ]]; then
        note_fail "$(t check_water_missing "${WATER_MODEL}")"
    fi
else
    note_fail "$(t check_ff_missing "${FF_DIR}")"
fi

if [[ "${INSTALL_CHECK}" -eq 1 ]]; then
    log_info "$(t check_section_bundle)"
    for f in em.mdp nvt.mdp npt.mdp md.mdp ions.mdp sort_mol2_bonds.pl; do
        [[ -f "${GMXKIT_HOME}/${f}" ]] && log_ok "$(t check_file_ok "${f}")" \
            || note_fail "$(t check_file_missing "${f}")"
    done
    echo
    if [[ "${fail}" -eq 0 ]]; then
        log_ok "$(t check_install_pass)"
        mark_done "${STAGE}"
        exit 0
    fi
    log_err "$(t check_install_fail)"
    log_info "$(t check_install_hint)"
    exit 1
fi

# --- Proje girdileri ---
log_info "$(t check_section_inputs)"
for f in "${PROTEIN_PDB}" "${LIGAND_MOL2}" "${SORT_MOL2_PL}"; do
    [[ -f "${WORKDIR}/${f}" ]] && log_ok "$(t check_file_ok "${f}")" || note_fail "$(t check_file_missing "${f}")"
done

log_info "$(t check_section_mdp)"
for f in em.mdp "${IONS_MDP}" nvt.mdp npt.mdp "${PROD_MDP}"; do
    [[ -f "${WORKDIR}/${f}" ]] && log_ok "$(t check_file_ok "${f}")" || note_fail "$(t check_file_missing "${f}")"
done

log_info "$(t check_section_ligand)"
if [[ -f "${WORKDIR}/${LIGAND_MOL2}" ]]; then
    mol_name="$(mol2_molecule_name "${WORKDIR}/${LIGAND_MOL2}" || true)"
    log_info "$(t check_ligand_mol2 "${mol_name:-?}" "${LIG_RESNAME}")"
    if [[ -n "${mol_name}" && "${mol_name}" != "${LIG_RESNAME}" ]]; then
        log_warn "$(t check_ligand_resname_mismatch "${mol_name}" "${LIG_RESNAME}")"
    else
        log_ok "$(t check_ligand_resname_ok "${LIG_RESNAME}")"
    fi
fi

log_info "$(t check_section_protein)"
if [[ -f "${WORKDIR}/${PROTEIN_PDB}" ]]; then
    nhet="$(grep -c '^HETATM' "${WORKDIR}/${PROTEIN_PDB}" || true)"
    nhoh="$(grep -cE '^.{17}HOH' "${WORKDIR}/${PROTEIN_PDB}" || true)"
    log_info "$(t check_protein_counts "$(grep -c '^ATOM' "${WORKDIR}/${PROTEIN_PDB}" || true)" "${nhet}" "${nhoh}")"
    [[ "${nhet}" -eq 0 && "${nhoh}" -eq 0 ]] && log_ok "$(t check_protein_clean)" \
        || log_warn "$(t check_protein_hetatm)"
fi

echo
if [[ "${fail}" -eq 0 ]]; then
    log_ok "$(t check_project_pass)"
    mark_done "${STAGE}"
    exit 0
fi

log_err "$(t check_project_fail)"
log_info "$(t check_project_hint)"
exit 1
