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

Projeyle birlikte (zip/USB): protein.pdb, ligand.mol2, *.mdp, charmm36-*.ff/
EOF
            exit 0
            ;;
        *) die "Bilinmeyen: ${arg}. ./md install help" ;;
    esac
done

log_section() { echo ""; echo "======== $* ========"; }

_ensure_md_launcher() {
    local launcher="${WORKDIR}/md"
    if [[ -x "${launcher}" ]]; then
        log_ok "./md zaten var"
        return 0
    fi
    cat > "${launcher}" <<'LAUNCH'
#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${ROOT}/mdprep/md.sh" "$@"
LAUNCH
    chmod +x "${launcher}"
    log_ok "./md oluşturuldu"
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
    read -r -p "Devam? [Y/n] " ans
    [[ ! "${ans,,}" == "n" && ! "${ans,,}" == "no" && ! "${ans,,}" == "hayir" ]]
}

_install_report() {
    local report="${STATE_DIR}/install_report.txt"
    mkdir -p "${STATE_DIR}"
    {
        echo "GmxKit kurulum raporu — $(date -Iseconds 2>/dev/null || date)"
        echo "WORKDIR: ${WORKDIR}"
        echo ""
        echo "--- Script kurulumu (pip/apt) ---"
        if PY="$(find_python 2>/dev/null)"; then echo "  OK  python: ${PY}"; else echo "  EKSIK  python3"; fi
        command -v perl >/dev/null 2>&1 && echo "  OK  perl" || echo "  EKSIK  perl"
        if [[ -f "${MDPREP_DIR}/.cgenff_python_path" ]]; then
            echo "  OK  cgenff venv: $(cat "${MDPREP_DIR}/.cgenff_python_path")"
        else
            echo "  EKSIK  cgenff venv"
        fi
        echo ""
        echo "--- Kullanıcı kurar (script dokunmaz) ---"
        if command -v "${GMX}" >/dev/null 2>&1; then
            echo "  OK  gmx (${GMX}): $(command -v "${GMX}")"
        else
            echo "  EKSIK  gmx — siz kurun; config.sh → GMX=..."
        fi
        echo ""
        echo "--- Proje paketi ---"
        for f in "${PROTEIN_PDB}" "${LIGAND_MOL2}" em.mdp nvt.mdp npt.mdp md.mdp; do
            [[ -f "${WORKDIR}/${f}" ]] && echo "  OK  ${f}" || echo "  EKSIK  ${f}"
        done
        [[ -d "${WORKDIR}/${FF_DIR}" ]] && echo "  OK  ${FF_DIR}/" || echo "  EKSIK  ${FF_DIR}/"
    } | tee "${report}"
    log_info "Rapor: ${report}"
}

main_install() {
    log_section "GmxKit — BAĞIMLILIK KURULUMU"
    log_info "WORKDIR: ${WORKDIR}"
    log_info "GROMACS otomatik kurulmaz — gmx sizin ortamınızdan kullanılır"

    find "${MDPREP_DIR}" -type f -name '*.sh' -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    chmod +x "${MDPREP_DIR}/run.sh" "${MDPREP_DIR}/setup_env.sh" "${MDPREP_DIR}/md.sh" \
        "${MDPREP_DIR}/lib/"*.sh "${MDPREP_DIR}/stages/"*.sh 2>/dev/null || true

    _ensure_md_launcher

    local setup_args=()
    [[ "${RECREATE}" -eq 1 ]] && setup_args+=(--recreate)

    if _confirm_apt; then
        log_section "APT (python3, perl — gmx yok)"
        bash "${MDPREP_DIR}/setup_env.sh" --system "${setup_args[@]}" || log_warn "apt adımı kısmen başarısız"
    fi

    log_section "PIP (Python venv — cgenff)"
    bash "${MDPREP_DIR}/setup_env.sh" --py3 "${setup_args[@]}"

    mkdir -p "${STATE_DIR}"
    date -Iseconds > "${STATE_DIR}/.installed" 2>/dev/null || date > "${STATE_DIR}/.installed"

    log_section "ORTAM DENETİMİ"
    bash "${MDPREP_DIR}/run.sh" check || log_warn "Bazı kontroller başarısız (rapor)"

    _install_report

    if ! command -v "${GMX}" >/dev/null 2>&1; then
        log_warn "gmx PATH'te yok — GROMACS'ı siz kurun; config.sh içinde GMX= yolunu ayarlayın"
    fi

    echo ""
    echo "════════════════════════════════════════════════════════════"
    echo "  Script bağımlılıkları kuruldu →  ./md"
    echo "  GROMACS: sizin kurulumunuz (config.sh → GMX=)"
    echo "  Rehber: mdprep/KURULUM_YENI_PC.md"
    echo "════════════════════════════════════════════════════════════"
}

main_install "$@"
