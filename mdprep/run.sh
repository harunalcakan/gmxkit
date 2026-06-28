#!/usr/bin/env bash
# =============================================================================
# run.sh - GROMACS protein-ligand MD hazırlık pipeline orkestratörü
#
# Kullanım:
#   ./run.sh                 # tüm aşamaları sırayla (kaldığı yerden devam eder)
#   ./run.sh check           # sadece ortam kontrolü
#   ./run.sh stage 02        # sadece tek aşama çalıştır
#   ./run.sh list            # aşamaları ve durumlarını göster
#   ./run.sh setup [--system|--conda]  # bağımlılık kurulumu
#
# Bayraklar (ortam değişkeni):
#   DRY_RUN=yes ./run.sh     # komutları çalıştırmadan dene
#   FORCE=1 ./run.sh stage 03  # tamamlanmış aşamayı zorla tekrar çalıştır
#   ./run.sh clean [--dry-run]   # üretilmiş dosyaları sil (girdiler kalır)
# =============================================================================
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAGES_DIR="${MDPREP_DIR}/stages"

# Aşama listesi (sıralı). Stage 06 RUN_TARGET'a göre değişir.
if [[ "${RUN_TARGET:-local}" == "truba" ]]; then
    STAGE_06="06_truba_pack"
else
    STAGE_06="06_local_md"
fi
STAGES=(
    "00_check_env"
    "00b_prepare_metallo"
    "01_protein"
    "02_ligand"
    "03_complex"
    "04_solvate_ions"
    "05_index_posre"
    "${STAGE_06}"
)

source "${MDPREP_DIR}/lib/common.sh"

run_stage() {
    local name="$1"
    local script="${STAGES_DIR}/${name}.sh"
    [[ -f "${script}" ]] || die "Aşama script'i yok: ${script}"
    log_info "######## AŞAMA: ${name} ########"
    bash "${script}"
}

cmd="${1:-all}"
case "${cmd}" in
    check)
        run_stage "00_check_env"
        ;;
    setup)
        shift
        bash "${MDPREP_DIR}/setup_env.sh" "$@"
        ;;
    list)
        printf '\n%-20s %s\n' "AŞAMA" "DURUM"
        printf '%-20s %s\n' "--------------------" "------"
        for s in "${STAGES[@]}"; do
            if is_done "${s}"; then st="${C_GRN}tamamlandı${C_RST}"; else st="${C_DIM}bekliyor${C_RST}"; fi
            printf '%-20s %b\n' "${s}" "${st}"
        done
        echo
        ;;
    reset)
        if confirm "Tüm checkpoint'ler silinsin mi? (üretilen dosyalara DOKUNULMAZ)"; then
            rm -f "${STATE_DIR}"/*.done 2>/dev/null || true
            log_ok "Checkpoint'ler temizlendi."
        fi
        ;;
    clean|cleanup)
        shift || true
        bash "${MDPREP_DIR}/lib/cleanup_workdir.sh" "$@"
        ;;
    stage)
        target="${2:-}"
        [[ -n "${target}" ]] || die "Aşama numarası/adı ver: ./run.sh stage 02"
        match=""
        for s in "${STAGES[@]}"; do [[ "${s}" == ${target}* ]] && match="${s}" && break; done
        if [[ -z "${match}" && "${target}" == "06_truba" ]]; then
            match="06_truba_pack"
        fi
        [[ -n "${match}" ]] || die "Eşleşen aşama yok: '${target}'"
        run_stage "${match}"
        ;;
    all)
        log_info "Pipeline başlıyor (kaldığı yerden devam). DRY_RUN=${DRY_RUN}"
        for s in "${STAGES[@]}"; do
            run_stage "${s}"
        done
        log_ok "Tüm tanımlı aşamalar tamamlandı."
        ;;
    *)
        die "Bilinmeyen komut: '${cmd}'. (check|setup|list|reset|clean|stage|all)"
        ;;
esac
