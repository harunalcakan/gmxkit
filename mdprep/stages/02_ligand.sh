#!/usr/bin/env bash
# =============================================================================
# 02_ligand.sh - Ligand topolojisi
#   1) sort_mol2_bonds.pl
#   2) CGenFF manuel kapı (.str)
#   3) cgenff script (legacy py2.7+nx1.11 veya py3)
#   4) editconf -> ligand.gro
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="02_ligand"

stage_guard "${STAGE}" || exit 0

is_done "00_check_env" || die "Önce ortam kontrolü: ./mdprep/run.sh check"
is_done "01_protein"   || die "Önce protein aşaması: ./mdprep/run.sh stage 01"

log_info "================ LİGAND TOPOLOJİSİ ================"

require_file "${LIGAND_MOL2}" "ligand mol2"
require_file "${SORT_MOL2_PL}" "sort_mol2_bonds.pl"
require_dir "${FF_DIR}" "force field klasörü"

CGENFF_SCRIPT="$(resolve_cgenff_script)"
require_file "${CGENFF_SCRIPT}" "cgenff dönüştürücü"

PY="$(find_cgenff_python)" || die "cgenff python bulunamadı. Kur: ./mdprep/run.sh setup"

PY3="$(find_python)" || die "python3 gerekli (pipeline yardımcıları)"

log_info "cgenff : ${PY} ${CGENFF_SCRIPT} (${CGENFF_BACKEND})"
log_info "Çıktı : ${LIGAND_MOL2_SORTED}, ${LIG_ITP}, ${LIG_PRM}, ${LIG_INI_PDB}, ${LIGAND_GRO}"

for f in "${LIGAND_MOL2_SORTED}" "${LIG_ITP}" "${LIG_PRM}" "${LIG_TOP}" \
         "${LIG_INI_PDB}" "${LIGAND_GRO}"; do
    [[ -f "${f}" ]] && backup_file "${f}"
done

# --- 1) mol2 bond sıralama (eski script.py: ligand_fix.mol2) ----------------
log_info "--- mol2 bond sıralama ---"
run_cmd perl "${SORT_MOL2_PL}" "${LIGAND_MOL2}" "${LIGAND_MOL2_SORTED}" \
    || die "sort_mol2_bonds.pl başarısız"

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: sonraki adımlar atlandı."
    log_info "  [manuel] ${CGENFF_URL} -> ${LIG_STR} (RESI ${LIG_RESNAME})"
    log_info "  ${PY} ${CGENFF_SCRIPT} ${LIG_RESNAME} ${LIGAND_MOL2_SORTED} ${LIG_STR} ${FF_DIR}"
    log_info "  gmx editconf -f ${LIG_INI_PDB} -o ${LIGAND_GRO}"
    exit 0
fi

require_file "${LIGAND_MOL2_SORTED}" "sıralanmış mol2"

mol_atoms="$(awk '/@<TRIPOS>ATOM/{a=1;next} a&&/^@<TRIPOS>/{exit} a{print}' \
    "${LIGAND_MOL2}" | wc -l | tr -d ' ')"
sorted_atoms="$(awk '/@<TRIPOS>ATOM/{a=1;next} a&&/^@<TRIPOS>/{exit} a{print}' \
    "${LIGAND_MOL2_SORTED}" | wc -l | tr -d ' ')"
[[ "${mol_atoms}" == "${sorted_atoms}" ]] \
    || die "Atom sayısı değişti: ${LIGAND_MOL2}=${mol_atoms}, ${LIGAND_MOL2_SORTED}=${sorted_atoms}"
log_ok "${LIGAND_MOL2_SORTED} hazır (${sorted_atoms} atom)."

# --- 2) CGenFF manuel kapı --------------------------------------------------
# Eski workflow adı: ligand_fix.str (config LIG_STR_ALT)
LIG_STR_FILE="${LIG_STR}"
if [[ ! -f "${LIG_STR_FILE}" && -f "${LIG_STR_ALT}" ]]; then
    LIG_STR_FILE="${LIG_STR_ALT}"
    log_info "Alternatif bulundu: ${LIG_STR_ALT} (eski ad)"
fi

if [[ -f "${LIG_STR_FILE}" ]]; then
    log_ok "CGenFF stream mevcut: ${LIG_STR_FILE}"
else
    pause_gate "CGenFF adımı:
  1) '${LIGAND_MOL2_SORTED}' dosyasını yükle: ${CGENFF_URL}
  2) RESI adı '${LIG_RESNAME}' olmalı (mol2 ile aynı).
  3) 'Include parameters that are already in CGenFF' SEÇME.
  4) İndirilen .str dosyasını '${LIG_STR}' olarak WORKDIR'e kaydet."
fi

require_file "${LIG_STR_FILE}" "CGenFF stream dosyası"
LIG_STR="${LIG_STR_FILE}"

if ! grep -qiE "RESI[[:space:]]+${LIG_RESNAME}([[:space:]]|;|$)" "${LIG_STR}"; then
    die "${LIG_STR} içinde RESI '${LIG_RESNAME}' bulunamadı. CGenFF çıktısını ve LIG_RESNAME config'ini kontrol et."
fi
log_ok "${LIG_STR} doğrulandı (RESI ${LIG_RESNAME})."

prep_confirm_gate "CGenFF — ligand parametreleri" \
    "Ligand RESI    : ${LIG_RESNAME}  (mol2 + .str ile aynı olmalı)" \
    "Stream dosyası : ${LIG_STR}" \
    "Force field    : ${FF_DIR}" \
    "Çıktılar       : ${LIG_ITP}, ${LIG_PRM}, ${LIG_INI_PDB}"

# --- 3) cgenff -> GROMACS itp/prm/pdb ---------------------------------------
log_info "--- cgenff dönüştürme ---"
run_cmd "${PY}" "${CGENFF_SCRIPT}" "${LIG_RESNAME}" "${LIGAND_MOL2_SORTED}" \
    "${LIG_STR}" "${FF_DIR}" \
    || die "cgenff script başarısız"

for f in "${LIG_ITP}" "${LIG_PRM}" "${LIG_INI_PDB}"; do
    [[ -s "${f}" ]] || die "cgenff çıktısı eksik/boş: ${f}"
done
log_ok "cgenff çıktıları: ${LIG_ITP}, ${LIG_PRM}, ${LIG_INI_PDB}"

log_info "--- lig.prm dihedraltypes sıralama (kılavuz Adım 4) ---"
run_cmd "${PY3}" "${MDPREP_DIR}/lib/top_tools.py" sort-prm "${LIG_PRM}" \
    || die "lig.prm sıralama başarısız"

# --- 4) ligand.gro (eski script.py: editconf lig_ini.pdb) -------------------
run_gmx "editconf ligand" -- editconf -f "${LIG_INI_PDB}" -o "${LIGAND_GRO}" \
    ::expect:: "${LIGAND_GRO}" \
    || die "editconf başarısız"

lig_atoms_gro="$(awk 'NR==2 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}' "${LIGAND_GRO}")"
[[ "${lig_atoms_gro}" =~ ^[0-9]+$ ]] && [[ "${lig_atoms_gro}" -gt 0 ]] \
    || die "${LIGAND_GRO} atom sayısı okunamadı"
[[ "${lig_atoms_gro}" == "${sorted_atoms}" ]] \
    || log_warn "${LIGAND_GRO} atom=${lig_atoms_gro}, mol2 atom=${sorted_atoms} (H sayımı farklı olabilir)"

log_ok "Ligand topolojisi doğrulandı (${LIGAND_GRO}: ${lig_atoms_gro} atom)."
mark_done "${STAGE}"
