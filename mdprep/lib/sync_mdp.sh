#!/usr/bin/env bash
# config.sh → mdp nsteps, ref_t, tc-grps senkronizasyonu
set -o nounset -o pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MDPREP_DIR="$(cd "${LIB_DIR}/.." && pwd)"
# shellcheck source=common.sh
source "${MDPREP_DIR}/lib/common.sh"

NVT_STEPS="${NVT_STEPS:-50000}"   # 100 ps @ dt=0.002

_mdp_nsteps() {
    awk '/^[[:space:]]*nsteps[[:space:]]*=/ {
        gsub(/;.*/, "", $0)
        for (i = 1; i <= NF; i++) if ($i + 0 == $i && $i ~ /^[0-9]+$/) { print $i; exit }
    }' "$1"
}

sync_mdp_from_config() {
    local fix="${1:-no}"
    local nsteps_prod=$((PROD_NS * 500000))
    local issues=0

    _check_mdp() {
        local mdp="$1" want="$2" label="$3"
        local cur
        cur="$(_mdp_nsteps "${mdp}")"
        if [[ -z "${cur}" ]]; then
            log_warn "${label}: nsteps satırı yok (${mdp})"
            issues=$((issues + 1))
            return
        fi
        if [[ "${cur}" != "${want}" ]]; then
            if [[ "${fix}" == "yes" ]]; then
                sed -i "s/^[[:space:]]*nsteps[[:space:]]*=.*/nsteps                  = ${want}     ; ${label}/" "${mdp}"
                log_ok "${label}: nsteps ${cur} → ${want}"
            else
                log_warn "${label}: nsteps=${cur} (beklenen ${want}) — ./md audit --fix-mdp"
                issues=$((issues + 1))
            fi
        else
            log_info "${label}: nsteps=${cur} OK"
        fi
    }

    _check_mdp "${NVT_MDP}" "${NVT_STEPS}" "NVT (${NVT_STEPS} adım)"
    _check_mdp "${NPT_MDP}" "${NPT_STEPS}" "NPT (${NPT_STEPS} adım, 500 ps)"
    _check_mdp "${PROD_MDP}" "${nsteps_prod}" "MD (${PROD_NS} ns)"

    if [[ "${fix}" == "yes" ]]; then
        for mdp in "${NVT_MDP}" "${NPT_MDP}" "${PROD_MDP}"; do
            sed -i "s/ref_t[[:space:]]*=.*/ref_t                   = ${REF_TEMP}   ${REF_TEMP}/" "${mdp}" 2>/dev/null || true
            sed -i "s/gen_temp[[:space:]]*=.*/gen_temp                = ${REF_TEMP}/" "${mdp}" 2>/dev/null || true
            sed -i "s/tc-grps[[:space:]]*=.*/tc-grps                 = ${GRP_PROTEIN_LIG} ${GRP_WATER_IONS}/" "${mdp}" 2>/dev/null || true
        done
        log_ok "ref_t / tc-grps senkronize (${REF_TEMP} K, ${GRP_PROTEIN_LIG}/${GRP_WATER_IONS})"
    fi

    return "${issues}"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        --fix|fix) sync_mdp_from_config yes ;;
        --check|check|"") sync_mdp_from_config no ;;
        *) echo "Kullanım: sync_mdp.sh [--check|--fix]"; exit 1 ;;
    esac
fi
