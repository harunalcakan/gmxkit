#!/usr/bin/env bash
# =============================================================================
# common.sh - Pipeline çapraz-kesen altyapısı
#   * loglama (renkli + dosyaya)
#   * güvenli komut çalıştırma (dry-run + log)
#   * gmx sarmalayıcı (exit code + beklenen çıktı doğrulaması + log taraması)
#   * dosya/komut varlık kontrolü
#   * yedekleme (in-place düzenleme öncesi)
#   * checkpoint / resume
#   * kullanıcı kapısı (manuel adımlar için)
#
# Bu dosya stage script'leri tarafından "source" edilir; tek başına çalışmaz.
# =============================================================================

set -o errexit
set -o nounset
set -o pipefail

# --- Dizinler ---------------------------------------------------------------
# MDPREP_DIR = bu lib'in iki üst klasörü (mdprep/)
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"

# config.sh'i yükle
# shellcheck source=/dev/null
source "${MDPREP_DIR}/config.sh"

# shellcheck source=/dev/null
source "${MDPREP_DIR}/lib/i18n.sh"
load_i18n

GMXKIT_HOME="$(cd "${MDPREP_DIR}/.." && pwd)"
export GMXKIT_HOME

_resolve_workdir() {
    local w="" cwd
    if [[ -n "${GMXKIT_WORKDIR:-}" ]]; then
        w="$(cd "${GMXKIT_WORKDIR}" && pwd)"
    elif [[ -n "${WORKDIR}" ]]; then
        w="$(cd "${WORKDIR}" && pwd)"
    else
        w="$(pwd)"
    fi
    printf '%s' "${w}"
}

is_install_home() {
    [[ "${WORKDIR}" == "${GMXKIT_HOME}" ]]
}

project_has_inputs() {
    [[ -f "${WORKDIR}/${PROTEIN_PDB}" && -f "${WORKDIR}/${LIGAND_MOL2}" ]]
}

project_usable() {
    ! is_install_home && project_has_inputs
}

WORKDIR="$(_resolve_workdir)"
export GMXKIT_WORKDIR="${WORKDIR}"

if [[ -f "${WORKDIR}/gmxkit.env" ]]; then
    # shellcheck source=/dev/null
    source "${WORKDIR}/gmxkit.env"
fi

mol2_molecule_name() {
    local mol2="${1:-${WORKDIR}/${LIGAND_MOL2}}"
    [[ -f "${mol2}" ]] || return 1
    awk '/@<TRIPOS>MOLECULE/{getline; gsub(/[[:space:]]/,"",$0); print; exit}' "${mol2}"
}

mol2_residue_name() {
    local mol2="${1:-${WORKDIR}/${LIGAND_MOL2}}"
    [[ -f "${mol2}" ]] || return 1
    awk '/@<TRIPOS>SUBSTRUCTURE/{print $2; exit}' "${mol2}"
}

sync_lig_resname_from_mol2() {
    local res="" env_file="${WORKDIR}/gmxkit.env"
    [[ -f "${WORKDIR}/${LIGAND_MOL2}" ]] || return 0
    res="$(mol2_residue_name "${WORKDIR}/${LIGAND_MOL2}" 2>/dev/null || true)"
    [[ -n "${res}" ]] || return 0
    if [[ -f "${env_file}" ]] && grep -q '^LIG_RESNAME=' "${env_file}" 2>/dev/null; then
        return 0
    fi
    LIG_RESNAME="${res}"
    if [[ -z "${CHECK_LIG_RESNAME:-}" ]] || [[ "${CHECK_LIG_RESNAME}" == "LIG" ]]; then
        CHECK_LIG_RESNAME="${res}"
    fi
}

sync_lig_resname_from_mol2

if [[ -z "${CHECK_LIG_RESNAME:-}" ]]; then
    CHECK_LIG_RESNAME="${LIG_RESNAME}"
fi

_is_install_check() {
    [[ "${GMXKIT_CHECK_SCOPE:-}" == "install" ]] && return 0
    [[ "${WORKDIR}" == "${GMXKIT_HOME}" \
        && ! -f "${WORKDIR}/${PROTEIN_PDB}" \
        && ! -f "${WORKDIR}/${LIGAND_MOL2}" ]] && return 0
    return 1
}

LOG_DIR="${WORKDIR}/.gmxkit/logs"
STATE_DIR="${WORKDIR}/.gmxkit/state"
BACKUP_DIR="${WORKDIR}/.gmxkit/backups"
if is_install_home || project_has_inputs; then
    mkdir -p "${LOG_DIR}" "${STATE_DIR}" "${BACKUP_DIR}"
fi

_ensure_project_ff() {
    [[ -e "${WORKDIR}/${FF_DIR}" ]] && return 0
    [[ -d "${GMXKIT_HOME}/${FF_DIR}" ]] || return 0
    ln -snf "${GMXKIT_HOME}/${FF_DIR}" "${WORKDIR}/${FF_DIR}"
}

# Scaffold project folder (templates + FF symlink) — never mutate install home
_scaffold_project_dir() {
    local target="$1"
    [[ "${target}" != "${GMXKIT_HOME}" ]] || return 0
    [[ -f "${target}/${PROTEIN_PDB}" && -f "${target}/${LIGAND_MOL2}" ]] || return 0

    mkdir -p "${target}/.gmxkit/logs" "${target}/.gmxkit/state" "${target}/.gmxkit/backups"

    local f
    for f in em.mdp nvt.mdp npt.mdp md.mdp ions.mdp; do
        [[ ! -f "${target}/${f}" && -f "${GMXKIT_HOME}/${f}" ]] && \
            cp -f "${GMXKIT_HOME}/${f}" "${target}/${f}"
    done

    for f in sort_mol2_bonds.pl cgenff_charmm2gmx_py3_nx2.py cgenff_charmm2gmx_py2.py; do
        [[ ! -e "${target}/${f}" && -f "${GMXKIT_HOME}/${f}" ]] && \
            ln -snf "${GMXKIT_HOME}/${f}" "${target}/${f}"
    done

    if [[ ! -e "${target}/${FF_DIR}" && -d "${GMXKIT_HOME}/${FF_DIR}" ]]; then
        ln -snf "${GMXKIT_HOME}/${FF_DIR}" "${target}/${FF_DIR}"
    fi

    if [[ ! -f "${target}/gmxkit.env" && -f "${MDPREP_DIR}/profiles/gmxkit.env.example" ]]; then
        cp -f "${MDPREP_DIR}/profiles/gmxkit.env.example" "${target}/gmxkit.env"
    fi
}

_scaffold_project_dir "${WORKDIR}"
_ensure_project_ff

# Tüm gmx çıktılarının toplandığı ana log
RUN_LOG="${LOG_DIR}/run_$(date +%Y%m%d_%H%M%S).log"

# --- Renkler (terminal destekliyorsa) ---------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GRN=$'\033[0;32m'; C_YLW=$'\033[1;33m'
    C_BLU=$'\033[0;34m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
    C_RED=""; C_GRN=""; C_YLW=""; C_BLU=""; C_DIM=""; C_RST=""
fi

# --- Loglama ----------------------------------------------------------------
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
_log_raw() { printf '%s\n' "$*" >>"${RUN_LOG}"; }

log_info() { printf '%s[INFO]%s %s\n' "${C_BLU}" "${C_RST}" "$*"; _log_raw "[$(_ts)][INFO] $*"; }
log_ok()   { printf '%s[ OK ]%s %s\n' "${C_GRN}" "${C_RST}" "$*"; _log_raw "[$(_ts)][ OK ] $*"; }
log_section() { echo ""; echo "======== $* ========"; }
log_warn() { printf '%s[WARN]%s %s\n' "${C_YLW}" "${C_RST}" "$*"; _log_raw "[$(_ts)][WARN] $*"; }
log_err()  { printf '%s[FAIL]%s %s\n' "${C_RED}" "${C_RST}" "$*" >&2; _log_raw "[$(_ts)][FAIL] $*"; }

die() { log_err "$*"; exit 1; }

# --- Varlık kontrolleri -----------------------------------------------------
require_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "$(t err_cmd_missing "$1" "${2:-}")"
}

require_file() {
    [[ -f "$1" ]] || die "$(t err_file_missing "$1" "${2:-}")"
}

require_dir() {
    [[ -d "$1" ]] || die "$(t err_dir_missing "$1" "${2:-}")"
}

# --- Yedekleme --------------------------------------------------------------
backup_file() {
    # In-place düzenleme ÖNCESİ çağrılır. Zaman damgalı kopya alır.
    local f="$1"
    [[ -f "$f" ]] || return 0
    local ts; ts="$(date +%Y%m%d_%H%M%S)"
    local dest="${BACKUP_DIR}/$(basename "$f").${ts}.bak"
    cp -p "$f" "$dest"
    log_info "$(t backup_done "$(basename "$f")" "${dest#"${WORKDIR}/"}")"
}

# --- Güvenli komut çalıştırma ----------------------------------------------
run_cmd() {
    # Genel komut. DRY_RUN destekler, stdout+stderr'i loga yazar.
    log_info "CMD: $*"
    if [[ "${DRY_RUN}" == "yes" ]]; then
        log_warn "$(t dry_run_skip)"
        return 0
    fi
    if "$@" >>"${RUN_LOG}" 2>&1; then
        return 0
    else
        local rc=$?
        log_err "$(t cmd_failed "${rc}" "$*" "${RUN_LOG}")"
        return "${rc}"
    fi
}

# --- gmx sarmalayıcı --------------------------------------------------------
# run_gmx <açıklama> -- <gmx argümanları...> [::expect:: çıktı1 çıktı2 ...]
# Örn: run_gmx "pdb2gmx" -- pdb2gmx -f protein.pdb -o processed.gro ::expect:: processed.gro topol.top
run_gmx() {
    local desc="$1"; shift
    [[ "$1" == "--" ]] && shift

    local args=(); local expect=(); local in_expect="no"
    for a in "$@"; do
        if [[ "$a" == "::expect::" ]]; then in_expect="yes"; continue; fi
        if [[ "${in_expect}" == "yes" ]]; then expect+=("$a"); else args+=("$a"); fi
    done

    log_info "gmx ${desc}: ${GMX} ${args[*]}"
    if [[ "${DRY_RUN}" == "yes" ]]; then
        log_warn "DRY_RUN: gmx çalıştırılmadı."
        return 0
    fi

    local gmx_log="${LOG_DIR}/gmx_${desc// /_}_$(date +%H%M%S).log"
    "${GMX}" "${args[@]}" >"${gmx_log}" 2>&1
    local rc=$?
    cat "${gmx_log}" >>"${RUN_LOG}"

    if [[ ${rc} -ne 0 ]] || grep -qiE 'Fatal error:' "${gmx_log}"; then
        log_err "$(t gmx_failed "${desc}" "${rc}" "${gmx_log}")"
        # GROMACS hata satırını öne çıkar
        grep -iE 'fatal error|error|not found' "${gmx_log}" | head -n 8 || true
        return 1
    fi

    # Beklenen çıktıların gerçekten oluştuğunu doğrula
    local missing=0
    for out in "${expect[@]}"; do
        if [[ ! -s "${out}" ]]; then
            log_err "$(t gmx_missing_out "${desc}" "${out}")"
            missing=1
        fi
    done
    [[ "${missing}" -eq 0 ]] || return 1

    # Sessiz uyarıları rapor et
    if grep -qiE 'warning' "${gmx_log}"; then
        log_warn "$(t gmx_warn "${desc}" "${gmx_log}")"
    fi
    log_ok "$(t gmx_done "${desc}")"
    return 0
}

# run_gmx_stdin <açıklama> <stdin> -- <gmx argümanları...> [::expect:: dosyalar...]
run_gmx_stdin() {
    local desc="$1"
    local stdin_data="$2"
    shift 2
    [[ "$1" == "--" ]] && shift

    local args=(); local expect=(); local in_expect="no"
    for a in "$@"; do
        if [[ "$a" == "::expect::" ]]; then in_expect="yes"; continue; fi
        if [[ "${in_expect}" == "yes" ]]; then expect+=("$a"); else args+=("$a"); fi
    done

    log_info "gmx ${desc} (stdin): ${GMX} ${args[*]}"
    if [[ "${DRY_RUN}" == "yes" ]]; then
        log_warn "DRY_RUN: gmx çalıştırılmadı."
        return 0
    fi

    local gmx_log="${LOG_DIR}/gmx_${desc// /_}_$(date +%H%M%S).log"
    printf '%s' "${stdin_data}" | "${GMX}" "${args[@]}" >"${gmx_log}" 2>&1
    local rc=$?
    cat "${gmx_log}" >>"${RUN_LOG}"

    if [[ ${rc} -ne 0 ]] || grep -qiE 'Fatal error:' "${gmx_log}"; then
        log_err "$(t gmx_failed "${desc}" "${rc}" "${gmx_log}")"
        grep -iE 'fatal error|error|not found' "${gmx_log}" | head -n 8 || true
        return 1
    fi

    local missing=0
    for out in "${expect[@]}"; do
        if [[ ! -s "${out}" ]]; then
            log_err "$(t gmx_missing_out "${desc}" "${out}")"
            missing=1
        fi
    done
    [[ "${missing}" -eq 0 ]] || return 1

    log_ok "$(t gmx_done "${desc}")"
    return 0
}

find_python() {
    if [[ -n "${MDPREP_PYTHON:-}" ]] && [[ -x "${MDPREP_PYTHON}" ]]; then
        echo "${MDPREP_PYTHON}"; return 0
    fi
    local ptr="${MDPREP_DIR}/.venv_path"
    if [[ -f "${ptr}" ]]; then
        local venv_py
        venv_py="$(<"${ptr}")/bin/python"
        [[ -x "${venv_py}" ]] && { echo "${venv_py}"; return 0; }
    fi
    local venv_py="${MDPREP_DIR}/.venv/bin/python3"
    [[ -x "${venv_py}" ]] && { echo "${venv_py}"; return 0; }
    local venv_py2="${MDPREP_DIR}/.venv/bin/python"
    [[ -x "${venv_py2}" ]] && { echo "${venv_py2}"; return 0; }
    local cand
    for cand in python3 python; do
        command -v "$cand" >/dev/null 2>&1 && { echo "$cand"; return 0; }
    done
    return 1
}

resolve_cgenff_script() {
    if [[ -n "${CGENFF_SCRIPT}" ]]; then
        echo "${CGENFF_SCRIPT}"; return 0
    fi
    case "${CGENFF_BACKEND}" in
        legacy|py2|py27) echo "${CGENFF_SCRIPT_LEGACY}" ;;
        py3|*)           echo "${CGENFF_SCRIPT_PY3}" ;;
    esac
}

find_cgenff_python() {
    if [[ -n "${MDPREP_CGENFF_PYTHON:-}" ]] && [[ -x "${MDPREP_CGENFF_PYTHON}" ]]; then
        echo "${MDPREP_CGENFF_PYTHON}"; return 0
    fi
    local ptr="${MDPREP_DIR}/.cgenff_python_path"
    if [[ -f "${ptr}" ]]; then
        local py; py="$(<"${ptr}")"
        [[ -n "${py}" ]] && [[ -x "${py}" ]] && { echo "${py}"; return 0; }
    fi
    case "${CGENFF_BACKEND}" in
        legacy|py2|py27)
            local cand
            for cand in \
                "${HOME}/miniconda3/envs/${CGENFF_CONDA_ENV}/bin/python" \
                "${HOME}/anaconda3/envs/${CGENFF_CONDA_ENV}/bin/python" \
                "${HOME}/miniforge3/envs/${CGENFF_CONDA_ENV}/bin/python" \
                python2.7 python2; do
                [[ -x "${cand}" ]] && { echo "${cand}"; return 0; }
                command -v "${cand}" >/dev/null 2>&1 && { echo "${cand}"; return 0; }
            done
            ;;
        *)
            find_python && return 0
            ;;
    esac
    return 1
}

cgenff_deps_ok() {
    local py="$1"
    local backend="${CGENFF_BACKEND:-legacy}"
    "${py}" -c "
import sys
try:
    import numpy
    import networkx as nx
except ImportError as e:
    sys.stderr.write('IMPORT_FAIL: %s\n' % e)
    sys.exit(1)
v = nx.__version__
parts = [int(x) for x in v.split('.')[:2]]
backend = '${backend}'
if backend in ('legacy', 'py2', 'py27'):
    if parts[0] != 1:
        sys.stderr.write('NX_FAIL: networkx %s — legacy için 1.11 gerekli\n' % v)
        sys.exit(2)
    print('numpy %s networkx %s (legacy/py2)' % (numpy.__version__, v))
else:
    if parts[0] < 2:
        sys.stderr.write('NX_FAIL: networkx %s — py3 backend için 2.x gerekli\n' % v)
        sys.exit(2)
    print('numpy %s networkx %s (py3)' % (numpy.__version__, v))
" 2>&1
}

python_deps_ok() {
    local py="$1"
    "${py}" -c "import sys; print('python', sys.version.split()[0])" 2>&1
}

# --- Checkpoint / resume ----------------------------------------------------
mark_done() { : >"${STATE_DIR}/$1.done"; log_ok "$(t checkpoint_done "$1")"; }
is_done()   { [[ -f "${STATE_DIR}/$1.done" ]]; }
clear_done() { rm -f "${STATE_DIR}/$1.done"; }

# stage_guard <stage_adı>: tamamlanmışsa atla (FORCE=1 ile zorla)
stage_guard() {
    local name="$1"
    if is_done "${name}" && [[ "${FORCE:-0}" != "1" ]]; then
        log_info "$(t stage_skip "${name}")"
        return 1
    fi
    return 0
}

# --- Kullanıcı kapısı (manuel adımlar) -------------------------------------
pause_gate() {
    # pause_gate "mesaj"  -> kullanıcıdan ENTER bekler (DRY_RUN'da geçer)
    [[ "${DRY_RUN}" == "yes" ]] && { log_warn "$(t dry_run_gate)"; return 0; }
    printf '\n%s%s%s %s\n' "${C_YLW}" "$(t manual_step)" "${C_RST}" "$1"
    read -r -p "$(t pause_manual)" _
}

confirm() {
    # confirm "soru"  -> y/N
    local ans
    read -r -p "$1 $(t confirm_yn)" ans
    [[ "${ans}" =~ ^[Yy]$ ]]
}

# prep_confirm_gate "Başlık" "satır1" "satır2" ...
# GROMACS'un interaktif sorduğu kararları config'ten gösterir; onay / iptal / config düzenle.
prep_confirm_gate() {
    local title="$1"
    shift
    [[ "${PREP_INTERACTIVE:-yes}" == "yes" ]] || return 0
    [[ "${DRY_RUN}" == "yes" ]] && return 0
    if [[ ! -t 0 ]]; then
        log_info "$(t confirm_gate_no_tty "${title}")"
        return 0
    fi

    echo ""
    printf '╔══ %s ══╗\n' "${title}"
    while [[ $# -gt 0 ]]; do
        printf '  %s\n' "$1"
        shift
    done
    printf '╚══════════════════════════════════════════╝\n'
    while true; do
        read -r -p "$(t confirm_gate)" ans
        case "${ans,,}" in
            ""|y|yes|evet) return 0 ;;
            n|no|q|iptal) die "$(t confirm_gate_cancel)" ;;
            e|edit|d|duzenle)
                local _wd="${WORKDIR}"
                "${EDITOR:-nano}" "${MDPREP_DIR}/config.sh"
                # shellcheck source=/dev/null
                source "${MDPREP_DIR}/config.sh"
                load_i18n
                [[ -z "${WORKDIR}" ]] && WORKDIR="${_wd}"
                export GMXKIT_WORKDIR="${WORKDIR}"
                log_ok "$(t confirm_gate_reload)"
                ;;
            *)
                log_warn "$(t confirm_gate_invalid)"
                ;;
        esac
    done
}

# --- WORKDIR'e geç ----------------------------------------------------------
cd "${WORKDIR}" || die "$(t err_workdir "${WORKDIR}")"
