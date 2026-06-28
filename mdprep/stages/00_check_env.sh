#!/usr/bin/env bash
# =============================================================================
# 00_check_env.sh - Ortam + girdi doğrulaması
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="00_check_env"
fail=0
note_fail() { log_err "$1"; fail=1; }

log_info "================ ORTAM KONTROLÜ ================"
log_info "WORKDIR : ${WORKDIR}"
log_info "CGENFF_BACKEND : ${CGENFF_BACKEND}"

# --- Komutlar ---
log_info "--- Komutlar ---"
if command -v "${GMX}" >/dev/null 2>&1; then
    gmxver="$("${GMX}" --version 2>/dev/null | grep -i 'GROMACS version' | head -n1 | sed 's/^[[:space:]]*//')"
    log_ok "gmx bulundu: ${gmxver:-bilinmiyor}"
else
    note_fail "gmx bulunamadı — GROMACS'ı siz kurun; config.sh → GMX=\"gmx\" veya tam yol"
fi

command -v perl >/dev/null 2>&1 && log_ok "perl bulundu ($(perl -e 'print $^V' 2>/dev/null))" \
    || note_fail "perl bulunamadı. Kur: ./md install"

# --- Python 3 (pipeline yardımcıları) ---
log_info "--- Python 3 (pipeline) ---"
if PY3="$(find_python 2>/dev/null)"; then
    log_ok "python3: ${PY3} ($("${PY3}" -c 'import sys;print(sys.version.split()[0])' 2>/dev/null))"
else
    note_fail "python3 bulunamadı (gro_tools, top_tools, ndx_tools için)."
fi

# --- cgenff ortamı ---
log_info "--- cgenff (${CGENFF_BACKEND}) ---"
cgenff_script="$(resolve_cgenff_script)"
log_info "script: ${cgenff_script}"
[[ -f "${WORKDIR}/${cgenff_script}" ]] && log_ok "var: ${cgenff_script}" \
    || note_fail "EKSİK: ${cgenff_script}"

if CGENFF_PY="$(find_cgenff_python 2>/dev/null)"; then
    log_ok "cgenff python: ${CGENFF_PY}"
    dep_out="$(cgenff_deps_ok "${CGENFF_PY}" 2>&1)" || dep_rc=$?
    dep_rc="${dep_rc:-0}"
    if [[ "${dep_rc}" -eq 0 ]]; then
        log_ok "${dep_out}"
    else
        note_fail "cgenff bağımlılığı eksik/uyumsuz."
        echo "${dep_out}" | while read -r line; do [[ -n "${line}" ]] && log_err "  ${line}"; done
        case "${CGENFF_BACKEND}" in
            legacy|py2|py27)
                log_info "  Kur: ./md install"
                ;;
            *)
                log_info "  Kur: ./md install"
                ;;
        esac
    fi
else
    note_fail "cgenff python bulunamadı. Kur: ./md install"
fi

# --- Force field ---
log_info "--- Force field ---"
if [[ -d "${WORKDIR}/${FF_DIR}" ]]; then
    log_ok "FF klasörü: ${FF_DIR}"
    wmdat="${WORKDIR}/${FF_DIR}/watermodels.dat"
    if [[ -f "${wmdat}" ]] && grep -qE "^[[:space:]]*${WATER_MODEL}[[:space:]]" "${wmdat}"; then
        log_ok "Su modeli '${WATER_MODEL}' mevcut."
    elif [[ -f "${wmdat}" ]]; then
        note_fail "Su modeli '${WATER_MODEL}' watermodels.dat içinde yok."
    fi
else
    note_fail "FF klasörü yok: ${FF_DIR}"
fi

# --- Girdiler ---
log_info "--- Girdi dosyaları ---"
for f in "${PROTEIN_PDB}" "${LIGAND_MOL2}" "${SORT_MOL2_PL}"; do
    [[ -f "${WORKDIR}/${f}" ]] && log_ok "var: ${f}" || note_fail "EKSİK: ${f}"
done

log_info "--- mdp dosyaları ---"
for f in em.mdp "${IONS_MDP}" nvt.mdp npt.mdp "${PROD_MDP}"; do
    [[ -f "${WORKDIR}/${f}" ]] && log_ok "var: ${f}" || note_fail "EKSİK: ${f}"
done

log_info "--- Ligand ---"
if [[ -f "${WORKDIR}/${LIGAND_MOL2}" ]]; then
    mol_name="$(awk '/@<TRIPOS>MOLECULE/{getline; gsub(/[[:space:]]/,"",$0); print; exit}' "${WORKDIR}/${LIGAND_MOL2}")"
    log_info "mol2 adı: '${mol_name}' (LIG_RESNAME='${LIG_RESNAME}')"
fi

log_info "--- Protein ---"
if [[ -f "${WORKDIR}/${PROTEIN_PDB}" ]]; then
    nhet="$(grep -c '^HETATM' "${WORKDIR}/${PROTEIN_PDB}" || true)"
    nhoh="$(grep -cE '^.{17}HOH' "${WORKDIR}/${PROTEIN_PDB}" || true)"
    log_info "ATOM=$(grep -c '^ATOM' "${WORKDIR}/${PROTEIN_PDB}" || true)  HETATM=${nhet}  HOH=${nhoh}"
    [[ "${nhet}" -eq 0 && "${nhoh}" -eq 0 ]] && log_ok "Protein temiz." \
        || log_warn "HETATM/HOH var — pdb2gmx öncesi temizle."
fi

echo
if [[ "${fail}" -eq 0 ]]; then
    log_ok "ORTAM KONTROLÜ GEÇTİ."
    mark_done "${STAGE}"
    exit 0
else
    log_err "ORTAM KONTROLÜ BAŞARISIZ."
    log_info "Kurulum: ./md install"
    exit 1
fi
