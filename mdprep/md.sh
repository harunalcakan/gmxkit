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
# shellcheck source=lib/common.sh
source "${MDPREP_DIR}/lib/common.sh"

RUN_SCRIPT="${WORKDIR}/run_local_md.sh"
BIND_SCRIPT="${WORKDIR}/check_binding.sh"
CLEANUP_SH="${MDPREP_DIR}/lib/cleanup_workdir.sh"
RUN_SH="${MDPREP_DIR}/run.sh"
QUEUE_SH="${MDPREP_DIR}/lib/job_queue.sh"
ANALYZE_SH="${MDPREP_DIR}/lib/analyze_md.sh"
AUDIT_SH="${MDPREP_DIR}/lib/audit_prep.sh"
INSTALL_SH="${MDPREP_DIR}/lib/install.sh"

# run.sh ile aynı sıra (stage 06 RUN_TARGET'a göre)
_build_stage_labels() {
    if [[ "${RUN_TARGET:-local}" == "truba" ]]; then
        _STAGE_06_NAME="06_truba_pack"
        _STAGE_06_LABEL="$(t stage_06_truba)"
    else
        _STAGE_06_NAME="06_local_md"
        _STAGE_06_LABEL="$(t stage_06_local)"
    fi
    STAGE_IDS=( "00" "00b" "01" "02" "03" "04" "05" "06" )
    STAGE_NAMES=(
        "00_check_env"
        "00b_prepare_metallo"
        "01_protein"
        "02_ligand"
        "03_complex"
        "04_solvate_ions"
        "05_index_posre"
        "${_STAGE_06_NAME}"
    )
    STAGE_LABELS=(
        "$(t stage_00)"
        "$(t stage_00b)"
        "$(t stage_01)"
        "$(t stage_02)"
        "$(t stage_03)"
        "$(t stage_04)"
        "$(t stage_05)"
        "${_STAGE_06_LABEL}"
    )
}
_build_stage_labels

usage() {
    cat <<EOF
$(t usage_title)

$(t usage_menu)
$(t usage_same)

$(t usage_cli)
$(t usage_queue)
$(t usage_analyze)
$(t usage_audit)
$(t usage_install)
$(t usage_lang)

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
    if is_done "${STAGE_NAMES[$idx]}"; then
        printf '%b✓%b' "${C_GRN}" "${C_RST}"
    else
        printf '%b·%b' "${C_DIM}" "${C_RST}"
    fi
}

_print_status_board() {
    local i
    printf '\n%-4s %-36s %s\n' "$(t hdr_id)" "$(t hdr_stage)" "$(t hdr_status)"
    printf '%-4s %-36s %s\n' "----" "------------------------------------" "------"
    for i in "${!STAGE_IDS[@]}"; do
        local st
        st="$(t status_waiting)"
        is_done "${STAGE_NAMES[$i]}" && st="${C_GRN}$(t status_done)${C_RST}"
        printf '%-4s %-36s %b\n' "${STAGE_IDS[$i]}" "${STAGE_LABELS[$i]}" "${st}"
    done
    echo ""
}

_prep_done_count() {
    local i n=0
    for i in "${!STAGE_NAMES[@]}"; do
        is_done "${STAGE_NAMES[$i]}" && n=$((n + 1))
    done
    echo "${n}"
}

_prep_complete() {
    [[ "$(_prep_done_count)" -eq "${#STAGE_NAMES[@]}" ]]
}

_next_prep_stage() {
    local i
    for i in "${!STAGE_NAMES[@]}"; do
        if ! is_done "${STAGE_NAMES[$i]}"; then
            echo "${STAGE_IDS[$i]}|${STAGE_LABELS[$i]}"
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
        echo "$(t menu_queue)"
        echo "$(t menu_sim)"
        echo "$(t menu_control)"
        echo "$(t menu_analyze)"
        echo "  ─────────────────────────────────────────────"
        echo "$(t menu_prep)"
        echo "$(t menu_tools)"
        echo "$(t menu_exit)"
        echo ""
        echo "  ${C_DIM}$(t menu_hint_fg)${C_RST}"
    else
        echo "$(t menu_prep_only)"
        echo "$(t menu_tools_short)"
        echo "$(t menu_exit)"
        echo ""
        echo "  ${C_DIM}$(t menu_hint_locked)${C_RST}"
    fi
}

_dispatch_main_choice() {
    local choice="$1"
    if _prep_complete; then
        case "${choice^^}" in
            1|J) bash "${QUEUE_SH}" menu ;;
            2|S) _menu_simulation ;;
            3|K) _menu_binding ;;
            6|L) bash "${ANALYZE_SH}" all; _pause ;;
            4|P) _menu_prep ;;
            5|A) _menu_tools ;;
            0|Q) echo "$(t exit_msg)"; exit 0 ;;
            "") return 0 ;;
            R) bash "${QUEUE_SH}" status ;;
            *) log_warn "$(t warn_main_full)" ;;
        esac
    else
        case "${choice^^}" in
            1|P) _menu_prep ;;
            2|A) _menu_tools ;;
            0|Q) echo "$(t exit_msg)"; exit 0 ;;
            "") return 0 ;;
            *) log_warn "$(t warn_main_prep)" ;;
        esac
    fi
}

_suggest_next() {
    local i
    for i in "${!STAGE_NAMES[@]}"; do
        if ! is_done "${STAGE_NAMES[$i]}"; then
            echo "${STAGE_IDS[$i]} — ${STAGE_LABELS[$i]}"
            return 0
        fi
    done
    echo "$(t suggest_sim)"
}

_run_stage() {
    local id="$1" force="${2:-0}"
    local i name=""
    for i in "${!STAGE_IDS[@]}"; do
        [[ "${STAGE_IDS[$i]}" == "${id}" ]] && name="${STAGE_NAMES[$i]}" && break
    done
    [[ -n "${name}" ]] || { log_warn "$(t invalid_stage "${id}")"; return 1; }
    if [[ "${force}" == "1" ]]; then
        FORCE=1 bash "${RUN_SH}" stage "${id}"
    else
        bash "${RUN_SH}" stage "${id}"
    fi
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
        local i
        for i in "${!STAGE_IDS[@]}"; do
            printf '  [%s] %s  %s\n' "${STAGE_IDS[$i]}" "$(_stage_done_mark "${i}")" "${STAGE_LABELS[$i]}"
        done
        echo ""
        echo "$(t menu_prep_all)"
        echo "$(t menu_prep_force)"
        echo "$(t menu_prep_back)"
        echo ""
        read -r -p "$(t prompt_stage)" choice
        [[ -z "${choice}" ]] && continue
        case "${choice}" in
            0) return 0 ;;
            a|A)
                bash "${RUN_SH}" all
                _pause
                ;;
            f|F)
                read -r -p "$(t prompt_force_stage)" fid
                [[ -n "${fid}" ]] && { _run_stage "${fid}" 1; _pause; }
                ;;
            *)
                _run_stage "${choice}" 0
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
        echo "$(t menu_sim_nvt)"
        echo "$(t menu_sim_npt)"
        echo "$(t menu_sim_md)"
        echo "$(t menu_sim_resume)"
        echo "$(t menu_sim_nvt_y)"
        echo "$(t menu_prep_back)"
        read -r -p "$(t prompt_choice)" c
        case "${c}" in
            0) return 0 ;;
            1) cmd_md nvt; _pause ;;
            2) cmd_md npt; _pause ;;
            3) cmd_md md; _pause ;;
            4) cmd_md resume; _pause ;;
            5) cmd_md nvt -y; _pause ;;
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
                    a|A) bash "${MDPREP_DIR}/setup_env.sh"; _pause ;;
                    b|B) bash "${MDPREP_DIR}/setup_env.sh" --system; _pause ;;
                esac
                ;;
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
    if [[ ! -f "${STATE_DIR}/.installed" ]]; then
        echo ""
        echo "  ${C_YLW}$(t first_install)${C_RST}"
        echo ""
    fi
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║                        GmxKit                            ║"
        echo "║              $(t app_subtitle)                   ║"
        echo "╠══════════════════════════════════════════════════════════╣"
        printf "║  %s\n" "${WORKDIR}"
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
        prep|all) exec bash "${RUN_SH}" all ;;
        status|list) exec bash "${RUN_SH}" list ;;
        reset) exec bash "${RUN_SH}" reset ;;
        clean|cleanup) cmd_clean "$@" ;;
        stage) exec bash "${RUN_SH}" stage "$@" ;;
        setup) exec bash "${MDPREP_DIR}/setup_env.sh" "$@" ;;
        binding|check-binding) cmd_binding "$@" ;;
        queue|jobs) bash "${QUEUE_SH}" "$@" ;;
        analyze|analysis) bash "${ANALYZE_SH}" "$@" ;;
        audit) bash "${AUDIT_SH}" "$@" ;;
        install) bash "${INSTALL_SH}" "$@" ;;
        lang) cmd_lang "$@" ;;
        nvt|npt|md|resume) cmd_md "${cmd}" "$@" ;;
        *) die "$(t err_unknown_cmd "${cmd}")" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        orchestrator_menu
    else
        main_cli "$@"
    fi
fi
