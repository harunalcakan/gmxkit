#!/usr/bin/env bash
# =============================================================================
# 04_solvate_ions.sh - kutu, solvasyon, iyonlar, EM (yerel opsiyonel)
# Kaynak: script.py §7-9, step10.py, step11.py
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="04_solvate_ions"
NDX_PY="${MDPREP_DIR}/lib/ndx_tools.py"
TOP_PY="${MDPREP_DIR}/lib/top_tools.py"

stage_guard "${STAGE}" || exit 0

is_done "03_complex" || die "Önce: ./mdprep/run.sh stage 03"

log_info "================ SOLVASYON + İYONLAR (+ em.tpr) ================"
require_file "${COMPLEX_GRO}" "complex gro"
require_file "${PROTEIN_TOP}" "topoloji"
require_file "${IONS_MDP}" "ions mdp"
require_file "${EM_MDP}" "em mdp"

PY="$(find_python)" || die "python3 gerekli"
require_file "${NDX_PY}" "ndx_tools.py"
require_file "${TOP_PY}" "top_tools.py"

for f in "${NEWBOX_GRO}" "${SOLV_GRO}" "${SOLV_IONS_GRO}" "${EM_TPR}" "${EM_GRO}"; do
    [[ -f "${f}" ]] && backup_file "${f}"
done

prep_confirm_gate "Kutu ve solvasyon" \
    "Kutu tipi     : ${BOX_TYPE}  (editconf -bt)" \
    "Kenar mesafe  : ${BOX_DIST} nm  (editconf -d)" \
    "Su koordinat  : ${WATER_GRO}  (solvate -cs, ${WATER_MODEL} ile uyumlu)" \
    "Topoloji      : ${PROTEIN_TOP}"

# --- kutu -------------------------------------------------------------------
run_gmx "editconf box" -- editconf -f "${COMPLEX_GRO}" -o "${NEWBOX_GRO}" \
    -bt "${BOX_TYPE}" -d "${BOX_DIST}" \
    ::expect:: "${NEWBOX_GRO}" \
    || die "editconf kutu başarısız"

# --- solvasyon --------------------------------------------------------------
run_gmx "solvate" -- solvate -cp "${NEWBOX_GRO}" -cs "${WATER_GRO}" \
    -p "${PROTEIN_TOP}" -o "${SOLV_GRO}" \
    ::expect:: "${SOLV_GRO}" \
    || die "solvate başarısız"

# --- ions grompp ------------------------------------------------------------
run_gmx "grompp ions" -- grompp -f "${IONS_MDP}" -c "${SOLV_GRO}" \
    -p "${PROTEIN_TOP}" -o ions.tpr -maxwarn "${GROMPP_MAXWARN}" \
    ::expect:: ions.tpr \
    || die "ions grompp başarısız"

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: genion ve EM atlandı."
    log_info "  genion -> ${SOLV_IONS_GRO}"
    log_info "  grompp/mdrun em -> ${EM_TPR}, ${EM_GRO}"
    exit 0
fi

# --- genion (SOL grubu parse) -----------------------------------------------
sol_grp="$("${PY}" "${NDX_PY}" sol-group --gmx "${GMX}" "${SOLV_GRO}")" \
    || die "SOL grup numarası alınamadı"
log_info "genion: SOL grubu = ${sol_grp}"

prep_confirm_gate "genion — iyon ekleme" \
    "Değiştirilecek grup : ${sol_grp} (${SOLVENT_GROUP})  ← GROMACS'un sorduğu grup" \
    "Katyon / anyon       : ${ION_PNAME} / ${ION_NNAME}" \
    "Nötrleştir           : ${ION_NEUTRAL}" \
    "Konsantrasyon        : ${ION_CONC} M (boş = sadece nötr)" \
    "Çıktı                : ${SOLV_IONS_GRO}"

genion_args=(genion -s ions.tpr -o "${SOLV_IONS_GRO}" -p "${PROTEIN_TOP}"
    -pname "${ION_PNAME}" -nname "${ION_NNAME}")
[[ "${ION_NEUTRAL}" == "yes" ]] && genion_args+=(-neutral)
[[ -n "${ION_CONC}" ]] && genion_args+=(-conc "${ION_CONC}")

run_gmx_stdin "genion" "${sol_grp}\n" -- "${genion_args[@]}" \
    ::expect:: "${SOLV_IONS_GRO}" \
    || die "genion başarısız"

prep_confirm_gate "EM — grompp (mdrun kuyrukta)" \
    "MDP           : ${EM_MDP}" \
    "Girdi gro     : ${SOLV_IONS_GRO}" \
    "Çıktı tpr     : ${EM_TPR}" \
    "mdrun         : hazırlıkta YAPILMAZ → ./md queue submit em" \
    "LOCAL_EM_RUN  : ${LOCAL_EM_RUN} (yes ise burada mdrun da koşar)"

# --- EM grompp (+ opsiyonel mdrun) ------------------------------------------
_em_grompp() {
    run_gmx "grompp em" -- grompp -f "${EM_MDP}" -c "${SOLV_IONS_GRO}" \
        -p "${PROTEIN_TOP}" -o "${EM_TPR}" -maxwarn "${GROMPP_MAXWARN}" \
        ::expect:: "${EM_TPR}"
}

if ! _em_grompp; then
    log_warn "EM grompp başarısız — iyon adı düzeltmesi deneniyor..."
    backup_file "${PROTEIN_TOP}"
    backup_file "${SOLV_IONS_GRO}"
    run_cmd "${PY}" "${TOP_PY}" fix-ions "${PROTEIN_TOP}" "${SOLV_IONS_GRO}" \
        || die "iyon düzeltmesi başarısız"
    _em_grompp || die "EM grompp (düzeltme sonrası) başarısız"
fi

if [[ "${LOCAL_EM_RUN}" == "yes" ]]; then
    log_info "--- yerel EM (mdrun) ---"
    run_gmx "mdrun em" -- mdrun -v -deffnm em \
        ::expect:: "${EM_GRO}" \
        || die "EM mdrun başarısız"
    log_ok "Yerel EM tamamlandı: ${EM_GRO}"
    if [[ "${CHECK_BINDING:-yes}" == "yes" ]]; then
        if [[ -f "${INDEX_NDX}" ]]; then
            bash "${MDPREP_DIR}/lib/check_binding.sh" em \
                || [[ "${CHECK_BINDING_STRICT:-no}" != "yes" ]] \
                || die "EM sonrası binding check başarısız (CHECK_BINDING_STRICT=yes)"
        else
            log_info "Binding check atlandı (${INDEX_NDX} henüz yok — aşama 05 sonrası)."
        fi
    fi
else
    log_ok "EM grompp tamam: ${EM_TPR}"
    log_info "Sonraki adım: ./md → [J] Kuyruk → EM gönder (mdrun → ${EM_GRO})"
fi

log_ok "Solvasyon + iyonlar hazır: ${SOLV_IONS_GRO}"
mark_done "${STAGE}"
