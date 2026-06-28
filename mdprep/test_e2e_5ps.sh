#!/usr/bin/env bash
# Uçtan uca deneme: temizlik → prep 00–06 → kuyruk EM→NVT→NPT→MD (5 ps)
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${MDPREP_DIR}/.." && pwd)"
cd "${ROOT}"

# shellcheck source=lib/common.sh
source "${MDPREP_DIR}/lib/common.sh"

PS_STEPS=2500          # 5 ps @ dt=0.002
EM_MAX_STEPS=5000      # hızlı EM (minimizasyon; ps değil)
REPORT="${MDPREP_DIR}/logs/e2e_5ps_report.txt"

log_section() { echo ""; echo "======== $* ========"; }

backup_mdp() {
    for f in em.mdp nvt.mdp npt.mdp md.mdp; do
        cp -f "${f}" "${MDPREP_DIR}/backups/${f}.e2e_bak" 2>/dev/null || cp -f "${f}" "${f}.e2e_bak"
    done
}

apply_test_mdp() {
    sed -i -E 's/^nsteps[[:space:]]*=.*/nsteps                  = '"${EM_MAX_STEPS}"'/' em.mdp
    sed -i -E 's/^nsteps[[:space:]]*=.*/nsteps                  = '"${PS_STEPS}"'/' nvt.mdp
    sed -i -E 's/^nsteps[[:space:]]*=.*/nsteps                  = '"${PS_STEPS}"'/' npt.mdp
    sed -i -E 's/^nsteps[[:space:]]*=.*/nsteps                  = '"${PS_STEPS}"'/' md.mdp
    log_ok "MDP test süreleri: EM max ${EM_MAX_STEPS} adım, NVT/NPT/MD ${PS_STEPS} adım (5 ps)"
}

restore_mdp() {
    for f in em.mdp nvt.mdp npt.mdp md.mdp; do
        local bak="${MDPREP_DIR}/backups/${f}.e2e_bak"
        [[ -f "${bak}" ]] && cp -f "${bak}" "${f}"
    done
    log_info "MDP dosyaları yedekten geri yüklendi (varsa)."
}

deep_clean() {
    log_section "TEMİZLİK"
    CLEAN_YES=yes CLEAN_REMOVE_BACKUPS=yes bash "${MDPREP_DIR}/lib/cleanup_workdir.sh" --yes --remove-backups
    rm -f "${STATE_DIR}/jobs.json" 2>/dev/null || true
    rm -rf "${LOG_DIR}/queue" "${LOG_DIR}/binding_checks" 2>/dev/null || true
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
    log_section "KUYRUK EM→NVT→NPT→MD"
    printf 'y\n' | bash "${MDPREP_DIR}/lib/job_queue.sh" chain
}

wait_jobs() {
    log_section "JOB BEKLEME"
    local py
    py="$("${MDPREP_DIR}/.venv/bin/python3" 2>/dev/null || command -v python3)"
    local n=0
    while true; do
        "${py}" "${MDPREP_DIR}/lib/md_queue.py" status >/dev/null 2>&1 || true
        local running
        running="$("${py}" -c "
import json, os
p=os.path.join('${MDPREP_DIR}/.state/jobs.json')
if not os.path.exists(p): print(0); exit()
j=json.load(open(p))
print(sum(1 for x in j if x.get('status')=='Running'))
" 2>/dev/null || echo 0)"
        log_info "Çalışan job: ${running}"
        [[ "${running}" -eq 0 ]] && break
        n=$((n + 1))
        [[ "${n}" -gt 360 ]] && die "Job bekleme zaman aşımı (3 saat)"
        sleep 15
    done
    log_ok "Tüm job'lar bitti."
}

audit_files() {
    log_section "DOSYA DENETİMİ"
    mkdir -p "${MDPREP_DIR}/logs"
    : >"${REPORT}"
    {
        echo "E2E 5 ps deneme — $(date -Iseconds)"
        echo "WORKDIR: ${ROOT}"
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

    echo "--- Hazırlık çıktıları ---" | tee -a "${REPORT}"
    _check protein_prep.pdb "00b"
    _check processed.gro "01"
    _check topol.top "01"
    _check lig.itp "02"
    _check ligand.gro "02"
    _check complex.gro "03"
    _check solv_ions.gro "04"
    _check em.tpr "04 grompp"
    _check index.ndx "05"
    _check posre_lig.itp "05"
    _check run_local_md.sh "06"
    _check check_binding.sh "06"

    echo "--- Simülasyon çıktıları ---" | tee -a "${REPORT}"
    _check em.gro "EM mdrun"
    _check nvt.gro "NVT 5 ps"
    _check nvt.cpt "NVT checkpoint"
    _check npt.gro "NPT 5 ps"
    _check npt.cpt "NPT checkpoint"
    _check md_0_1.gro "MD 5 ps"
    _check md_0_1.xtc "MD traj (varsa)"

    echo "" >>"${REPORT}"
    echo "Index grupları:" >>"${REPORT}"
    grep -E '^\[' index.ndx 2>/dev/null | head -20 >>"${REPORT}" || echo "  index.ndx yok" >>"${REPORT}"

    echo "" >>"${REPORT}"
    echo "tc-grps (nvt.mdp):" >>"${REPORT}"
    grep tc-grps nvt.mdp >>"${REPORT}" 2>/dev/null || true

    echo "" >>"${REPORT}"
    echo "Özet: OK=${ok}  EKSIK=${fail}" >>"${REPORT}"

    if [[ -f em.gro ]]; then
        echo "" >>"${REPORT}"
        echo "HSD/ZN (processed/em):" >>"${REPORT}"
        grep -E '94HSD|96HSD|119HSD| ZN ' em.gro 2>/dev/null | head -5 >>"${REPORT}" || true
    fi

    cat "${REPORT}"
    [[ "${fail}" -eq 0 ]]
}

main() {
    mkdir -p "${MDPREP_DIR}/backups"
    if [[ "${1:-}" == "--audit-only" ]]; then
        audit_files && log_ok "Audit OK" || exit 1
        return 0
    fi
    if [[ "${1:-}" == "--resume-queue" ]]; then
        apply_test_mdp
        run_queue_chain
        wait_jobs
        audit_files && log_ok "E2E BAŞARILI" || exit 1
        restore_mdp
        return 0
    fi
    backup_mdp
    apply_test_mdp
    deep_clean
    run_prep
    run_queue_chain
    wait_jobs
    if audit_files; then
        log_ok "E2E deneme BAŞARILI — rapor: ${REPORT}"
    else
        log_warn "E2E deneme TAMAMLANDI ama eksik dosya var — rapor: ${REPORT}"
        exit 1
    fi
    restore_mdp
}

main "$@"
