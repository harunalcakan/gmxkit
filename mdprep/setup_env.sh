#!/usr/bin/env bash
# =============================================================================
# setup_env.sh - Pipeline bağımlılık kurulumu
#
# Varsayılan (legacy): Python 2.7 + networkx 1.11 conda env (cgenff için)
#   ./mdprep/run.sh setup
#   ./mdprep/run.sh setup --legacy
#
# Alternatif py3 cgenff:
#   config.sh -> CGENFF_BACKEND="py3"
#   ./mdprep/run.sh setup --py3
#
# Sistem paketleri: ./mdprep/run.sh setup --system
# =============================================================================
set -o errexit -o nounset -o pipefail

MDPREP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKDIR="$(cd "${MDPREP_DIR}/.." && pwd)"
# shellcheck source=config.sh
source "${MDPREP_DIR}/config.sh"

VENV_POINTER="${MDPREP_DIR}/.venv_path"
CGENFF_PTR="${MDPREP_DIR}/.cgenff_python_path"
ENV_LEGACY="${MDPREP_DIR}/environment-legacy.yml"
REQ_PY3="${MDPREP_DIR}/requirements-py3.txt"
REQ_PY3NX="${MDPREP_DIR}/requirements.txt"

DO_SYSTEM=0
DO_CONDA=0
DO_LEGACY=0
DO_PY3=0
DO_FIX_ONLY=0
DO_RECREATE=0
DO_ALL=0

for arg in "$@"; do
    case "${arg}" in
        --system)   DO_SYSTEM=1 ;;
        --all)      DO_ALL=1 ;;
        --conda)    DO_CONDA=1 ;;
        --legacy)   DO_LEGACY=1 ;;
        --py3)      DO_PY3=1 ;;
        --fix-crlf) DO_FIX_ONLY=1 ;;
        --recreate) DO_RECREATE=1 ;;
        -h|--help)
            cat <<'EOF'
Bağımlılık kurulumu (mdprep/setup_env.sh):

  --all       apt (python3, perl — GROMACS hariç) + pip venv (cgenff py3)
  --system    Yalnızca apt: python3, perl, build-essential (GROMACS kurulmaz)
  --py3       Yalnızca Python venv + pip (requirements.txt)
  --legacy    Conda py2.7 + networkx 1.11 (eski cgenff)
  --recreate  venv/conda env sıfırdan
  --fix-crlf  Script satır sonlarını düzelt (CRLF→LF)

Kullanıcı dostu giriş:  ./md install
EOF
            exit 0
            ;;
        *) echo "Bilinmeyen seçenek: ${arg}" >&2; exit 1 ;;
    esac
done

if [[ "${DO_ALL}" -eq 1 ]]; then
    DO_SYSTEM=1
    DO_PY3=1
fi

info()  { printf '[setup] %s\n' "$*"; }
warn()  { printf '[setup][WARN] %s\n' "$*" >&2; }
die()   { printf '[setup][FAIL] %s\n' "$*" >&2; exit 1; }

fix_scripts() {
    find "${MDPREP_DIR}" -type f -name '*.sh' -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    chmod +x "${MDPREP_DIR}/run.sh" "${MDPREP_DIR}/setup_env.sh" "${MDPREP_DIR}/stages/"*.sh 2>/dev/null || true
}

if [[ "${DO_FIX_ONLY}" -eq 1 ]]; then
    fix_scripts
    info "CRLF + chmod tamam."
    exit 0
fi

# Varsayılan: legacy backend ise --legacy kur
if [[ "${DO_LEGACY}" -eq 0 && "${DO_PY3}" -eq 0 && "${DO_CONDA}" -eq 0 ]]; then
    case "${CGENFF_BACKEND}" in
        legacy|py2|py27) DO_LEGACY=1 ;;
        py3|*)           DO_PY3=1 ;;
    esac
fi

# --- Sistem paketleri (Ubuntu/Debian/WSL) ------------------------------------
install_system_packages() {
    command -v apt-get >/dev/null 2>&1 || {
        warn "apt-get yok — python3/perl'i elle kurun"
        return 1
    }
    info "apt: python3, perl, build-essential (GROMACS kurulmaz — kullanıcı kurar)"
    sudo apt-get update -qq
    sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
        perl python3 python3-venv python3-pip \
        build-essential ca-certificates curl \
        || { warn "apt kurulumu kısmen başarısız"; return 1; }
    return 0
}

if [[ "${DO_SYSTEM}" -eq 1 ]]; then
    install_system_packages || true
fi

# --- Legacy: conda py2.7 + networkx 1.11 ------------------------------------
setup_legacy_conda() {
    [[ -f "${ENV_LEGACY}" ]] || die "${ENV_LEGACY} yok"
    command -v conda >/dev/null 2>&1 || die "conda bulunamadı. Miniconda kur: https://docs.conda.io/en/latest/miniconda.html"

    if [[ "${DO_RECREATE}" -eq 1 ]]; then
        info "Conda env siliniyor: ${CGENFF_CONDA_ENV}"
        conda env remove -n "${CGENFF_CONDA_ENV}" -y 2>/dev/null || true
    fi

    if conda env list | grep -qE "^${CGENFF_CONDA_ENV}[[:space:]]"; then
        info "Conda env mevcut: ${CGENFF_CONDA_ENV}"
    else
        info "Conda env oluşturuluyor: ${CGENFF_CONDA_ENV} (py2.7 + networkx 1.11)"
        conda env create -f "${ENV_LEGACY}" || die "conda env create başarısız"
    fi

    local py
    py="$(conda run -n "${CGENFF_CONDA_ENV}" which python 2>/dev/null || true)"
    [[ -n "${py}" ]] || py="${HOME}/miniconda3/envs/${CGENFF_CONDA_ENV}/bin/python"
    [[ -x "${py}" ]] || py="${HOME}/anaconda3/envs/${CGENFF_CONDA_ENV}/bin/python"
    [[ -x "${py}" ]] || die "Conda python bulunamadı: ${CGENFF_CONDA_ENV}"

    echo "${py}" > "${CGENFF_PTR}"
    info "cgenff python: ${py}"
    conda run -n "${CGENFF_CONDA_ENV}" python -c "import numpy, networkx as nx; print('numpy', numpy.__version__, '| networkx', nx.__version__)"
}

# --- Py3 venv (yalnızca CGENFF_BACKEND=py3 veya --py3) ----------------------
setup_py3_venv() {
    local PY3=""
    for cand in python3 python; do
        command -v "$cand" >/dev/null 2>&1 && PY3="$cand" && break
    done
    [[ -n "${PY3}" ]] || die "python3 bulunamadı"

    local VENV_DIR
    if [[ "${WORKDIR}" == /mnt/* ]]; then
        local vtag; vtag="$(echo -n "${WORKDIR}" | md5sum | awk '{print $1}')"
        VENV_DIR="${HOME}/.cache/mdprep-venvs/${vtag}"
    else
        VENV_DIR="${MDPREP_DIR}/.venv"
    fi

    [[ "${DO_RECREATE}" -eq 1 ]] && rm -rf "${VENV_DIR}"
    [[ -d "${VENV_DIR}" ]] || "${PY3}" -m venv "${VENV_DIR}"

    # shellcheck source=/dev/null
    source "${VENV_DIR}/bin/activate"
    python -m pip install -q --upgrade pip 2>/dev/null || true
    python -m pip install -r "${REQ_PY3NX}" || die "pip install (py3 cgenff) başarısız"
    echo "${VENV_DIR}" > "${VENV_POINTER}"
    echo "${VENV_DIR}/bin/python" > "${CGENFF_PTR}"
    python -c "import numpy, networkx as nx; print('numpy', numpy.__version__, '| networkx', nx.__version__)"
}

if [[ "${DO_LEGACY}" -eq 1 ]]; then
    setup_legacy_conda
    [[ -f "${WORKDIR}/${CGENFF_SCRIPT_LEGACY}" ]] \
        || warn "Eksik: ${CGENFF_SCRIPT_LEGACY} (WORKDIR'e kopyala)"
fi

if [[ "${DO_PY3}" -eq 1 ]]; then
    setup_py3_venv
fi

if [[ "${DO_CONDA}" -eq 1 && "${DO_LEGACY}" -eq 0 ]]; then
    [[ -f "${MDPREP_DIR}/environment.yml" ]] || die "environment.yml yok"
    conda env create -f "${MDPREP_DIR}/environment.yml" 2>/dev/null \
        || conda env update -f "${MDPREP_DIR}/environment.yml"
fi

fix_scripts

cat <<EOF

================================================================================
Kurulum tamamlandı (CGENFF_BACKEND=${CGENFF_BACKEND})
================================================================================
cgenff script : ${CGENFF_SCRIPT_LEGACY} (legacy) / ${CGENFF_SCRIPT_PY3} (py3)
cgenff python : $(cat "${CGENFF_PTR}" 2>/dev/null || echo '— kurulmadı —')

Pipeline yardımcıları (gro/top/ndx): python3
  $(command -v python3 2>/dev/null || echo 'python3 bulunamadı')

Sonraki:  cd "${WORKDIR}" && ./mdprep/run.sh check

Legacy mod: conda activate ${CGENFF_CONDA_ENV}  (manuel test için)
Py3 mod:    config.sh içinde CGENFF_BACKEND=py3 && ./mdprep/run.sh setup --py3
================================================================================
EOF
