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

source "${MDPREP_DIR}/lib/common.sh"
# shellcheck source=stages.sh
source "${MDPREP_DIR}/lib/stages.sh"
stages_init

run_stage() {
    local name="$1"
    local script="${STAGES_DIR}/${name}.sh"
    [[ -f "${script}" ]] || die "$(t run_err_script "${script}")"
    log_info "$(t run_stage_hdr "${name}")"
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
        printf '\n%-8s %-20s %s\n' "#" "$(t run_list_short)" "$(t run_list_status)"
        printf '%-8s %-20s %s\n' "--------" "--------------------" "------"
        local i
        for i in "${!STAGES[@]}"; do
            if is_done "${STAGES[$i]}"; then st="${C_GRN}$(t run_done)${C_RST}"; else st="${C_DIM}$(t run_pending)${C_RST}"; fi
            printf '%-8s %-20s %b\n' "$((i + 1))" "${STAGE_SHORTS[$i]}" "${st}"
        done
        echo
        ;;
    reset)
        if confirm "$(t run_reset_confirm)"; then
            rm -f "${STATE_DIR}"/*.done 2>/dev/null || true
            log_ok "$(t run_reset_ok)"
        fi
        ;;
    clean|cleanup)
        shift || true
        bash "${MDPREP_DIR}/lib/cleanup_workdir.sh" "$@"
        ;;
    stage)
        target="${2:-}"
        [[ -n "${target}" ]] || die "$(t run_err_stage_arg)"
        match=""
        if match="$(resolve_stage_name "${target}")"; then
            run_stage "${match}"
        else
            die "$(t run_err_no_match "${target}")"
        fi
        ;;
    all)
        log_info "$(t run_all_start "${DRY_RUN}")"
        for s in "${STAGES[@]}"; do
            run_stage "${s}"
        done
        log_ok "$(t run_all_done)"
        ;;
    *)
        die "$(t run_err_unknown "${cmd}")"
        ;;
esac
