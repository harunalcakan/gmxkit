#!/usr/bin/env bash
# =============================================================================
# GmxKit — GROMACS protein–ligand MD araç seti (menü + CLI)
#
#   ./md                    Proje kökünden (önerilen)
#   ./mdprep/md.sh            Aynı
#   ./mdprep/md.sh stage 01   CLI (ileri kullanıcı)
# =============================================================================
set -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export GMXKIT_HOME="$(cd "${MDPREP_DIR}/.." && pwd)"

# Global flags: -C /path  or  --project /path  (before other commands)
MD_ARGS=()
_md_parse_globals() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -C|--project|--workdir)
                export GMXKIT_WORKDIR="$2"
                shift 2
                ;;
            -C=*|--project=*|--workdir=*)
                export GMXKIT_WORKDIR="${1#*=}"
                shift
                ;;
            *)
                MD_ARGS+=("$1")
                shift
                ;;
        esac
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    _md_parse_globals "$@"
    set -- "${MD_ARGS[@]}"
fi

# shellcheck source=lib/common.sh
source "${MDPREP_DIR}/lib/common.sh"
# shellcheck source=lib/stages.sh
source "${MDPREP_DIR}/lib/stages.sh"
# shellcheck source=lib/project_profile.sh
source "${MDPREP_DIR}/lib/project_profile.sh"

RUN_SCRIPT="${WORKDIR}/run_local_md.sh"
BIND_SCRIPT="${WORKDIR}/check_binding.sh"
CLEANUP_SH="${MDPREP_DIR}/lib/cleanup_workdir.sh"
RUN_SH="${MDPREP_DIR}/run.sh"
QUEUE_SH="${MDPREP_DIR}/lib/job_queue.sh"
ANALYZE_SH="${MDPREP_DIR}/lib/analyze_md.sh"
AUDIT_SH="${MDPREP_DIR}/lib/audit_prep.sh"
INSTALL_SH="${MDPREP_DIR}/lib/install.sh"
UNINSTALL_SH="${MDPREP_DIR}/lib/uninstall.sh"

# run.sh ile aynı sıra (stage 06 RUN_TARGET'a göre)
_build_stage_labels() {
    stages_init
    STAGE_NAMES=( "${STAGES[@]}" )
    local _shorts=( "${STAGE_SHORTS[@]}" )
    STAGE_SHORTS=( "${_shorts[@]}" )
    if [[ "${RUN_TARGET:-local}" == "truba" ]]; then
        STAGE_LABELS=(
            "$(t stage_00)"
            "$(t stage_00b)"
            "$(t stage_01)"
            "$(t stage_02)"
            "$(t stage_03)"
            "$(t stage_04)"
            "$(t stage_05)"
            "$(t stage_06_truba)"
        )
    else
        STAGE_LABELS=(
            "$(t stage_00)"
            "$(t stage_00b)"
            "$(t stage_01)"
            "$(t stage_02)"
            "$(t stage_03)"
            "$(t stage_04)"
            "$(t stage_05)"
            "$(t stage_06_local)"
        )
    fi
}
_build_stage_labels

usage() {
    cat <<EOF
$(t usage_title)

$(t usage_menu)
$(t usage_same)

$(t usage_stages "$(stages_usage_line)")
$(t usage_cli)
$(t usage_queue)
$(t usage_analyze)
$(t usage_audit)
$(t usage_install)
$(t usage_uninstall)
$(t usage_lang)
$(t usage_init)
$(t usage_project)

$(t usage_workdir "${WORKDIR}")
$(t usage_guide "$(docs_guide_path)")
EOF
}

cmd_lang() {
    local lang="${1:-}"
    if [[ -z "${lang}" ]]; then
        echo "$(t lang_current "${MDLANG}")"
        echo "$(t lang_usage)"
        return 0
    fi
    set_mdlang "${lang}" || die "$(t lang_usage)"
    _build_stage_labels
    log_ok "$(t lang_set "${MDLANG}")"
}

_pause() {
    echo ""
    read -r -p "$(t pause_main)" _ || true
}

_stage_done_mark() {
    local idx="$1"
    if _stage_effective_done "${idx}"; then
        printf '%b✓%b' "${C_GRN}" "${C_RST}"
    else
        printf '%b·%b' "${C_DIM}" "${C_RST}"
    fi
}

_stage_effective_done() {
    local idx="$1"
    [[ "${STAGE_SHORTS[$idx]}" == "metal" ]] && ! metal_enzyme_enabled && return 0
    is_done "${STAGE_NAMES[$idx]}"
}

_print_status_board() {
    local i
    printf '\n%-4s %-36s %s\n' "$(t hdr_id)" "$(t hdr_stage)" "$(t hdr_status)"
    printf '%-4s %-36s %s\n' "----" "------------------------------------" "------"
    for i in "${!STAGE_NAMES[@]}"; do
        local st skip=""
        st="$(t status_waiting)"
        _stage_effective_done "${i}" && st="${C_GRN}$(t status_done)${C_RST}"
        skip="$(_stage_skip_label "${i}")"
        printf '%-8s %-36s %b %b\n' "${STAGE_SHORTS[$i]}" "${STAGE_LABELS[$i]}" "${st}" "${skip}"
    done
    echo ""
}

_prep_done_count() {
    local i n=0
    for i in "${!STAGE_NAMES[@]}"; do
        _stage_effective_done "${i}" && n=$((n + 1))
    done
    echo "${n}"
}

_prep_complete() {
    [[ "$(_prep_done_count)" -eq "${#STAGE_NAMES[@]}" ]]
}

_next_prep_stage() {
    local i
    for i in "${!STAGE_NAMES[@]}"; do
        if ! _stage_effective_done "${i}"; then
            echo "${STAGE_SHORTS[$i]}|${STAGE_LABELS[$i]}"
            return 0
        fi
    done
    echo ""
}

_file_mark() {
    local rel="$1" label="$2"
    if [[ -f "${WORKDIR}/${rel}" ]]; then
        printf '%b%s ✓%b' "${C_GRN}" "${label}" "${C_RST}"
    else
        printf '%b%s ·%b' "${C_DIM}" "${label}" "${C_RST}"
    fi
}

_print_md_progress() {
    local parts=()
    parts+=("$(_file_mark "${EM_GRO}" "EM")")
    parts+=("$(_file_mark "${NVT_DEFFNM}.gro" "NVT")")
    parts+=("$(_file_mark "${NPT_DEFFNM}.gro" "NPT")")
    parts+=("$(_file_mark "${PROD_DEFFNM}.gro" "MD")")
    local IFS='  '
    echo "$(t sim_label)  ${parts[*]}"
}

_queue_summary_line() {
    local line
    line="$(bash "${QUEUE_SH}" summary 2>/dev/null | tail -1)" || true
    if [[ -n "${line}" ]]; then
        echo "$(t queue_label) ${line}"
    else
        echo "$(t queue_label) $(t queue_empty)"
    fi
}

_recommend_phase() {
    bash "${QUEUE_SH}" recommend 2>/dev/null | tail -1
}

_print_compact_header() {
    local done n total
    done="$(_prep_done_count)"
    total="${#STAGE_NAMES[@]}"
    if _prep_complete; then
        printf '%s%b%d/%d ✓%b\n' "$(t prep_label)" "${C_GRN}" "${done}" "${total}" "${C_RST}"
        _print_md_progress
        _queue_summary_line
    else
        local next id label
        next="$(_next_prep_stage)"
        id="${next%%|*}"
        label="${next#*|}"
        printf '%s' "$(t prep_label)"
        printf "$(t prep_progress)" "${done}" "${total}"
        [[ -n "${id}" ]] && printf "$(t prep_next)" "${id}"
        echo ""
    fi
}

_smart_recommendation() {
    if ! _prep_complete; then
        local next id label
        next="$(_next_prep_stage)"
        id="${next%%|*}"
        label="${next#*|}"
        echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_prep "${id}" "${label}")"
        return
    fi

    local phase running_line marker
    marker="$(t summary_running_marker)"
    running_line="$(bash "${QUEUE_SH}" summary 2>/dev/null | tail -1)"
    if [[ "${running_line}" == *"${marker}"* ]]; then
        echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_queue_watch)"
        return
    fi

    phase="$(_recommend_phase)"
    case "${phase}" in
        em)  echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_queue_em)" ;;
        nvt) echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_queue_nvt)" ;;
        npt) echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_queue_npt)" ;;
        md)  echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_queue_md)" ;;
        done)
            echo "  ${C_GRN}$(t rec_label)${C_RST}$(t rec_analyze)"
            ;;
        *)   echo "  ${C_YLW}$(t rec_label)${C_RST}$(t rec_queue_start)" ;;
    esac
}

_print_main_menu_actions() {
    if _prep_complete; then
        echo "$(t menu_prep)"
        echo "$(t menu_sim)"
        echo "$(t menu_analyze)"
        echo "$(t menu_tools)"
        echo "$(t menu_exit)"
    else
        echo "$(t menu_prep_only)"
        echo "$(t menu_tools_short)"
        echo "$(t menu_exit)"
        echo ""
        echo "  ${C_DIM}$(t menu_hint_locked)${C_RST}"
    fi
}

_print_project_header() {
    local prot lig ff
    prot="$(_file_mark "${PROTEIN_PDB}" "${PROTEIN_PDB}")"
    lig="$(_file_mark "${LIGAND_MOL2}" "${LIGAND_MOL2}")"
    if [[ -e "${WORKDIR}/${FF_DIR}" ]]; then
        ff="${C_GRN}${FF_DIR} ✓${C_RST}"
    else
        ff="${C_DIM}${FF_DIR} $(t input_missing)${C_RST}"
    fi
    printf '  %s: %s\n' "$(t hdr_project)" "${WORKDIR}"
    printf '  %s:  %b  %b  %b\n' "$(t hdr_inputs)" "${prot}" "${lig}" "${ff}"
}

_gmxkit_installed() {
    [[ -f "${GMXKIT_HOME}/.gmxkit/state/.installed" ]] || \
        [[ -f "${MDPREP_DIR}/.cgenff_python_path" ]]
}

_dispatch_main_choice() {
    local choice="$1"
    if _prep_complete; then
        case "${choice}" in
            1) _menu_prep ;;
            2) _menu_simulation ;;
            3) bash "${ANALYZE_SH}" all; _pause ;;
            4) _menu_tools ;;
            0) echo "$(t exit_msg)"; exit 0 ;;
            "") return 0 ;;
            *) log_warn "$(t warn_main_full)" ;;
        esac
    else
        case "${choice}" in
            1) _menu_prep ;;
            2) _menu_tools ;;
            0) echo "$(t exit_msg)"; exit 0 ;;
            "") return 0 ;;
            *) log_warn "$(t warn_main_prep)" ;;
        esac
    fi
}

_suggest_next() {
    local i
    for i in "${!STAGE_NAMES[@]}"; do
        if ! is_done "${STAGE_NAMES[$i]}"; then
            echo "${STAGE_SHORTS[$i]} — ${STAGE_LABELS[$i]}"
            return 0
        fi
    done
    echo "$(t suggest_sim)"
}

_prep_step_menu_num() {
    echo "$(( $1 + 2 ))"
}

_stage_skip_label() {
    local i="$1"
    [[ "${STAGE_SHORTS[$i]}" == "metal" ]] && ! metal_enzyme_enabled && {
        printf '%b%s%b' "${C_DIM}" "$(t stage_metal_off)" "${C_RST}"
        return 0
    }
    echo ""
}

_print_prep_legend() {
    printf '  %-4s %-8s %-32s %s\n' "$(t hdr_num)" "$(t hdr_code)" "$(t hdr_stage)" "$(t hdr_status)"
    printf '  %-4s %-8s %-32s %s\n' "----" "--------" "--------------------------------" "------"
}

_print_prep_system_line() {
    if metal_enzyme_enabled; then
        echo "  $(t prep_system_metal "${METAL_HSD_RESIDUES:-}" "${METAL_CHAIN:-A}")"
    else
        echo "  $(t prep_system_std)"
    fi
}

_run_stage() {
    local token="$1" force="${2:-0}"
    local arg="${token}"
    if [[ "${token}" =~ ^[2-9]$ ]]; then
        arg="${STAGE_SHORTS[$((token - 2))]}"
    fi
    resolve_stage_name "${arg}" >/dev/null || { log_warn "$(t invalid_stage "${token}")"; return 1; }
    if [[ "${force}" == "1" ]]; then
        FORCE=1 bash "${RUN_SH}" stage "${arg}"
    else
        bash "${RUN_SH}" stage "${arg}"
    fi
}

_run_prep_step() {
    local token="$1" force="${2:-0}"
    local arg="${token}" short hint=""
    if [[ "${token}" =~ ^[2-9]$ ]]; then
        arg="${STAGE_SHORTS[$((token - 2))]}"
    elif resolve_stage_name "${token}" >/dev/null 2>&1; then
        arg="$(stage_short_for "$(resolve_stage_name "${token}")")"
    fi
    short="${arg}"
    hint="$(stage_manual_hint "${short}")"
    if [[ -n "${hint}" ]]; then
        echo ""
        echo "  ${C_YLW}$(t prep_manual_note)${C_RST} ${hint}"
        echo ""
    fi
    _run_stage "${arg}" "${force}"
}

cmd_binding() {
    local phase="${1:-npt}"
    if [[ -x "${BIND_SCRIPT}" ]]; then
        bash "${BIND_SCRIPT}" "${phase}"
    else
        bash "${MDPREP_DIR}/lib/check_binding.sh" "${phase}"
    fi
}

cmd_md() {
    local sub="$1"
    shift || true
    [[ -x "${RUN_SCRIPT}" ]] || { log_warn "$(t err_run_local_md)"; return 1; }
    bash "${RUN_SCRIPT}" "${sub}" "$@"
}

cmd_clean() {
    bash "${CLEANUP_SH}" "$@"
}

_menu_prep() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║$(t menu_prep_title)║"
        echo "╚══════════════════════════════════════════╝"
        echo ""
        _print_prep_system_line
        echo ""
        echo "$(t menu_prep_auto)"
        echo "$(t menu_prep_manual_hdr)"
        echo ""
        _print_prep_legend
        local i n skip
        for i in "${!STAGE_NAMES[@]}"; do
            n="$(_prep_step_menu_num "${i}")"
            skip="$(_stage_skip_label "${i}")"
            printf '  %-4d %-8s %s  %-28s %b\n' \
                "${n}" "${STAGE_SHORTS[$i]}" "$(_stage_done_mark "${i}")" \
                "${STAGE_LABELS[$i]}" "${skip}"
        done
        echo ""
        echo "$(t menu_prep_force)"
        echo "$(t menu_prep_input_hint)"
        echo "$(t menu_prep_back)"
        echo ""
        read -r -p "$(t prompt_stage)" choice
        [[ -z "${choice}" ]] && continue
        case "${choice}" in
            0) return 0 ;;
            1|a|A|auto)
                echo "  $(t menu_prep_auto_note)"
                bash "${RUN_SH}" all
                _pause
                ;;
            f|F)
                read -r -p "$(t prompt_force_stage)" fid
                [[ -n "${fid}" ]] && { _run_prep_step "${fid}" 1; _pause; }
                ;;
            *)
                _run_prep_step "${choice}" 0
                _pause
                ;;
        esac
    done
}

_menu_simulation() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║$(t menu_sim_title)║"
        echo "╚══════════════════════════════════════════╝"
        _print_md_progress
        echo ""
        echo "$(t menu_sim_chain)"
        echo "$(t menu_sim_queue)"
        echo "$(t menu_sim_fg)"
        echo "$(t menu_sim_check)"
        echo "$(t menu_prep_back)"
        read -r -p "$(t prompt_choice)" c
        case "${c}" in
            0) return 0 ;;
            1) bash "${QUEUE_SH}" chain; _pause ;;
            2) bash "${QUEUE_SH}" menu ;;
            3) _menu_simulation_fg ;;
            4) _menu_binding ;;
            *) log_warn "$(t invalid_choice)" ;;
        esac
    done
}

_menu_simulation_fg() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║$(t menu_sim_fg_title)║"
        echo "╚══════════════════════════════════════════╝"
        echo "$(t menu_sim_nvt)"
        echo "$(t menu_sim_npt)"
        echo "$(t menu_sim_md)"
        echo "$(t menu_sim_resume)"
        echo "$(t menu_prep_back)"
        read -r -p "$(t prompt_choice)" c
        case "${c}" in
            0) return 0 ;;
            1) cmd_md nvt; _pause ;;
            2) cmd_md npt; _pause ;;
            3) cmd_md md; _pause ;;
            4) cmd_md resume; _pause ;;
            *) log_warn "$(t invalid_choice)" ;;
        esac
    done
}

_menu_binding() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║$(t menu_ctrl_title)║"
        echo "╚══════════════════════════════════════════╝"
        echo "$(t menu_ctrl_binding)"
        echo "$(t menu_ctrl_audit)"
        echo "$(t menu_ctrl_mdp)"
        echo "$(t menu_prep_back)"
        read -r -p "$(t prompt_choice)" c
        case "${c}" in
            0) return 0 ;;
            1) cmd_binding em; _pause ;;
            2) cmd_binding nvt; _pause ;;
            3) cmd_binding npt; _pause ;;
            4) cmd_binding md; _pause ;;
            5) bash "${AUDIT_SH}"; _pause ;;
            6) bash "${MDPREP_DIR}/lib/sync_mdp.sh" --fix; _pause ;;
            *) log_warn "$(t invalid_choice)" ;;
        esac
    done
}

_menu_tools() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║$(t menu_tools_title)║"
        echo "╚══════════════════════════════════════════╝"
        echo "$(t tool_status)"
        echo "$(t tool_reset)"
        echo "$(t tool_clean_list)"
        echo "$(t tool_clean_run)"
        echo "$(t tool_config)"
        echo "$(t tool_guide)"
        echo "$(t tool_setup)"
        echo "$(t tool_lang)"
        echo "$(t tool_install)"
        echo "$(t tool_system)"
        echo "$(t menu_prep_back)"
        read -r -p "$(t prompt_choice)" c
        case "${c}" in
            0) return 0 ;;
            1) _print_status_board; _pause ;;
            2) bash "${RUN_SH}" reset ;;
            3) cmd_clean --dry-run; _pause ;;
            4) _menu_clean_confirm ;;
            5)
                echo "$(t tool_config_path "${MDPREP_DIR}/config.sh")"
                echo "$(t tool_profile_path "${MDPREP_DIR}/profiles")"
                _pause
                ;;
            6)
                echo "$(t tool_guide_path "$(docs_guide_path)")"
                _pause
                ;;
            7)
                echo "  $(t tool_setup_opts)"
                read -r -p "$(t prompt_choice)" s
                case "${s}" in
                    1) bash "${MDPREP_DIR}/setup_env.sh"; _pause ;;
                    2) bash "${MDPREP_DIR}/setup_env.sh" --system; _pause ;;
                esac
                ;;
            8)
                echo "  en | tr"
                read -r -p "$(t prompt_choice)" lang
                [[ -n "${lang}" ]] && cmd_lang "${lang}"
                _pause
                ;;
            9) bash "${INSTALL_SH}"; _pause ;;
            10) menu_system_type; _build_stage_labels; _pause ;;
            *) log_warn "$(t invalid_choice)" ;;
        esac
    done
}

_menu_clean_confirm() {
    echo ""
    echo "$(t clean_opt1)"
    echo "$(t clean_opt2)"
    echo "$(t clean_opt3)"
    echo "$(t clean_cancel)"
    read -r -p "$(t prompt_choice)" c
    case "${c}" in
        1) cmd_clean ;;
        2) cmd_clean --remove-backups ;;
        3) cmd_clean --remove-str ;;
        0) return 0 ;;
    esac
    _pause
}

orchestrator_menu() {
    clear 2>/dev/null || true
    if ! _gmxkit_installed; then
        echo ""
        echo "  ${C_YLW}$(t first_install)${C_RST}"
        echo ""
    fi
    prompt_system_type_if_needed
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                        GmxKit                            ║"
        echo "║              $(t app_subtitle)                   ║"
        echo "╠══════════════════════════════════════════════════════════╣"
        _print_project_header
        echo "╚══════════════════════════════════════════════════════════╝"
        echo ""
        _print_compact_header
        echo ""
        if ! _prep_complete; then
            _print_status_board
        fi
        _smart_recommendation
        echo ""
        _print_main_menu_actions
        echo ""
        if _prep_complete; then
            read -r -p "$(t prompt_main_full)" main
        else
            read -r -p "$(t prompt_main_prep)" main
        fi
        _dispatch_main_choice "${main}"
    done
}

main_cli() {
    local cmd="${1:-menu}"
    shift || true
    case "${cmd}" in
        menu) orchestrator_menu ;;
        help|-h|--help) usage ;;
        check|env) exec bash "${RUN_SH}" check ;;
        prep|all)
            if [[ $# -gt 0 ]]; then
                exec bash "${RUN_SH}" stage "$1"
            else
                exec bash "${RUN_SH}" all
            fi
            ;;
        status|list) exec bash "${RUN_SH}" list ;;
        reset) exec bash "${RUN_SH}" reset ;;
        clean|cleanup) cmd_clean "$@" ;;
        stage)
            [[ -n "${1:-}" ]] || die "$(t run_err_stage_arg)"
            exec bash "${RUN_SH}" stage "$1"
            ;;
        setup) exec bash "${MDPREP_DIR}/setup_env.sh" "$@" ;;
        binding|check-binding) cmd_binding "$@" ;;
        queue|jobs) bash "${QUEUE_SH}" "$@" ;;
        analyze|analysis) bash "${ANALYZE_SH}" "$@" ;;
        audit) bash "${AUDIT_SH}" "$@" ;;
        install) bash "${INSTALL_SH}" "$@" ;;
        uninstall) bash "${UNINSTALL_SH}" "$@" ;;
        init) bash "${MDPREP_DIR}/lib/init_project.sh" "${1:-.}" ;;
        lang) cmd_lang "$@" ;;
        nvt|npt|md|resume) cmd_md "${cmd}" "$@" ;;
        *)
            if resolve_stage_name "${cmd}" >/dev/null 2>&1; then
                exec bash "${RUN_SH}" stage "${cmd}"
            fi
            die "$(t err_unknown_cmd "${cmd}")"
            ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        orchestrator_menu
    else
        main_cli "$@"
    fi
fi
