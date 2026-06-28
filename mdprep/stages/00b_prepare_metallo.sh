#!/usr/bin/env bash
# =============================================================================
# 00b_prepare_metallo.sh - CA/Zn metalloenzim PDB hazırlığı (kılavuz Adım 1)
#   * Zn koordinasyon Histidinleri → HSD
#   * Protein sonu ile Zn arasına TER
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="00b_prepare_metallo"
PREP_PY="${MDPREP_DIR}/lib/prep_pdb.py"

stage_guard "${STAGE}" || exit 0

is_done "00_check_env" || die "Önce: ./mdprep/run.sh check"

if [[ "${METAL_ENZYME}" != "yes" ]]; then
    log_info "METAL_ENZYME=no — metalloenzim PDB hazırlığı atlandı."
    mark_done "${STAGE}"
    exit 0
fi

log_info "================ METALLOenzim PDB HAZIRLIĞI (CA) ================"
require_file "${PROTEIN_PDB}" "protein pdb"
require_file "${PREP_PY}" "prep_pdb.py"

PY="$(find_python)" || die "python3 gerekli"

[[ -f "${PROTEIN_PDB_PREP}" ]] && backup_file "${PROTEIN_PDB_PREP}"

log_info "HSD residue'ler: ${METAL_HSD_RESIDUES} (chain ${METAL_CHAIN})"
log_info "Metal iyon: ${METAL_ION_RESNAME}"

run_cmd "${PY}" "${PREP_PY}" "${PROTEIN_PDB}" "${PROTEIN_PDB_PREP}" \
    --hsd "${METAL_HSD_RESIDUES}" \
    --chain "${METAL_CHAIN}" \
    --metal "${METAL_ION_RESNAME}" \
    || die "PDB hazırlığı başarısız"

require_file "${PROTEIN_PDB_PREP}" "hazırlanmış pdb"

if ! grep -qE "^HETATM.*${METAL_ION_RESNAME}[[:space:]]" "${PROTEIN_PDB_PREP}"; then
    log_warn "PDB'de ${METAL_ION_RESNAME} (HETATM) bulunamadı."
    log_warn "CA simülasyonu için Çinko koordinatını PDB'ye ekleyip bu aşamayı tekrar çalıştırın."
fi

for res in ${METAL_HSD_RESIDUES}; do
    grep -qE " HSD ${METAL_CHAIN}[[:space:]]+${res}[[:space:]]" "${PROTEIN_PDB_PREP}" \
        && log_ok "HSD ${METAL_CHAIN} ${res} doğrulandı." \
        || log_warn "HSD ${METAL_CHAIN} ${res} bulunamadı (PDB residue numarasını kontrol edin)."
done

log_ok "Hazır PDB: ${PROTEIN_PDB_PREP}"
mark_done "${STAGE}"
