#!/usr/bin/env bash
# Per-project system profile (standard vs metalloenzyme) — gmxkit.env
set -o nounset -o pipefail

metal_enzyme_enabled() {
    [[ "${METAL_ENZYME:-no}" == "yes" ]]
}

_project_env_file() {
    printf '%s/gmxkit.env' "${WORKDIR}"
}

_set_project_env_var() {
    local key="$1" val="$2" f
    f="$(_project_env_file)"
    touch "${f}"
    if grep -q "^${key}=" "${f}" 2>/dev/null; then
        sed -i "s|^${key}=.*|${key}=\"${val}\"|" "${f}"
    else
        printf '%s="%s"\n' "${key}" "${val}" >>"${f}"
    fi
}

_reload_project_env() {
    local f
    f="$(_project_env_file)"
    [[ -f "${f}" ]] || return 0
    # shellcheck source=/dev/null
    source "${f}"
}

_profile_was_set() {
    [[ -f "${STATE_DIR}/.profile_set" ]]
}

_mark_profile_set() {
    mkdir -p "${STATE_DIR}"
    date -Iseconds >"${STATE_DIR}/.profile_set" 2>/dev/null || date >"${STATE_DIR}/.profile_set"
}

set_metal_enzyme_mode() {
    local mode="${1:-no}"
    case "${mode}" in
        yes|no) ;;
        *) return 1 ;;
    esac
    _set_project_env_var "METAL_ENZYME" "${mode}"
    METAL_ENZYME="${mode}"
    _mark_profile_set
    log_ok "$(t profile_metal_set "${mode}")"
}

prompt_system_type_if_needed() {
    [[ -t 0 ]] || return 0
    _profile_was_set && return 0
    if [[ -f "$(_project_env_file)" ]] && grep -q '^METAL_ENZYME=' "$(_project_env_file)" 2>/dev/null; then
        _mark_profile_set
        return 0
    fi

    echo ""
    echo "  $(t profile_ask_title)"
    echo "  $(t profile_ask_std)"
    echo "  $(t profile_ask_metal)"
    echo ""
    read -r -p "$(t profile_ask_prompt)" ans
    case "${ans,,}" in
        y|yes|e|evet|2|metal|m)
            set_metal_enzyme_mode yes
            if [[ -z "${METAL_HSD_RESIDUES:-}" ]]; then
                log_warn "$(t profile_metal_hsd_missing)"
            fi
            echo "  $(t profile_metal_hint "${METAL_HSD_RESIDUES:-}" "${METAL_CHAIN:-A}")"
            echo "  $(t profile_metal_edit "$(_project_env_file)")"
            ;;
        *)
            set_metal_enzyme_mode no
            ;;
    esac
    echo ""
}

menu_system_type() {
    echo ""
    echo "  $(t profile_current "$(metal_enzyme_enabled && echo yes || echo no)")"
    echo ""
    echo "  1) $(t profile_opt_std)"
    echo "  2) $(t profile_opt_metal)"
    echo "  0) $(t menu_prep_back)"
    read -r -p "$(t prompt_choice)" c
    case "${c}" in
        1) set_metal_enzyme_mode no ;;
        2)
            set_metal_enzyme_mode yes
            echo "  $(t profile_metal_hint "${METAL_HSD_RESIDUES:-}" "${METAL_CHAIN:-A}")"
            echo "  $(t profile_metal_edit "$(_project_env_file)")"
            ;;
        0) return 0 ;;
        *) log_warn "$(t invalid_choice)"; return 1 ;;
    esac
    _reload_project_env
    return 0
}

stage_manual_hint() {
    local short="$1"
    case "${short}" in
        check)   t hint_check ;;
        metal)   t hint_metal ;;
        protein) t hint_protein ;;
        ligand)  t hint_ligand ;;
        complex) t hint_complex ;;
        solvate) t hint_solvate ;;
        index)   t hint_index ;;
        scripts|slurm) t hint_scripts ;;
        *)       echo "" ;;
    esac
}
