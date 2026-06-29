#!/usr/bin/env bash
# Remove GmxKit-installed artifacts (venv, global wrapper, install state).
# Does NOT remove: GROMACS, force field, project folders, or the gmxkit clone (unless --purge-home).
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

ASSUME_YES=0
PURGE_HOME=0

for arg in "$@"; do
    case "${arg}" in
        -y|--yes) ASSUME_YES=1 ;;
        --purge-home) PURGE_HOME=1 ;;
        help|-h)
            cat <<EOF
$(t uninstall_help_title)

  gmxkit uninstall              Remove Python venv, ~/.local/bin/gmxkit, install markers
  gmxkit uninstall -y           No confirmation prompt
  gmxkit uninstall --purge-home Also delete entire install folder (${GMXKIT_HOME})

Keeps: GROMACS, force field (charmm36-*.ff), your project folders and simulation files.
EOF
            exit 0
            ;;
        *) die "$(t uninstall_unknown "${arg}")" ;;
    esac
done

_confirm() {
    [[ "${ASSUME_YES}" -eq 1 ]] && return 0
    echo ""
    echo "  $(t uninstall_confirm_list)"
    echo "    • $(t uninstall_item_wrapper)"
    echo "    • $(t uninstall_item_venv)"
    echo "    • $(t uninstall_item_state)"
    [[ "${PURGE_HOME}" -eq 1 ]] && echo "    • $(t uninstall_item_home "${GMXKIT_HOME}")"
    echo ""
    read -r -p "$(t uninstall_confirm_prompt)" ans
    [[ "${ans,,}" == "y" || "${ans,,}" == "yes" || "${ans,,}" == "evet" ]]
}

_wrapper_is_ours() {
    local w="${HOME}/.local/bin/gmxkit"
    [[ -f "${w}" ]] || return 1
    grep -Fq "GMXKIT_HOME=\"${GMXKIT_HOME}\"" "${w}" 2>/dev/null \
        || grep -Fq "GMXKIT_HOME=${GMXKIT_HOME}" "${w}" 2>/dev/null
}

_remove_global_wrapper() {
    local w="${HOME}/.local/bin/gmxkit"
    if [[ ! -f "${w}" ]]; then
        log_info "$(t uninstall_skip_wrapper)"
        return 0
    fi
    if _wrapper_is_ours; then
        rm -f "${w}"
        log_ok "$(t uninstall_removed_wrapper "${w}")"
    else
        log_warn "$(t uninstall_wrapper_other "${w}")"
    fi
}

_remove_path_dir() {
    local dir="$1" label="$2"
    [[ -n "${dir}" && -d "${dir}" ]] || return 0
    rm -rf "${dir}"
    log_ok "$(t uninstall_removed_dir "${label}" "${dir}")"
}

_remove_venvs() {
    local venv_dir="" ptr="${MDPREP_DIR}/.venv_path"
    if [[ -f "${ptr}" ]]; then
        venv_dir="$(<"${ptr}")"
        _remove_path_dir "${venv_dir}" "venv"
        rm -f "${ptr}"
    fi
    _remove_path_dir "${MDPREP_DIR}/.venv" "venv"
    rm -f "${MDPREP_DIR}/.cgenff_python_path"

    # Legacy conda env (optional — only if created by GmxKit naming)
    if command -v conda >/dev/null 2>&1; then
        if conda env list 2>/dev/null | grep -qE "^${CGENFF_CONDA_ENV}[[:space:]]"; then
            if [[ "${ASSUME_YES}" -eq 1 ]]; then
                conda env remove -n "${CGENFF_CONDA_ENV}" -y 2>/dev/null && \
                    log_ok "$(t uninstall_removed_conda "${CGENFF_CONDA_ENV}")" || true
            else
                read -r -p "$(t uninstall_conda_prompt "${CGENFF_CONDA_ENV}")" ans
                if [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]; then
                    conda env remove -n "${CGENFF_CONDA_ENV}" -y 2>/dev/null && \
                        log_ok "$(t uninstall_removed_conda "${CGENFF_CONDA_ENV}")" || true
                fi
            fi
        fi
    fi
}

_remove_install_state() {
    local base="${GMXKIT_HOME}/.gmxkit"
    rm -f "${base}/state/.installed" "${base}/state/install_report.txt" 2>/dev/null || true
    rm -rf "${base}/state" "${base}/logs" "${base}/backups" 2>/dev/null || true
    rmdir "${base}" 2>/dev/null || true
    log_ok "$(t uninstall_removed_state)"
}

_purge_home() {
    [[ "${PURGE_HOME}" -eq 1 ]] || return 0
    if [[ "${ASSUME_YES}" -ne 1 ]]; then
        echo ""
        echo "  $(t uninstall_purge_warn "${GMXKIT_HOME}")"
        read -r -p "$(t uninstall_purge_prompt)" ans
        [[ "${ans}" == "${GMXKIT_HOME}" ]] || { log_warn "$(t uninstall_purge_cancel)"; return 0; }
    fi
    rm -rf "${GMXKIT_HOME}"
    log_ok "$(t uninstall_purge_done "${GMXKIT_HOME}")"
    echo "$(t uninstall_purge_note)"
}

main_uninstall() {
    WORKDIR="${GMXKIT_HOME}"
    export GMXKIT_WORKDIR="${WORKDIR}"

    log_section "$(t uninstall_title)"
    log_info "GMXKIT_HOME: ${GMXKIT_HOME}"

    _confirm || { log_info "$(t uninstall_cancelled)"; exit 0; }

    _remove_global_wrapper
    _remove_venvs
    _remove_install_state
    _purge_home

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "$(t uninstall_done)"
    echo "$(t uninstall_done_note)"
    echo "════════════════════════════════════════════════════════════"
}

main_uninstall "$@"
