#!/usr/bin/env bash
# Uçtan uca deneme: temizlik → prep 00–06 → kuyruk EM→NVT→NPT→MD (10 ps)
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${MDPREP_DIR}/.." && pwd)"
cd "${ROOT}"

# shellcheck source=lib/common.sh
source "${MDPREP_DIR}/lib/common.sh"

PS_PS=10
PS_STEPS=5000          # 10 ps @ dt=0.002
EM_MAX_STEPS=5000      # EM minimize üst sınırı (ps değil)
NSTXOUT=500            # ~10 frame / 10 ps traj
REPORT="${MDPREP_DIR}/logs/e2e_10ps_report.txt"

log_section() { echo ""; echo "======== $* ========"; }

backup_mdp() {
    mkdir -p "${MDPREP_DIR}/backups"
    for f in em.mdp nvt.mdp npt.mdp md.mdp; do
        cp -f "${f}" "${MDPREP_DIR}/backups/${f}.e2e10_bak"
    done
}

apply_test_mdp() {
    sed -i -E 's/^nsteps[[:space:]]*=.*/nsteps                  = '"${EM_MAX_STEPS}"'/' em.mdp
    for f in nvt.mdp npt.mdp md.mdp; do
        sed -i -E 's/^nsteps[[:space:]]*=.*/nsteps                  = '"${PS_STEPS}"'/' "${f}"
        sed -i -E 's/^nstxout-compressed[[:space:]]*=.*/nstxout-compressed      = '"${NSTXOUT}"'/' "${f}"
    done
    log_ok "MDP test: EM max ${EM_MAX_STEPS} adım, NVT/NPT/MD ${PS_STEPS} adım (${PS_PS} ps), nstxout=${NSTXOUT}"
}

restore_mdp() {
    for f in em.mdp nvt.mdp npt.mdp md.mdp; do
        local bak="${MDPREP_DIR}/backups/${f}.e2e10_bak"
        [[ -f "${bak}" ]] && cp -f "${bak}" "${f}"
    done
    log_info "MDP dosyaları yedekten geri yüklendi (e2e10_bak)."
}

deep_clean() {
    log_section "TEMİZLİK"
    CLEAN_YES=yes CLEAN_REMOVE_BACKUPS=no bash "${MDPREP_DIR}/lib/cleanup_workdir.sh" --yes
    rm -f "${STATE_DIR}/jobs.json" 2>/dev/null || true
    rm -rf "${LOG_DIR}/queue" "${LOG_DIR}/binding_checks" "${LOG_DIR}/analysis" 2>/dev/null || true
    rm -f "${ROOT}/md_pbc.xtc" 2>/dev/null || true
    shopt -s nullglob
    rm -f "${ROOT}"/posre_*.itp "${ROOT}"/topol_Protein*.itp "${ROOT}"/topol_Ion*.itp \
          "${ROOT}"/step13*.pdb "${ROOT}"/slurm-*.out "${ROOT}"/slurm-*.err 2>/dev/null || true
    shopt -u nullglob
    log_ok "Derin temizlik tamam."
}

run_prep() {
    log_section "HAZIRLIK 00–06"
    export PREP_INTERACTIVE=no
    export DRY_RUN=no
    export SKIP_MDP_AUTO_SYNC=yes
    bash "${MDPREP_DIR}/run.sh" all
    apply_test_mdp
}

run_queue_chain() {
    log_section "KUYRUK EM→NVT→NPT→MD (${PS_PS} ps)"
    # Zincir onayı + var olan çıktı için yeniden koş onayları
    printf 'y\ny\ny\ny\ny\n' | bash "${MDPREP_DIR}/lib/job_queue.sh" chain
}

wait_jobs() {
    log_section "JOB BEKLEME"
    bash "${MDPREP_DIR}/lib/job_queue.sh" export-env 2>/dev/null || true
    local py
    py="$("${MDPREP_DIR}/.venv/bin/python3" 2>/dev/null || command -v python3)"
    export MDQUEUE_MDPREP_DIR="${MDPREP_DIR}"
    export MDQUEUE_WORKDIR="${ROOT}"
    export MDQUEUE_STATE_DIR="${STATE_DIR}"
    export MDQUEUE_LOG_DIR="${LOG_DIR}/queue"
    export MDQUEUE_JOBS_FILE="${STATE_DIR}/jobs.json"
    "${py}" "${MDPREP_DIR}/lib/md_queue.py" wait-all || die "Kuyruk job'ları başarısız"
    log_ok "Tüm job'lar bitti."
}

audit_files() {
    log_section "DOSYA DENETİMİ"
    mkdir -p "${MDPREP_DIR}/logs"
    : >"${REPORT}"
    {
        echo "E2E ${PS_PS} ps deneme — $(date -Iseconds)"
        echo "WORKDIR: ${ROOT}"
        echo "nsteps NVT/NPT/MD: ${PS_STEPS}"
        echo ""
    } >>"${REPORT}"

    local ok=0 fail=0
    _check() {
        local f="$1" note="${2:-}" line
        if [[ -f "${ROOT}/${f}" ]] && [[ -s "${ROOT}/${f}" ]]; then
            line="  OK   ${f}  ${note}"
            ok=$((ok + 1))
        else
            line="  EKSIK ${f}  ${note}"
            fail=$((fail + 1))
        fi
        echo "${line}"
        echo "${line}" >>"${REPORT}"
    }

    echo "--- Hazırlık ---" | tee -a "${REPORT}"
    _check protein_prep.pdb "00b"
    _check processed.gro "01"
    _check topol.top "01"
    _check lig.itp "02"
    _check ligand.gro "02"
    _check complex.gro "03"
    _check solv_ions.gro "04"
    _check em.tpr "04"
    _check index.ndx "05"
    _check posre_lig.itp "05"
    _check run_local_md.sh "06"

    echo "--- Simülasyon (${PS_PS} ps) ---" | tee -a "${REPORT}"
    _check em.gro "EM"
    _check nvt.gro "NVT"
    _check nvt.cpt "NVT ckpt"
    _check npt.gro "NPT"
    _check npt.cpt "NPT ckpt"
    _check md_0_1.gro "MD"
    _check md_0_1.xtc "MD traj"

    echo "" >>"${REPORT}"
    echo "MDP nsteps:" >>"${REPORT}"
    grep '^nsteps' em.mdp nvt.mdp npt.mdp md.mdp >>"${REPORT}" 2>/dev/null || true

    if [[ -f md_0_1.xtc ]]; then
        echo "" >>"${REPORT}"
        echo "MD traj frame sayısı:" >>"${REPORT}"
        gmx check -f md_0_1.xtc 2>&1 | awk '/^Coords/ {print "  Coords:", $2}' >>"${REPORT}" || true
    fi

    echo "" >>"${REPORT}"
    echo "Özet: OK=${ok}  EKSIK=${fail}" >>"${REPORT}"
    cat "${REPORT}"
    [[ "${fail}" -eq 0 ]]
}

post_analyze() {
    log_section "ANALİZ"
    bash "${MDPREP_DIR}/lib/analyze_md.sh" all 2>&1 | tee -a "${MDPREP_DIR}/logs/e2e_10ps_analyze.log" || true
}

main() {
    mkdir -p "${MDPREP_DIR}/backups"
    case "${1:-}" in
        --audit-only) audit_files && log_ok "Audit OK" || exit 1; return 0 ;;
        --analyze-only) post_analyze; return 0 ;;
        --resume-queue)
            apply_test_mdp
            run_queue_chain
            wait_jobs
            audit_files || { log_warn "Eksik dosya — rapor: ${REPORT}"; exit 1; }
            post_analyze
            restore_mdp
            log_ok "E2E ${PS_PS} ps BAŞARILI — ${REPORT}"
            return 0
            ;;
    esac
    backup_mdp
    deep_clean
    run_prep
    run_queue_chain
    wait_jobs
    audit_files || { log_warn "Eksik dosya — rapor: ${REPORT}"; exit 1; }
    post_analyze
    restore_mdp
    log_ok "E2E ${PS_PS} ps BAŞARILI — ${REPORT}"
}

main "$@"
