#!/usr/bin/env bash
# Etkileşimli MDP düzenleme (NVT / NPT / production)

MDP_DT="${MDP_DT:-0.002}"

mdp_read_value() {
    local key="$1" file="$2"
    grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | head -1 \
        | sed -E 's/^[^=]*=[[:space:]]*([^;]+).*/\1/' | tr -d '\r' | awk '{print $1}'
}

mdp_set_scalar() {
    local key="$1" file="$2" value="$3"
    sed -i -E "s/^([[:space:]]*${key}[[:space:]]*=).*/\\1 ${value}/" "$file"
}

mdp_ps_to_nsteps() {
    awk -v ps="$1" -v dt="${MDP_DT}" 'BEGIN { printf "%.0f", ps / dt }'
}

mdp_nsteps_to_ps() {
    awk -v n="$1" -v dt="${MDP_DT}" 'BEGIN { printf "%.0f", n * dt }'
}

mdp_ns_to_nsteps() {
    awk -v ns="$1" -v dt="${MDP_DT}" 'BEGIN { printf "%.0f", ns * 1000 / dt }'
}

mdp_nsteps_to_ns() {
    awk -v n="$1" -v dt="${MDP_DT}" 'BEGIN { printf "%.3f", n * dt / 1000 }'
}

prompt_value() {
    local prompt="$1" default="$2" answer=""
    read -r -p "${prompt} [${default}]: " answer
    if [[ -z "${answer}" ]]; then
        echo "${default}"
    else
        echo "${answer}"
    fi
}

prompt_edit_mdp() {
    local mdp="$1"
    local answer=""
    read -r -p "$(t mdp_prompt_edit)" answer
    if [[ "${answer,,}" == "e" || "${answer,,}" == "evet" || "${answer,,}" == "yes" ]]; then
        "${EDITOR:-nano}" "${mdp}"
    fi
}

_set_temp_mdp() {
    local mdp="$1" temp="$2"
    sed -i "s/ref_t[[:space:]]*=.*/ref_t                   = ${temp}   ${temp}/" "${mdp}"
    if grep -qE '^[[:space:]]*gen_temp[[:space:]]*=' "${mdp}"; then
        mdp_set_scalar gen_temp "${mdp}" "${temp}"
    fi
}

configure_mdp_nvt() {
    local mdp="$1"
    local dt nsteps ps ref_t new_ps new_t

    dt="$(mdp_read_value dt "${mdp}")"
    [[ -n "${dt}" ]] && MDP_DT="${dt}"
    nsteps="$(mdp_read_value nsteps "${mdp}")"
    ps="$(mdp_nsteps_to_ps "${nsteps}")"
    ref_t="$(mdp_read_value ref_t "${mdp}")"

    echo ""
    printf '%s\n' "$(t mdp_nvt_hdr "${mdp}")"
    printf '%s\n' "$(t mdp_current_nvt "${ps}" "${ref_t}" "${nsteps}" "${MDP_DT}")"

    if [[ "${INTERACTIVE:-yes}" != "yes" ]]; then
        return 0
    fi

    new_ps="$(prompt_value "$(t mdp_prompt_ps)" "${ps}")"
    new_t="$(prompt_value "$(t mdp_prompt_temp)" "${ref_t}")"
    nsteps="$(mdp_ps_to_nsteps "${new_ps}")"

    mdp_set_scalar nsteps "${mdp}" "${nsteps}"
    _set_temp_mdp "${mdp}" "${new_t}"

    printf '%s\n' "$(t mdp_result_nvt "${nsteps}" "${new_ps}" "${new_t}")"
    prompt_edit_mdp "${mdp}"
}

configure_mdp_npt() {
    local mdp="$1"
    local dt nsteps ps ref_t ref_p new_ps new_t new_p

    dt="$(mdp_read_value dt "${mdp}")"
    [[ -n "${dt}" ]] && MDP_DT="${dt}"
    nsteps="$(mdp_read_value nsteps "${mdp}")"
    ps="$(mdp_nsteps_to_ps "${nsteps}")"
    ref_t="$(mdp_read_value ref_t "${mdp}")"
    ref_p="$(mdp_read_value ref_p "${mdp}")"
    ref_p="${ref_p:-1.0}"

    echo ""
    printf '%s\n' "$(t mdp_npt_hdr "${mdp}")"
    printf '%s\n' "$(t mdp_current_npt "${ps}" "${ref_t}" "${ref_p}" "${nsteps}")"

    if [[ "${INTERACTIVE:-yes}" != "yes" ]]; then
        return 0
    fi

    new_ps="$(prompt_value "$(t mdp_prompt_ps)" "${ps}")"
    new_t="$(prompt_value "$(t mdp_prompt_temp_short)" "${ref_t}")"
    new_p="$(prompt_value "$(t mdp_prompt_pressure)" "${ref_p}")"
    nsteps="$(mdp_ps_to_nsteps "${new_ps}")"

    mdp_set_scalar nsteps "${mdp}" "${nsteps}"
    _set_temp_mdp "${mdp}" "${new_t}"
    if grep -qE '^[[:space:]]*ref_p[[:space:]]*=' "${mdp}"; then
        mdp_set_scalar ref_p "${mdp}" "${new_p}"
    fi

    printf '%s\n' "$(t mdp_result_npt "${nsteps}" "${new_ps}" "${new_t}" "${new_p}")"
    prompt_edit_mdp "${mdp}"
}

configure_mdp_md() {
    local mdp="$1"
    local dt nsteps ns ref_t new_ns new_t

    dt="$(mdp_read_value dt "${mdp}")"
    [[ -n "${dt}" ]] && MDP_DT="${dt}"
    nsteps="$(mdp_read_value nsteps "${mdp}")"
    ns="$(mdp_nsteps_to_ns "${nsteps}")"
    ref_t="$(mdp_read_value ref_t "${mdp}")"

    echo ""
    printf '%s\n' "$(t mdp_md_hdr "${mdp}")"
    printf '%s\n' "$(t mdp_current_md "${ns}" "${ref_t}" "${nsteps}")"

    if [[ "${INTERACTIVE:-yes}" != "yes" ]]; then
        return 0
    fi

    new_ns="$(prompt_value "$(t mdp_prompt_ns)" "${ns}")"
    new_t="$(prompt_value "$(t mdp_prompt_temp_short)" "${ref_t}")"
    nsteps="$(mdp_ns_to_nsteps "${new_ns}")"

    mdp_set_scalar nsteps "${mdp}" "${nsteps}"
    _set_temp_mdp "${mdp}" "${new_t}"

    printf '%s\n' "$(t mdp_result_md "${nsteps}" "${new_ns}" "${new_t}")"
    prompt_edit_mdp "${mdp}"
}
