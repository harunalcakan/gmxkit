#!/usr/bin/env bash
# =============================================================================
# 01_protein.sh - pdb2gmx ile protein topolojisi (non-interaktif)
# Üretir: PROTEIN_GRO, PROTEIN_TOP, PROTEIN_POSRE (config.sh)
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="01_protein"

stage_guard "${STAGE}" || exit 0

is_done "00_check_env" || die "Önce ortam kontrolü: ./mdprep/run.sh check"
if [[ "${METAL_ENZYME}" == "yes" ]]; then
    is_done "00b_prepare_metallo" || die "Önce metalloenzim PDB: ./mdprep/run.sh stage 00b"
fi

PDB_IN="${PROTEIN_PDB}"
[[ "${METAL_ENZYME}" == "yes" ]] && PDB_IN="${PROTEIN_PDB_PREP}"

log_info "================ PROTEİN TOPOLOJİSİ (pdb2gmx) ================"
log_info "Girdi : ${PDB_IN}"
log_info "FF    : ${FF_NAME}  |  su: ${WATER_MODEL}"
log_info "Çıktı : ${PROTEIN_GRO}, ${PROTEIN_TOP}, ${PROTEIN_POSRE}"

require_file "${PDB_IN}" "protein yapısı"
require_dir "${FF_DIR}" "force field klasörü"

# Mevcut çıktılar varsa yedekle (FORCE=1 veya yeniden çalıştırma)
for f in "${PROTEIN_GRO}" "${PROTEIN_TOP}" "${PROTEIN_POSRE}"; do
    [[ -f "${f}" ]] && backup_file "${f}"
done

# pdb2gmx argümanlarını config'ten oluştur
pdb2gmx_args=(
    pdb2gmx
    -f "${PDB_IN}"
    -o "${PROTEIN_GRO}"
    -p "${PROTEIN_TOP}"
    -i "${PROTEIN_POSRE}"
    -ff "${FF_NAME}"
    -water "${WATER_MODEL}"
)
[[ "${PDB2GMX_IGNH}" == "yes" ]] && pdb2gmx_args+=(-ignh)
[[ "${PDB2GMX_MISSING}" == "yes" ]] && pdb2gmx_args+=(-missing)
[[ "${PDB2GMX_INTER}" == "no" ]] && pdb2gmx_args+=(-inter no)
[[ "${PDB2GMX_TER}" == "no" ]] && pdb2gmx_args+=(-ter no)

prep_confirm_gate "$(t gate_pdb2gmx)" \
    "$(t gate_in_pdb "${PDB_IN}")" \
    "$(t gate_ff "${FF_NAME}")" \
    "$(t gate_water "${WATER_MODEL}")" \
    "$(t gate_flags "${PDB2GMX_IGNH}" "${PDB2GMX_MISSING}" "${PDB2GMX_INTER}" "${PDB2GMX_TER}")" \
    "$(t gate_out "${PROTEIN_GRO}" "${PROTEIN_TOP}")" \
    "$(t gate_config_hint)"

run_gmx "pdb2gmx protein" -- "${pdb2gmx_args[@]}" \
    ::expect:: "${PROTEIN_GRO}" "${PROTEIN_TOP}" \
    || die "pdb2gmx başarısız (log: ${LOG_DIR}/gmx_pdb2gmx_protein_*.log)"

# TER + Zn ayrı zincir → pdb2gmx posre_Protein_chain_*.itp / posre_Ion_chain_*.itp yazar,
# tek posre.itp oluşturmaz. Pipeline uyumluluğu için stub veya mevcut dosyayı doğrula.
_finalize_pdb2gmx_posre() {
    if [[ -s "${PROTEIN_POSRE}" ]]; then
        log_ok "posre: ${PROTEIN_POSRE}"
        return 0
    fi

    local chain_posre=() f
    shopt -s nullglob
    for f in posre_*_chain_*.itp; do
        [[ -s "${f}" ]] && chain_posre+=("${f}")
    done
    shopt -u nullglob

    if [[ ${#chain_posre[@]} -eq 0 ]]; then
        die "pdb2gmx posre çıktısı yok (${PROTEIN_POSRE} veya posre_*_chain_*.itp)"
    fi

    log_info "Çoklu zincir posre (00b TER/Zn): ${chain_posre[*]}"
    {
        echo "; pdb2gmx multi-chain — position restraints chain itp içinde (#ifdef POSRES)"
        for f in "${chain_posre[@]}"; do
            echo ";   ${f}"
        done
    } >"${PROTEIN_POSRE}"
    log_ok "Uyumluluk: ${PROTEIN_POSRE} (gerçek posre zincir dosyalarında)"
}
_finalize_pdb2gmx_posre

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: çıktı doğrulaması ve checkpoint atlandı."
    exit 0
fi

# --- Doğrulama --------------------------------------------------------------
natoms_gro="$(awk 'NR==2 {gsub(/^[[:space:]]+|[[:space:]]+$/, ""); print; exit}' "${PROTEIN_GRO}")"
[[ "${natoms_gro}" =~ ^[0-9]+$ ]] && [[ "${natoms_gro}" -gt 0 ]] \
    || die "${PROTEIN_GRO} atom sayısı okunamadı (2. satır: '${natoms_gro}')"

grep -q '^\[ molecules \]' "${PROTEIN_TOP}" \
    || die "${PROTEIN_TOP} içinde [ molecules ] bölümü yok."

if ! grep -qE '^[[:space:]]*Protein[[:space:]]' "${PROTEIN_TOP}"; then
    log_warn "${PROTEIN_TOP}: 'Protein' satırı beklenen formatta değil; [ molecules ] bölümünü kontrol et."
fi

grep -qE "^[[:space:]]*#include[[:space:]]+\"${FF_NAME}\.ff/forcefield\.itp\"" "${PROTEIN_TOP}" \
    || log_warn "${PROTEIN_TOP}: forcefield.itp include satırı beklenen desenle eşleşmedi."

natom_pdb="$(grep -cE '^ATOM[[:space:]]+[0-9]+[[:space:]]+[A-Z0-9]{1,4}[[:space:]]+[A-Z]{3}[[:space:]]+[A-Z0-9]' \
    "${PROTEIN_PDB}" 2>/dev/null || echo 0)"
log_info "Protein PDB ATOM satırları: ${natom_pdb} (pdb2gmx -ignh ile H'ler yok sayılır)"
log_info "${PROTEIN_GRO} toplam atom: ${natoms_gro} (H + ağır atom, pdb2gmx sonrası)"

if [[ "${METAL_ENZYME}" == "yes" ]]; then
    log_info "--- CA/Zn doğrulama (kılavuz Adım 3) ---"
    for res in ${METAL_HSD_RESIDUES}; do
        if grep -qE "[[:space:]]${res}HSD[[:space:]]" "${PROTEIN_GRO}"; then
            if grep -E "[[:space:]]${res}HSD[[:space:]].*HE2" "${PROTEIN_GRO}" >/dev/null; then
                die "HSD ${res}: HE2 bulundu — NE2 boş kalmalı (HSE atanmış olabilir)."
            fi
            log_ok "HSD ${res}: NE2 boş (HE2 yok)."
        else
            log_warn "HSD ${res} ${PROTEIN_GRO} içinde bulunamadı."
        fi
    done
    if grep -qE "[[:space:]]${METAL_ION_RESNAME}[[:space:]]" "${PROTEIN_GRO}"; then
        log_ok "Metal iyon ${METAL_ION_RESNAME} ${PROTEIN_GRO} içinde."
    else
        log_warn "Metal iyon ${METAL_ION_RESNAME} ${PROTEIN_GRO} içinde YOK — pdb2gmx öncesi PDB'ye ekleyin."
    fi
    if grep -qE "^[[:space:]]*Ion_" "${PROTEIN_TOP}"; then
        log_ok "topol.top: iyon zinciri (Ion_chain_*) tanındı."
    else
        log_warn "topol.top: Ion_chain_* satırı yok (Zn ayrı zincir olarak işlenmemiş olabilir)."
    fi
fi

log_ok "Protein topolojisi doğrulandı."

mark_done "${STAGE}"
