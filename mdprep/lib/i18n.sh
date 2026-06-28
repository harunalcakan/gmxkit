#!/usr/bin/env bash
# GmxKit i18n — load strings from mdprep/i18n/{en,tr}.sh
# Usage: t key [printf-args...]

load_i18n() {
    local lang="${MDLANG:-en}"
    case "${lang}" in
        tr) ;;
        *) lang="en"; MDLANG="en" ;;
    esac
    # shellcheck source=/dev/null
    source "${MDPREP_DIR}/i18n/${lang}.sh"
}

t() {
    local key="$1"
    shift || true
    local var="I18N_${key}"
    local fmt="${!var:-[$key]}"
    if [[ $# -gt 0 ]]; then
        # shellcheck disable=SC2059
        printf "$fmt" "$@"
    else
        printf '%s' "$fmt"
    fi
}

set_mdlang() {
    local lang="$1"
    case "${lang}" in
        en|tr) ;;
        *) return 1 ;;
    esac
    if grep -qE '^MDLANG=' "${MDPREP_DIR}/config.sh"; then
        sed -i "s/^MDLANG=.*/MDLANG=\"${lang}\"/" "${MDPREP_DIR}/config.sh"
    else
        printf '\nMDLANG="%s"\n' "${lang}" >>"${MDPREP_DIR}/config.sh"
    fi
    MDLANG="${lang}"
    load_i18n
}

docs_guide_path() {
    case "${MDLANG:-en}" in
        tr) echo "${MDPREP_DIR}/docs/tr/KULLANIM.md" ;;
        *)  echo "${MDPREP_DIR}/docs/en/USAGE.md" ;;
    esac
}
