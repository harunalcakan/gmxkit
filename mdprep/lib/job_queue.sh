#!/usr/bin/env bash
# =============================================================================
# job_queue.sh — EM / NVT / NPT / MD kuyruk yönetimi
#
# Varsayılan: yerel iş istasyonu (rg16.py tarzı — PID + jobs.json)
# Opsiyonel:  QUEUE_BACKEND=slurm → TRUBA sbatch (manuel upload)
#
#   ./md queue              etkileşimli menü
#   ./md queue submit em    tek iş
#   ./md queue chain        EM→NVT→NPT→MD (sıralı bağımlılık)
#   ./md queue status       job tablosu
#   ./md queue cancel ID    iptal (abort)
# =============================================================================
set -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

MD_QUEUE_PY="${MDPREP_DIR}/lib/md_queue.py"
JOBS_JSON="${STATE_DIR}/jobs.json"
JOBS_TSV="${STATE_DIR}/jobs.tsv"
QUEUE_LOG_DIR="${LOG_DIR}/queue"
QUEUE_PHASES=( "em" "nvt" "npt" "md" )

_queue_backend() {
    echo "${QUEUE_BACKEND:-local}"
}

_queue_python() {
    if [[ -x "${MDPREP_DIR}/.venv/bin/python3" ]]; then
        echo "${MDPREP_DIR}/.venv/bin/python3"
    elif command -v python3 >/dev/null 2>&1; then
        command -v python3
    else
        die "python3 gerekli (md_queue.py)"
    fi
}

_export_queue_env() {
    export MDQUEUE_MDPREP_DIR="${MDPREP_DIR}"
    export MDQUEUE_WORKDIR="${WORKDIR}"
    export MDQUEUE_STATE_DIR="${STATE_DIR}"
    export MDQUEUE_LOG_DIR="${QUEUE_LOG_DIR}"
    export MDQUEUE_JOBS_FILE="${JOBS_JSON}"
    export MDLANG="${MDLANG:-en}"
    export MDQUEUE_GMX="${GMX}"
    export MDQUEUE_MDRUN_EXTRA="${GMX_MDRUN_EXTRA}"
    export MDQUEUE_MAXWARN="${GROMPP_MAXWARN}"
    export MDQUEUE_EM_MDP="${EM_MDP}"
    export MDQUEUE_SOLV_IONS="${SOLV_IONS_GRO}"
    export MDQUEUE_TOP="${PROTEIN_TOP}"
    export MDQUEUE_NDX="${INDEX_NDX}"
    export MDQUEUE_EM_GRO="${EM_GRO}"
    export MDQUEUE_NVT_DEFFNM="${NVT_DEFFNM}"
    export MDQUEUE_NPT_DEFFNM="${NPT_DEFFNM}"
    export MDQUEUE_PROD_DEFFNM="${PROD_DEFFNM}"
    export MDQUEUE_RUN_SCRIPT="${WORKDIR}/run_local_md.sh"
    mkdir -p "${QUEUE_LOG_DIR}"
}

_local_queue() {
    local py
    py="$(_queue_python)"
    _export_queue_env
    "${py}" "${MD_QUEUE_PY}" "$@"
}

# --- Slurm (opsiyonel, QUEUE_BACKEND=slurm) ----------------------------------

_slurm_for_phase() {
    case "$1" in
        em)  echo "${SLURM_EM}" ;;
        nvt) echo "${SLURM_NVT}" ;;
        npt) echo "${SLURM_NPT}" ;;
        md)  echo "${SLURM_MD}" ;;
        *)   return 1 ;;
    esac
}

_prev_phase() {
    case "$1" in
        nvt) echo "em" ;;
        npt) echo "nvt" ;;
        md)  echo "npt" ;;
        *)   echo "" ;;
    esac
}

_jobs_init_tsv() {
    [[ -f "${JOBS_TSV}" ]] || {
        printf '# phase\tjob_id\tslurm\tdependency\tsubmitted_at\tstatus\n' >"${JOBS_TSV}"
    }
}

_record_slurm_job() {
    local phase="$1" jid="$2" slurm="$3" dep="${4:-}"
    local ts
    ts="$(date -Iseconds 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')"
    _jobs_init_tsv
    printf '%s\t%s\t%s\t%s\t%s\tsubmitted\n' \
        "${phase}" "${jid}" "${slurm}" "${dep}" "${ts}" >>"${JOBS_TSV}"
}

_get_slurm_job_id() {
    local phase="$1"
    [[ -f "${JOBS_TSV}" ]] || return 1
    awk -F'\t' -v p="${phase}" '
        $1 == p && $2 ~ /^[0-9]+$/ { id = $2 }
        END { if (id != "") print id; else exit 1 }
    ' "${JOBS_TSV}"
}

_have_slurm() {
    command -v sbatch >/dev/null 2>&1
}

_preview_slurm() {
    local f="$1" n="${2:-18}"
    echo "── ${f} (ilk ${n} satır) ──"
    head -n "${n}" "${f}" 2>/dev/null || true
    echo "────────────────────────"
}

_confirm() {
    local msg="${1:-Devam?}"
    read -r -p "${msg} [Y/n] " ans
    [[ ! "${ans}" =~ ^[nN] ]]
}

_maybe_edit() {
    local f="$1"
    read -r -p "Slurm dosyasını düzenle? [e/N] " ans
    if [[ "${ans}" =~ ^[eE] ]]; then
        "${EDITOR:-nano}" "${f}"
    fi
}

slurm_pack() {
    log_info "Slurm paketi üretiliyor (06_truba_pack)..."
    RUN_TARGET=truba FORCE=1 bash "${MDPREP_DIR}/stages/06_truba_pack.sh"
    for ph in "${QUEUE_PHASES[@]}"; do
        local sf
        sf="$(_slurm_for_phase "${ph}")"
        [[ -f "${WORKDIR}/${sf}" ]] && log_ok "var: ${sf}" || log_warn "eksik: ${sf}"
    done
}

slurm_submit_one() {
    local phase="${1:-}"
    [[ -n "${phase}" ]] || die "Faz: em | nvt | npt | md"
    local slurm
    slurm="$(_slurm_for_phase "${phase}")" || die "Bilinmeyen faz: ${phase}"
    require_file "${slurm}" "${slurm} — önce: ./md queue pack"

    if ! _have_slurm; then
        log_warn "sbatch yok — slurm dosyalarını TRUBA'ya kopyalayıp orada sbatch kullanın"
        _preview_slurm "${slurm}" 20
        log_info "Manuel: sbatch ${slurm}"
        return 1
    fi

    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║  SLURM: ${phase^^}"
    echo "╚══════════════════════════════════════════╝"
    _preview_slurm "${slurm}" 16
    _maybe_edit "${slurm}"

    local dep="" prev prev_jid
    prev="$(_prev_phase "${phase}")"
    if [[ -n "${prev}" ]] && prev_jid="$(_get_slurm_job_id "${prev}" 2>/dev/null)"; then
        echo "  Önceki adım (${prev}): Job ID ${prev_jid}"
        if _confirm "Bağımlılık afterok:${prev_jid} eklensin mi?"; then
            dep="afterok:${prev_jid}"
        fi
    fi

    _confirm "sbatch ${slurm}${dep:+ ( --dependency=${dep} )}?" || return 0

    local jid sbatch_args=(--parsable)
    [[ -n "${dep}" ]] && sbatch_args+=(--dependency="${dep}")
    jid="$(sbatch "${sbatch_args[@]}" "${slurm}")" || die "sbatch başarısız"
    _record_slurm_job "${phase}" "${jid}" "${slurm}" "${dep}"
    log_ok "${phase^^} gönderildi → Slurm Job ID: ${jid}"
}

slurm_submit_chain() {
    local slurm dep="" jid phase
    if ! _have_slurm; then
        die "sbatch yok — slurm dosyalarını cluster'da çalıştırın"
    fi
    for phase in "${QUEUE_PHASES[@]}"; do
        slurm="$(_slurm_for_phase "${phase}")"
        require_file "${slurm}" "${slurm}"
    done

    echo ""
    echo "Zincir: EM → NVT → NPT → MD (Slurm afterok)"
    _confirm "Tüm zincir kuyruğa gönderilsin mi?" || return 0

    dep=""
    for phase in "${QUEUE_PHASES[@]}"; do
        slurm="$(_slurm_for_phase "${phase}")"
        if [[ -n "${dep}" ]]; then
            jid="$(sbatch --parsable --dependency="afterok:${dep}" "${slurm}")"
        else
            jid="$(sbatch --parsable "${slurm}")"
        fi
        _record_slurm_job "${phase}" "${jid}" "${slurm}" "${dep:+afterok:${dep}}"
        log_ok "${phase^^} → Slurm Job ID ${jid}"
        dep="${jid}"
    done
    log_ok "Zincir tamam. Son job: ${jid}"
}

slurm_status() {
    _jobs_init_tsv
    echo ""
    echo "=== Slurm kayıtları (${JOBS_TSV}) ==="
    column -t -s $'\t' "${JOBS_TSV}" 2>/dev/null || cat "${JOBS_TSV}"
    if _have_slurm; then
        local ids
        ids="$(awk -F'\t' '$2 ~ /^[0-9]+$/ {print $2}' "${JOBS_TSV}" | sort -u | tr '\n' ',' | sed 's/,$//')"
        [[ -n "${ids}" ]] && squeue -j "${ids}" 2>/dev/null
    fi
}

slurm_cancel() {
    local jid="${1:-}"
    [[ -n "${jid}" ]] || die "Job ID: ./md queue cancel 12345"
    _have_slurm || die "scancel için sbatch ortamı gerekli"
    _confirm "scancel ${jid}?" || return 0
    scancel "${jid}"
    log_ok "İptal edildi: ${jid}"
}

slurm_menu() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║  KUYRUK (Slurm — QUEUE_BACKEND=slurm)    ║"
        echo "╚══════════════════════════════════════════╝"
        echo "  sbatch: $(_have_slurm && echo evet || echo "hayir — cluster ortaminda sbatch")"
        echo ""
        echo "  1) Slurm paketi üret"
        echo "  2) EM gönder   3) NVT   4) NPT   5) MD"
        echo "  6) Zincir (afterok)"
        echo "  7) Durum (jobs.tsv + squeue)"
        echo "  8) İptal (scancel)"
        echo "  0) Ana menü"
        read -r -p "Seçim: " c
        case "${c}" in
            0) return 0 ;;
            1) slurm_pack; _pause_queue ;;
            2) slurm_submit_one em; _pause_queue ;;
            3) slurm_submit_one nvt; _pause_queue ;;
            4) slurm_submit_one npt; _pause_queue ;;
            5) slurm_submit_one md; _pause_queue ;;
            6) slurm_submit_chain; _pause_queue ;;
            7) slurm_status; _pause_queue ;;
            8)
                read -r -p "Slurm Job ID: " jid
                [[ -n "${jid}" ]] && slurm_cancel "${jid}"
                _pause_queue
                ;;
            *) log_warn "Geçersiz seçim." ;;
        esac
    done
}

# --- Ortak giriş -------------------------------------------------------------

_pause_queue() {
    echo ""
    read -r -p "↵ ENTER... " _ || true
}

usage_queue() {
    local backend
    backend="$(_queue_backend)"
    cat <<EOF
Kuyruk komutları (backend=${backend}):

  ./md queue              menü
  ./md queue submit em    tek iş (em|nvt|npt|md)
  ./md queue chain        EM→MD zinciri
  ./md queue status       job tablosu (-w canlı izle)
  ./md queue cancel ID    iptal (yerelde md_N veya all)

Yerel kayıt: ${JOBS_JSON}
Slurm kayıt:  ${JOBS_TSV}  (QUEUE_BACKEND=slurm)

QUEUE_BACKEND=local  (varsayılan) — arka plan gmx, PID izleme
QUEUE_BACKEND=slurm  — sbatch/scancel (cluster)
EOF
}

main_queue() {
    local sub="${1:-menu}"
    shift || true

    if [[ "$(_queue_backend)" == "slurm" ]]; then
        case "${sub}" in
            menu|"") slurm_menu ;;
            pack) slurm_pack ;;
            submit) slurm_submit_one "${1:-}" ;;
            chain) slurm_submit_chain ;;
        status|list) slurm_status ;;
        summary) slurm_status ;;
        cancel) slurm_cancel "${1:-}" ;;
            help|-h) usage_queue ;;
            *) die "Bilinmeyen: queue ${sub}. ./md queue help" ;;
        esac
        return 0
    fi

    case "${sub}" in
        menu|"") _local_queue menu ;;
        submit) _local_queue submit "${1:-}" ;;
        chain) _local_queue chain ;;
        status|list) _local_queue status "$@" ;;
        summary) _local_queue summary ;;
        recommend) _local_queue recommend ;;
        cancel|abort) _local_queue abort "${1:-}" ;;
        tail) _local_queue tail "${1:-}" ;;
        help|-h) usage_queue ;;
        *) die "Bilinmeyen: queue ${sub}. ./md queue help" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main_queue "$@"
fi
