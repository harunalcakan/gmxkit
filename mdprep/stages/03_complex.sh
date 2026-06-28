#!/usr/bin/env bash
# =============================================================================
# 03_complex.sh - complex.gro montajı + topol.top cerrahisi
# Kaynak: eski script.py merge_protein_ligand + modify_topol_file
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="03_complex"
GRO_PY="${MDPREP_DIR}/lib/gro_tools.py"
TOP_PY="${MDPREP_DIR}/lib/top_tools.py"

stage_guard "${STAGE}" || exit 0

is_done "01_protein" || die "Önce: ./mdprep/run.sh stage 01"
is_done "02_ligand"   || die "Önce: ./mdprep/run.sh stage 02"

log_info "================ KOMPLEKS OLUŞTURMA ================"
require_file "${PROTEIN_GRO}" "protein gro"
require_file "${LIGAND_GRO}" "ligand gro"
require_file "${PROTEIN_TOP}" "protein topoloji"
require_file "${LIG_ITP}" "ligand itp"
require_file "${LIG_PRM}" "ligand prm"

PY="$(find_python)" || die "python3 gerekli"
require_file "${GRO_PY}" "gro_tools.py"
require_file "${TOP_PY}" "top_tools.py"

for f in "${COMPLEX_GRO}" "${PROTEIN_TOP}"; do
    [[ -f "${f}" ]] && backup_file "${f}"
done

# --- complex.gro ------------------------------------------------------------
log_info "--- ${COMPLEX_GRO} montajı ---"
run_cmd "${PY}" "${GRO_PY}" "${PROTEIN_GRO}" "${LIGAND_GRO}" "${COMPLEX_GRO}" \
    || die "complex.gro birleştirme başarısız"

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: topol cerrahisi atlandı."
    log_info "  ${PY} ${TOP_PY} add-ligand ${PROTEIN_TOP} ${PROTEIN_TOP} --prm ${LIG_PRM} --itp ${LIG_ITP} --resname ${LIG_RESNAME}"
    exit 0
fi

require_file "${COMPLEX_GRO}" "complex gro"
prot_n="$(awk 'NR==2 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' "${PROTEIN_GRO}")"
lig_n="$(awk 'NR==2 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' "${LIGAND_GRO}")"
cpx_n="$(awk 'NR==2 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print}' "${COMPLEX_GRO}")"
[[ "${cpx_n}" == "$((prot_n + lig_n))" ]] \
    || die "Atom sayısı tutmuyor: ${prot_n}+${lig_n} != ${cpx_n}"
log_ok "${COMPLEX_GRO}: ${cpx_n} atom (protein ${prot_n} + ligand ${lig_n})"

# --- topol.top cerrahisi ----------------------------------------------------
log_info "--- topol.top ligand include ---"
run_cmd "${PY}" "${TOP_PY}" add-ligand "${PROTEIN_TOP}" "${PROTEIN_TOP}" \
    --prm "${LIG_PRM}" --itp "${LIG_ITP}" --resname "${LIG_RESNAME}" \
    || die "topol.top düzenleme başarısız"

grep -qE "^[[:space:]]*[^[:space:];]+[[:space:]]+1" "${PROTEIN_TOP}" \
    && grep -q "#include \"${LIG_ITP}\"" "${PROTEIN_TOP}" \
    || die "[ molecules ] / ${LIG_ITP} doğrulanamadı"
moltype="$("${PY}" -c "import sys; sys.path.insert(0,'${MDPREP_DIR}/lib'); from top_tools import read_moleculetype; print(read_moleculetype('${LIG_ITP}'))")"
grep -qE "^[[:space:]]*${moltype}[[:space:]]+1" "${PROTEIN_TOP}" \
    || die "[ molecules ] altında ${moltype} satırı yok"

log_ok "Kompleks hazır: ${COMPLEX_GRO}, ${PROTEIN_TOP} güncellendi."
mark_done "${STAGE}"
