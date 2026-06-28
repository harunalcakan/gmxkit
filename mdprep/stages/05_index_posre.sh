#!/usr/bin/env bash
# =============================================================================
# 05_index_posre.sh - ligand posre + tc-grps index grupları
# Kaynak: step12.py, step13.py
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="05_index_posre"
NDX_PY="${MDPREP_DIR}/lib/ndx_tools.py"
TOP_PY="${MDPREP_DIR}/lib/top_tools.py"

stage_guard "${STAGE}" || exit 0

is_done "04_solvate_ions" || die "Önce: ./mdprep/run.sh stage 04"

log_info "================ INDEX + LİGAND POSRE ================"
require_file "${LIGAND_GRO}" "ligand gro"
require_file "${PROTEIN_TOP}" "topoloji"
require_file "${LIG_ITP}" "ligand itp"

PY="$(find_python)" || die "python3 gerekli"
require_file "${NDX_PY}" "ndx_tools.py"
require_file "${TOP_PY}" "top_tools.py"

STRUCT_GRO="${EM_GRO}"
[[ -f "${STRUCT_GRO}" ]] || STRUCT_GRO="${SOLV_IONS_GRO}"
require_file "${STRUCT_GRO}" "em.gro veya solv_ions.gro"
log_info "Index yapı dosyası: ${STRUCT_GRO}"

for f in "${INDEX_LIG_NDX}" "${LIG_POSRE_ITP}" "${INDEX_NDX}"; do
    [[ -f "${f}" ]] && backup_file "${f}"
done
backup_file "${PROTEIN_TOP}"

# --- ligand heavy-atom index + genrestr -------------------------------------
log_info "--- ligand posre (${LIG_POSRE_ITP}) ---"
lig_grp="$("${PY}" "${NDX_PY}" ligand-heavy --gmx "${GMX}" \
    "${LIGAND_GRO}" "${INDEX_LIG_NDX}")" \
    || die "ligand heavy grup alınamadı"
log_info "genrestr grup: ${lig_grp}"

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: genrestr ve complex index atlandı."
    log_info "  gmx genrestr -f ${LIGAND_GRO} -n ${INDEX_LIG_NDX} -o ${LIG_POSRE_ITP} -fc ${LIG_POSRE_FC}"
    log_info "  ${PY} ${TOP_PY} add-posre ..."
    log_info "  ${PY} ${NDX_PY} complex-index ..."
    exit 0
fi

prep_confirm_gate "$(t gate_index)" \
    "Yapı dosyası  : ${STRUCT_GRO}" \
    "genrestr grup : ${lig_grp}  (ligand heavy atoms — GROMACS'un sorduğu grup)" \
    "Tc-grps 1     : ${GRP_PROTEIN_LIG}  (protein + Zn + ligand)" \
    "Tc-grps 2     : ${GRP_WATER_IONS}  (su + iyonlar)" \
    "Ligand posre  : ${LIG_POSRE_ITP}  fc=${LIG_POSRE_FC}" \
    "mdp uyumu     : nvt/npt/md → tc-grps = ${GRP_PROTEIN_LIG} ${GRP_WATER_IONS}"

run_gmx_stdin "genrestr ligand" "${lig_grp}"$'\n' -- \
    genrestr -f "${LIGAND_GRO}" -n "${INDEX_LIG_NDX}" -o "${LIG_POSRE_ITP}" \
    -fc ${LIG_POSRE_FC} \
    ::expect:: "${LIG_POSRE_ITP}" \
    || die "genrestr başarısız"

run_cmd "${PY}" "${TOP_PY}" add-posre "${PROTEIN_TOP}" "${PROTEIN_TOP}" \
    --itp "${LIG_ITP}" --posre "${LIG_POSRE_ITP}" \
    || die "topol posre ekleme başarısız"

# --- Protein_LIG + Water_and_Ions index -------------------------------------
log_info "--- ${INDEX_NDX} (${GRP_PROTEIN_LIG}, ${GRP_WATER_IONS}) ---"
LIG_NDX_NAME="$("${PY}" -c "import sys; sys.path.insert(0,'${MDPREP_DIR}/lib'); from top_tools import read_moleculetype; print(read_moleculetype('${LIG_ITP}'))")"
log_info "Ligand index residue/moltype: ${LIG_NDX_NAME} (lig.itp)"
run_cmd "${PY}" "${NDX_PY}" complex-index --gmx "${GMX}" \
    "${STRUCT_GRO}" "${INDEX_NDX}" \
    --lig-resname "${LIG_NDX_NAME}" \
    --grp-pl "${GRP_PROTEIN_LIG}" \
    --grp-wi "${GRP_WATER_IONS}" \
    $([[ "${METAL_ENZYME}" == "yes" ]] && echo "--metal-resname ${METAL_ION_RESNAME}") \
    || die "complex index başarısız"

require_file "${INDEX_NDX}" "index.ndx"
grep -q "${GRP_PROTEIN_LIG}" "${INDEX_NDX}" \
    || die "${INDEX_NDX} içinde ${GRP_PROTEIN_LIG} yok"
grep -q "${GRP_WATER_IONS}" "${INDEX_NDX}" \
    || die "${INDEX_NDX} içinde ${GRP_WATER_IONS} yok"

log_ok "Index ve posre hazır."
mark_done "${STAGE}"
