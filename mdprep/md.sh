#!/usr/bin/env bash
# =============================================================================
# GROMACS MD Orkestratör — tek giriş noktası, menü tabanlı kontrol
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
if [[ "${RUN_TARGET:-local}" == "truba" ]]; then
    _STAGE_06_NAME="06_truba_pack"
    _STAGE_06_LABEL="TRUBA slurm paketi"
else
    _STAGE_06_NAME="06_local_md"
    _STAGE_06_LABEL="MD scriptleri (run_local_md.sh)"
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
    "Ortam kontrolü"
    "Metalloenzim PDB (HSD, Zn)"
    "Protein topolojisi (pdb2gmx)"
    "Ligand (CGenFF + itp)"
    "Kompleks birleştirme"
    "Solvasyon + iyonlar (+ em.tpr)"
    "Index + ligand posre"
    "${_STAGE_06_LABEL}"
)

usage() {
    cat <<EOF
GROMACS MD Orkestratör

  ./md                         Etkileşimli menü (önerilen)
  ./mdprep/md.sh               Aynı

CLI: check | prep | status | reset | clean | stage NN | nvt | npt | md | binding
      queue [submit|chain|status|cancel]  — yerel iş kuyruğu (EM/NVT/NPT/MD)
      analyze [all|pbc|rmsd|report]       — PBC traj + RMSD/RMSF/Rg/SASA
      audit [--fix-mdp]                   — hazırlık denetimi (+ mdp senkron)
      install [-y] [--with-apt] [--recreate]  — pip venv (gmx kurulmaz)

WORKDIR: ${WORKDIR}
Kılavuz:  ${MDPREP_DIR}/KULLANIM.md
EOF
}

_pause() {
    echo ""
    read -r -p "↵ ENTER ile ana menüye dön... " _ || true
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
    printf '\n%-4s %-36s %s\n' "ID" "AŞAMA" "DURUM"
    printf '%-4s %-36s %s\n' "----" "------------------------------------" "------"
    for i in "${!STAGE_IDS[@]}"; do
        local st="bekliyor"
        is_done "${STAGE_NAMES[$i]}" && st="${C_GRN}tamam${C_RST}"
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
    echo "  Simülasyon  ${parts[*]}"
}

_queue_summary_line() {
    local line
    line="$(bash "${QUEUE_SH}" summary 2>/dev/null | tail -1)" || true
    if [[ -n "${line}" ]]; then
        echo "  Kuyruk      ${line}"
    else
        echo "  Kuyruk      (henüz job yok)"
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
        printf '  Hazırlık    %b%d/%d ✓%b\n' "${C_GRN}" "${done}" "${total}" "${C_RST}"
        _print_md_progress
        _queue_summary_line
    else
        local next id label
        next="$(_next_prep_stage)"
        id="${next%%|*}"
        label="${next#*|}"
        printf '  Hazırlık    %d/%d tamam' "${done}" "${total}"
        [[ -n "${id}" ]] && printf '  →  sonraki: %s' "${id}"
        echo ""
    fi
}

_smart_recommendation() {
    if ! _prep_complete; then
        local next id label
        next="$(_next_prep_stage)"
        id="${next%%|*}"
        label="${next#*|}"
        echo "  ${C_YLW}Öneri${C_RST}  →  [1] Hazırlık — aşama ${id} (${label})"
        return
    fi

    local phase running_line
    running_line="$(bash "${QUEUE_SH}" summary 2>/dev/null | tail -1)"
    if [[ "${running_line}" == *"çalışıyor"* ]]; then
        echo "  ${C_YLW}Öneri${C_RST}  →  [1] Kuyruk — durum / log izle"
        return
    fi

    phase="$(_recommend_phase)"
    case "${phase}" in
        em)  echo "  ${C_YLW}Öneri${C_RST}  →  [1] Kuyruk — EM gönder" ;;
        nvt) echo "  ${C_YLW}Öneri${C_RST}  →  [1] Kuyruk — NVT gönder" ;;
        npt) echo "  ${C_YLW}Öneri${C_RST}  →  [1] Kuyruk — NPT gönder" ;;
        md)  echo "  ${C_YLW}Öneri${C_RST}  →  [1] Kuyruk — production MD gönder" ;;
        done)
            echo "  ${C_GRN}Öneri${C_RST}  →  [6] Analiz — PBC + RMSD/RMSF/Rg/SASA"
            ;;
        *)   echo "  ${C_YLW}Öneri${C_RST}  →  [1] Kuyruk — simülasyon başlat" ;;
    esac
}

_print_main_menu_actions() {
    if _prep_complete; then
        echo "  1  [J] Kuyruk       arka plan — job ID, izle, iptal"
        echo "  2  [S] Simülasyon   ön plan — süre/sıcaklık sorar"
        echo "  3  [K] Kontrol      binding + hazırlık denetimi"
        echo "  6  [L] Analiz       PBC traj + RMSD/RMSF/Rg/SASA"
        echo "  ─────────────────────────────────────────────"
        echo "  4  [P] Hazırlık     aşama 00–06 (yeniden)"
        echo "  5  [A] Araçlar      temizlik, reset, config"
        echo "  0  [Q] Çıkış"
        echo ""
        echo "  ${C_DIM}S=terminalde çalışır · J=arka planda (uzun koşular için)${C_RST}"
    else
        echo "  1  [P] Hazırlık     aşama 00–06 (önerilen)"
        echo "  2  [A] Araçlar      kurulum, temizlik, config"
        echo "  0  [Q] Çıkış"
        echo ""
        echo "  ${C_DIM}Simülasyon ve kuyruk hazırlık (06) tamamlandıktan sonra açılır.${C_RST}"
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
            0|Q) echo "Çıkış."; exit 0 ;;
            "") return 0 ;;
            R) bash "${QUEUE_SH}" status ;;
            *) log_warn "1–6, 0 veya J/S/K/L/P/A/Q girin. (r = kuyruk durumu)" ;;
        esac
    else
        case "${choice^^}" in
            1|P) _menu_prep ;;
            2|A) _menu_tools ;;
            0|Q) echo "Çıkış."; exit 0 ;;
            "") return 0 ;;
            *) log_warn "1, 2, 0 veya P/A/Q girin." ;;
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
    echo "Simülasyon → [1] Kuyruk veya [2] etkileşimli"
}

_run_stage() {
    local id="$1" force="${2:-0}"
    local i name=""
    for i in "${!STAGE_IDS[@]}"; do
        [[ "${STAGE_IDS[$i]}" == "${id}" ]] && name="${STAGE_NAMES[$i]}" && break
    done
    [[ -n "${name}" ]] || { log_warn "Geçersiz aşama: ${id}"; return 1; }
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
    [[ -x "${RUN_SCRIPT}" ]] || { log_warn "run_local_md.sh yok — önce aşama 06"; return 1; }
    bash "${RUN_SCRIPT}" "${sub}" "$@"
}

cmd_clean() {
    bash "${CLEANUP_SH}" "$@"
}

_menu_prep() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║  HAZIRLIK — aşama seç (tek tek ilerle)   ║"
        echo "╚══════════════════════════════════════════╝"
        local i
        for i in "${!STAGE_IDS[@]}"; do
            printf '  [%s] %s  %s\n' "${STAGE_IDS[$i]}" "$(_stage_done_mark "${i}")" "${STAGE_LABELS[$i]}"
        done
        echo ""
        echo "  a) Tüm aşamaları sırayla (kaldığı yerden)"
        echo "  f) Aşama no + ZORLA tekrar (FORCE)"
        echo "  0) Ana menü"
        echo ""
        read -r -p "Aşama ID veya seçenek: " choice
        [[ -z "${choice}" ]] && continue
        case "${choice}" in
            0) return 0 ;;
            a|A)
                bash "${RUN_SH}" all
                _pause
                ;;
            f|F)
                read -r -p "Zorla tekrarlanacak aşama (00, 01 …): " fid
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
        echo "║  SİMÜLASYON — ön planda (terminalde)     ║"
        echo "╚══════════════════════════════════════════╝"
        _print_md_progress
        echo ""
        echo "  1) NVT   ısınma"
        echo "  2) NPT   basınç dengeleme"
        echo "  3) MD    production"
        echo "  4) Resume (MD checkpoint)"
        echo "  5) NVT   (-y, soru sormadan)"
        echo "  0) Ana menü"
        read -r -p "Seçim: " c
        case "${c}" in
            0) return 0 ;;
            1) cmd_md nvt; _pause ;;
            2) cmd_md npt; _pause ;;
            3) cmd_md md; _pause ;;
            4) cmd_md resume; _pause ;;
            5) cmd_md nvt -y; _pause ;;
            *) log_warn "Geçersiz seçim." ;;
        esac
    done
}

_menu_binding() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║  KONTROL — binding + denetim             ║"
        echo "╚══════════════════════════════════════════╝"
        echo "  1) em binding   2) nvt   3) npt   4) md"
        echo "  5) Hazırlık denetimi (audit)"
        echo "  6) MDP senkron (config → nvt/npt/md.mdp)"
        echo "  0) Ana menü"
        read -r -p "Seçim: " c
        case "${c}" in
            0) return 0 ;;
            1) cmd_binding em; _pause ;;
            2) cmd_binding nvt; _pause ;;
            3) cmd_binding npt; _pause ;;
            4) cmd_binding md; _pause ;;
            5) bash "${AUDIT_SH}"; _pause ;;
            6) bash "${MDPREP_DIR}/lib/sync_mdp.sh" --fix; _pause ;;
            *) log_warn "Geçersiz seçim." ;;
        esac
    done
}

_menu_tools() {
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════╗"
        echo "║  ARAÇLAR                                  ║"
        echo "╚══════════════════════════════════════════╝"
        echo "  1) Durum tablosu"
        echo "  2) Checkpoint sıfırla (dosyalar kalır)"
        echo "  3) Temizlik: listele (dry-run)"
        echo "  4) Temizlik: çıktıları sil (baştan kur)"
        echo "  5) Config yolu + profiller"
        echo "  6) Kılavuz (KULLANIM.md)"
        echo "  7) Ortam kurulumu (setup)"
        echo "  0) Ana menü"
        read -r -p "Seçim: " c
        case "${c}" in
            0) return 0 ;;
            1) _print_status_board; _pause ;;
            2) bash "${RUN_SH}" reset ;;
            3) cmd_clean --dry-run; _pause ;;
            4) _menu_clean_confirm ;;
            5)
                echo "Config: ${MDPREP_DIR}/config.sh"
                echo "Profil: ${MDPREP_DIR}/profiles/"
                _pause
                ;;
            6)
                echo "Kılavuz: ${MDPREP_DIR}/KULLANIM.md"
                _pause
                ;;
            7)
                echo "  a) setup (conda/venv)  b) setup --system"
                read -r -p "Seçim: " s
                case "${s}" in
                    a|A) bash "${MDPREP_DIR}/setup_env.sh"; _pause ;;
                    b|B) bash "${MDPREP_DIR}/setup_env.sh" --system; _pause ;;
                esac
                ;;
            *) log_warn "Geçersiz seçim." ;;
        esac
    done
}

_menu_clean_confirm() {
    echo ""
    echo "  1) Çıktıları sil (varsayılan yedekler korunur)"
    echo "  2) + mdprep/backups sil"
    echo "  3) + CGenFF .str sil"
    echo "  0) İptal"
    read -r -p "Seçim: " c
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
        echo "  ${C_YLW}İlk kurulum?${C_RST}  →  ./md install   (pip; gmx siz kurarsınız)"
        echo ""
    fi
    while true; do
        echo ""
        echo "╔══════════════════════════════════════════════════════════╗"
        echo "║           GROMACS MD ORKESTRATÖR                         ║"
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
            read -r -p "Seçim (1–6 / J S K L P A Q / r=durum): " main
        else
            read -r -p "Seçim (1–2 / P A Q): " main
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
        nvt|npt|md|resume) cmd_md "${cmd}" "$@" ;;
        *) die "Bilinmeyen: ${cmd}. ./md help" ;;
    esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ $# -eq 0 ]]; then
        orchestrator_menu
    else
        main_cli "$@"
    fi
fi
