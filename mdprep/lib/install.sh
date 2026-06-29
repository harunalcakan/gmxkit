#!/usr/bin/env bash
# Yeni bilgisayar / yeni klasör — tek komut kurulum: ./md install
# GROMACS kurulmaz; kullanıcı kendi gmx kurulumunu kullanır (config.sh → GMX=)
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

WITH_APT=0
SKIP_APT=0
RECREATE=0
ASSUME_YES=0

for arg in "$@"; do
    case "${arg}" in
        --with-apt|--system) WITH_APT=1 ;;
        --no-apt|--skip-apt) SKIP_APT=1; WITH_APT=0 ;;
        --recreate) RECREATE=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        help|-h)
            cat <<'EOF'
Yeni makinede kurulum:

  ./md install              pip venv (numpy, networkx — cgenff)
  ./md install --with-apt   + apt: python3, perl (GROMACS YOK)
  ./md install -y           soru sormadan
  ./md install --recreate   venv sıfırdan

GROMACS (gmx) otomatik kurulmaz. Siz kurun; config.sh:
  GMX="gmx"                    # PATH'te ise
  GMX="/opt/gromacs/bin/gmx"   # tam yol

Projeyle birlikte: ayrı klasörde protein.pdb, ligand.mol2. Kurulum klasöründe charmm36-*.ff/ ve *.mdp şablonları paketlenir.
EOF
            exit 0
            ;;
        *) die "Bilinmeyen: ${arg}. ./md install help" ;;
    esac
done

log_section() { echo ""; echo "======== $* ========"; }

_ensure_md_launcher() {
    chmod +x "${GMXKIT_HOME}/gmxkit" "${GMXKIT_HOME}/md" 2>/dev/null || true
}

_install_global_command() {
    local bindir="${HOME}/.local/bin"
    local wrapper="${bindir}/gmxkit"
    mkdir -p "${bindir}"
    cat > "${wrapper}" <<EOF
#!/usr/bin/env bash
export GMXKIT_HOME="${GMXKIT_HOME}"
exec bash "\${GMXKIT_HOME}/mdprep/md.sh" "\$@"
EOF
    chmod +x "${wrapper}"
    log_ok "$(t install_global_cmd "${wrapper}")"
    case ":${PATH}:" in
        *":${bindir}:"*) ;;
        *)
            log_info "$(t install_path_hint "${bindir}")"
            ;;
    esac
}

_confirm_apt() {
    [[ "${WITH_APT}" -eq 0 || "${SKIP_APT}" -eq 1 ]] && return 1
    command -v apt-get >/dev/null 2>&1 || {
        log_warn "apt-get yok — --with-apt atlanıyor"
        return 1
    }
    echo ""
    echo "  Kurulacak (sudo): python3, perl, build-essential"
    echo "  Kurulmayacak: gromacs (kendi kurulumunuzu kullanın)"
    if [[ "${ASSUME_YES}" -eq 1 ]]; then
        return 0
    fi
    read -r -p "$(t install_confirm_apt)" ans
    [[ ! "${ans,,}" == "n" && ! "${ans,,}" == "no" && ! "${ans,,}" == "hayir" ]]
}

_install_report() {
    local report="${STATE_DIR}/install_report.txt"
    mkdir -p "${STATE_DIR}"
    {
        echo "$(t install_report_title "$(date -Iseconds 2>/dev/null || date)")"
        echo "WORKDIR: ${WORKDIR}"
        echo ""
        echo "$(t install_report_script)"
        if PY="$(find_python 2>/dev/null)"; then echo "  OK  python: ${PY}"; else echo "  EKSIK  python3"; fi
        command -v perl >/dev/null 2>&1 && echo "  OK  perl" || echo "  EKSIK  perl"
        if [[ -f "${MDPREP_DIR}/.cgenff_python_path" ]]; then
            echo "  OK  cgenff venv: $(cat "${MDPREP_DIR}/.cgenff_python_path")"
        else
            echo "  EKSIK  cgenff venv"
        fi
        echo ""
        echo "$(t install_report_user)"
        if command -v "${GMX}" >/dev/null 2>&1; then
            echo "  OK  gmx (${GMX}): $(command -v "${GMX}")"
        else
            echo "  EKSIK  gmx — siz kurun; config.sh → GMX=..."
        fi
        echo ""
        echo "$(t install_report_bundle)"
        for f in em.mdp nvt.mdp npt.mdp md.mdp ions.mdp sort_mol2_bonds.pl; do
            [[ -f "${GMXKIT_HOME}/${f}" ]] && echo "  OK  ${f}" || echo "  EKSIK  ${f}"
        done
        [[ -d "${GMXKIT_HOME}/${FF_DIR}" ]] && echo "  OK  ${FF_DIR}/" || echo "  EKSIK  ${FF_DIR}/"
        echo ""
        echo "$(t install_report_project_hint)"
        echo "$(t install_report_project_note)"
    } | tee "${report}"
    log_info "$(t install_report_path "${report}")"
}

main_install() {
    WORKDIR="${GMXKIT_HOME}"
    export GMXKIT_WORKDIR="${WORKDIR}"
    LOG_DIR="${WORKDIR}/.gmxkit/logs"
    STATE_DIR="${WORKDIR}/.gmxkit/state"
    BACKUP_DIR="${WORKDIR}/.gmxkit/backups"
    mkdir -p "${LOG_DIR}" "${STATE_DIR}" "${BACKUP_DIR}"

    log_section "$(t install_title)"
    log_info "WORKDIR: ${WORKDIR}"
    log_info "$(t install_gmx_note)"

    find "${MDPREP_DIR}" -type f -name '*.sh' -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    chmod +x "${MDPREP_DIR}/run.sh" "${MDPREP_DIR}/setup_env.sh" "${MDPREP_DIR}/md.sh" \
        "${MDPREP_DIR}/lib/"*.sh "${MDPREP_DIR}/stages/"*.sh 2>/dev/null || true

    _ensure_md_launcher
    _install_global_command

    local setup_args=()
    [[ "${RECREATE}" -eq 1 ]] && setup_args+=(--recreate)

    if _confirm_apt; then
        log_section "$(t install_apt_section)"
        bash "${MDPREP_DIR}/setup_env.sh" --system "${setup_args[@]}" || log_warn "apt step partially failed"
    fi

    log_section "$(t install_pip_section)"
    bash "${MDPREP_DIR}/setup_env.sh" --py3 "${setup_args[@]}"

    mkdir -p "${STATE_DIR}"
    date -Iseconds > "${STATE_DIR}/.installed" 2>/dev/null || date > "${STATE_DIR}/.installed"

    log_section "$(t install_check_section)"
    GMXKIT_CHECK_SCOPE=install bash "${MDPREP_DIR}/run.sh" check || log_warn "$(t install_warn_check)"

    _install_report

    log_section "$(t install_cleanup_section)"
    bash "${MDPREP_DIR}/lib/cleanup_install_home.sh" -y || true

    if ! command -v "${GMX}" >/dev/null 2>&1; then
        log_warn "$(t install_warn_gmx)"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "$(t install_done_banner)"
    echo "$(t install_done_usage)"
    echo "$(t install_done_gmx)"
    echo "$(t install_done_guide "$(docs_guide_path)")"
    echo "════════════════════════════════════════════════════════════"
}

main_install "$@"
