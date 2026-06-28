#!/usr/bin/env bash
# =============================================================================
# 06_local_md.sh - Yerel iş istasyonu: NVT, NPT, Production MD (kılavuz Adım 8–10)
# TRUBA slurm yerine gmx grompp + mdrun
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="06_local_md"
RUN_SCRIPT="run_local_md.sh"
ANALYSIS_DOC="${MDPREP_DIR}/ANALYSIS.md"

stage_guard "${STAGE}" || exit 0

is_done "05_index_posre" || die "Önce: ./mdprep/run.sh stage 05"

log_info "================ YEREL MD (NVT → NPT → Production) ================"
require_file "${PROTEIN_TOP}" "topoloji"
require_file "${INDEX_NDX}" "index.ndx"
require_file "${EM_MDP}" "em mdp"
require_file "${NVT_MDP}" "nvt mdp"
require_file "${NPT_MDP}" "npt mdp"
require_file "${PROD_MDP}" "md mdp"
if [[ -f "${EM_GRO}" ]]; then
    log_info "EM yapı: ${EM_GRO}"
elif [[ -f "${EM_TPR}" ]] && [[ "${LOCAL_EM_RUN}" != "yes" ]]; then
    log_info "em.gro henüz yok — em.tpr hazır; EM mdrun kuyrukta (./md queue submit em)."
else
    require_file "${EM_GRO}" "em.gro (veya önce stage 04 + kuyruk EM)"
fi

nsteps_prod=$((PROD_NS * 500000))
log_info "Sıcaklık: ${REF_TEMP} K | Production: ${PROD_NS} ns (nsteps=${nsteps_prod})"

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: mdp/run script yazımı atlandı."
    exit 0
fi

# --- mdp senkronizasyonu (SKIP_MDP_AUTO_SYNC=yes ile atlanır — test/kısa koşu) ---
if [[ "${SKIP_MDP_AUTO_SYNC:-no}" != "yes" ]]; then
if grep -qE '^[[:space:]]*nsteps[[:space:]]*=' "${PROD_MDP}"; then
    sed -i "s/^[[:space:]]*nsteps[[:space:]]*=.*/nsteps                  = ${nsteps_prod}     ; ${PROD_NS} ns/" \
        "${PROD_MDP}"
fi
if grep -qE '^[[:space:]]*nsteps[[:space:]]*=' "${NVT_MDP}"; then
    sed -i "s/^[[:space:]]*nsteps[[:space:]]*=.*/nsteps                  = ${NVT_STEPS}      ; NVT ısınma/" \
        "${NVT_MDP}"
fi
if grep -qE '^[[:space:]]*nsteps[[:space:]]*=' "${NPT_MDP}"; then
    sed -i "s/^[[:space:]]*nsteps[[:space:]]*=.*/nsteps                  = ${NPT_STEPS}      ; NPT dengeleme/" \
        "${NPT_MDP}"
fi
for mdp in "${NVT_MDP}" "${NPT_MDP}" "${PROD_MDP}"; do
    sed -i "s/ref_t[[:space:]]*=.*/ref_t                   = ${REF_TEMP}   ${REF_TEMP}/" "${mdp}" 2>/dev/null || true
    sed -i "s/gen_temp[[:space:]]*=.*/gen_temp                = ${REF_TEMP}/" "${mdp}" 2>/dev/null || true
    sed -i "s/tc-grps[[:space:]]*=.*/tc-grps                 = ${GRP_PROTEIN_LIG} ${GRP_WATER_IONS}/" "${mdp}" 2>/dev/null || true
done
log_ok "MDP dosyaları güncellendi (${REF_TEMP} K, tc-grps=${GRP_PROTEIN_LIG}/${GRP_WATER_IONS})."
else
    log_info "SKIP_MDP_AUTO_SYNC=yes — mdp nsteps/sıcaklık otomatik yazımı atlandı."
fi

# --- run_local_md.sh --------------------------------------------------------
[[ -f "${RUN_SCRIPT}" ]] && backup_file "${RUN_SCRIPT}"

cat > "${RUN_SCRIPT}" <<EOF
#!/usr/bin/env bash
# Yerel GROMACS MD — ${PROD_NS} ns @ ${REF_TEMP} K (CA/Zn kılavuzu)
set -o errexit -o nounset -o pipefail
cd "${WORKDIR}"

GMX="${GMX}"
MW="${GROMPP_MAXWARN}"
NDX="${INDEX_NDX}"
TOP="${PROTEIN_TOP}"
MDRUN_EXTRA="${GMX_MDRUN_EXTRA}"
INTERACTIVE="${INTERACTIVE_MD:-yes}"

# shellcheck source=mdprep/lib/mdp_prompt.sh
source "${MDPREP_DIR}/lib/mdp_prompt.sh"
# shellcheck source=mdprep/config.sh
source "${MDPREP_DIR}/config.sh"

_run_binding_check() {
  local phase="\$1"
  [[ "\${CHECK_BINDING:-yes}" == "yes" ]] || return 0
  echo ""
  if ! bash "${MDPREP_DIR}/lib/check_binding.sh" "\${phase}"; then
    local rc=\$?
    if [[ "\${CHECK_BINDING_STRICT:-no}" == "yes" ]]; then
      echo "[run_local_md] Binding check başarısız (strict)." >&2
      exit "\${rc}"
    fi
  fi
}

usage() {
  cat <<USAGE
Kullanım: \$0 {nvt|npt|md|all|resume} [-y]

  nvt / npt / md   Adımı çalıştır (INTERACTIVE=yes ise süre/sıcaklık sorulur)
  all              Üç adımı sırayla çalıştır
  resume           Production MD'yi checkpoint'ten sürdür
  -y               Soru sormadan mevcut mdp değerlerini kullan

Örnek:
  ./${RUN_SCRIPT} npt          # NPT süresini/sıcaklığını sor
  ./${RUN_SCRIPT} npt -y       # npt.mdp olduğu gibi
  INTERACTIVE=no ./${RUN_SCRIPT} md
USAGE
}

parse_args() {
  PHASE=""
  for arg in "\$@"; do
    case "\${arg}" in
      -y|--yes) INTERACTIVE=no ;;
      nvt|npt|md|all|resume) PHASE="\${arg}" ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Bilinmeyen argüman: \${arg}"; usage; exit 1 ;;
    esac
  done
  PHASE="\${PHASE:-all}"
}

run_nvt() {
  configure_mdp_nvt "${NVT_MDP}"
  \${GMX} grompp -f ${NVT_MDP} -c ${EM_GRO} -r ${EM_GRO} -p \${TOP} -n \${NDX} \\
    -o ${NVT_TPR} -maxwarn \${MW}
  \${GMX} mdrun -v -deffnm ${NVT_DEFFNM} \${MDRUN_EXTRA}
  _run_binding_check nvt
}

run_npt() {
  configure_mdp_npt "${NPT_MDP}"
  \${GMX} grompp -f ${NPT_MDP} -c ${NVT_DEFFNM}.gro -r ${NVT_DEFFNM}.gro -t ${NVT_DEFFNM}.cpt \\
    -p \${TOP} -n \${NDX} -o ${NPT_TPR} -maxwarn \${MW}
  \${GMX} mdrun -v -deffnm ${NPT_DEFFNM} \${MDRUN_EXTRA}
  _run_binding_check npt
}

run_prod() {
  configure_mdp_md "${PROD_MDP}"
  \${GMX} grompp -f ${PROD_MDP} -c ${NPT_DEFFNM}.gro -t ${NPT_DEFFNM}.cpt \\
    -p \${TOP} -n \${NDX} -o ${MD_TPR} -maxwarn \${MW}
  \${GMX} mdrun -v -deffnm ${PROD_DEFFNM} \${MDRUN_EXTRA}
  _run_binding_check md
}

parse_args "\$@"

case "\${PHASE}" in
  nvt)    run_nvt ;;
  npt)    run_npt ;;
  md)     run_prod ;;
  all)    run_nvt; run_npt; run_prod ;;
  resume) \${GMX} mdrun -v -deffnm ${PROD_DEFFNM} -cpi ${PROD_DEFFNM}.cpt \${MDRUN_EXTRA} ;;
  *)      usage; exit 1 ;;
esac
EOF
chmod +x "${RUN_SCRIPT}"
log_ok "Yerel çalıştırma script'i: ./${RUN_SCRIPT} [nvt|npt|md|all|resume]"

cat > "${WORKDIR}/check_binding.sh" <<'CHEOF'
#!/usr/bin/env bash
exec bash "__MDPREP_DIR__/lib/check_binding.sh" "$@"
CHEOF
sed -i "s|__MDPREP_DIR__|${MDPREP_DIR}|g" "${WORKDIR}/check_binding.sh"
chmod +x "${WORKDIR}/check_binding.sh"
log_ok "Bağ kontrolü: ./check_binding.sh {em|nvt|npt|md}"

# --- opsiyonel otomatik mdrun ------------------------------------------------
_do_mdrun() {
    local phase="$1"
    shift
    log_info "--- yerel ${phase} (mdrun) ---"
    run_gmx "mdrun ${phase}" -- mdrun -v "$@" ${GMX_MDRUN_EXTRA} \
        || die "${phase} mdrun başarısız"
}

if [[ "${LOCAL_MD_RUN}" == "yes" || "${LOCAL_NVT_RUN}" == "yes" ]]; then
    run_gmx "grompp nvt" -- grompp -f "${NVT_MDP}" -c "${EM_GRO}" -r "${EM_GRO}" \
        -p "${PROTEIN_TOP}" -n "${INDEX_NDX}" -o "${NVT_TPR}" -maxwarn "${GROMPP_MAXWARN}" \
        ::expect:: "${NVT_TPR}" || die "NVT grompp başarısız"
    _do_mdrun "nvt" -deffnm "${NVT_DEFFNM}"
    log_ok "NVT tamamlandı: ${NVT_DEFFNM}.gro"
fi

if [[ "${LOCAL_MD_RUN}" == "yes" || "${LOCAL_NPT_RUN}" == "yes" ]]; then
    require_file "${NVT_DEFFNM}.gro" "nvt.gro"
    run_gmx "grompp npt" -- grompp -f "${NPT_MDP}" -c "${NVT_DEFFNM}.gro" -r "${NVT_DEFFNM}.gro" \
        -t "${NVT_DEFFNM}.cpt" -p "${PROTEIN_TOP}" -n "${INDEX_NDX}" -o "${NPT_TPR}" \
        -maxwarn "${GROMPP_MAXWARN}" \
        ::expect:: "${NPT_TPR}" || die "NPT grompp başarısız"
    _do_mdrun "npt" -deffnm "${NPT_DEFFNM}"
    log_ok "NPT tamamlandı: ${NPT_DEFFNM}.gro"
fi

if [[ "${LOCAL_MD_RUN}" == "yes" || "${LOCAL_PROD_RUN}" == "yes" ]]; then
    require_file "${NPT_DEFFNM}.gro" "npt.gro"
    run_gmx "grompp md" -- grompp -f "${PROD_MDP}" -c "${NPT_DEFFNM}.gro" -t "${NPT_DEFFNM}.cpt" \
        -p "${PROTEIN_TOP}" -n "${INDEX_NDX}" -o "${MD_TPR}" -maxwarn "${GROMPP_MAXWARN}" \
        ::expect:: "${MD_TPR}" || die "MD grompp başarısız"
    log_warn "Production MD ${PROD_NS} ns başlıyor — uzun sürebilir."
    _do_mdrun "md" -deffnm "${PROD_DEFFNM}"
    log_ok "Production MD tamamlandı: ${PROD_DEFFNM}.xtc"
fi

# --- analiz notları ---------------------------------------------------------
cat > "${ANALYSIS_DOC}" <<EOF
# Analiz komutları (yerel)

Sistem: \`${WORKDIR}\`
Production: \`${PROD_DEFFNM}\` (${PROD_NS} ns @ ${REF_TEMP} K)
Index grupları: \`${GRP_PROTEIN_LIG}\`, \`${GRP_WATER_IONS}\`

## Çalıştırma

\`\`\`bash
./${RUN_SCRIPT} nvt    # etkileşimli: süre (ps), sıcaklık (K)
./${RUN_SCRIPT} npt    # etkileşimli: süre, T, basınç
./${RUN_SCRIPT} md     # etkileşimli: süre (ns), sıcaklık
./${RUN_SCRIPT} npt -y # soru sormadan mevcut mdp ile çalıştır
# veya: ./${RUN_SCRIPT} all

# Kesinti sonrası:
./${RUN_SCRIPT} resume
\`\`\`

## Kalite kontrol

\`\`\`bash
echo "Temperature" | ${GMX} energy -f ${NVT_DEFFNM}.edr -o nvt_temp.xvg
echo "Density" | ${GMX} energy -f ${NPT_DEFFNM}.edr -o npt_density.xvg
grep -E "$(echo ${METAL_HSD_RESIDUES} | sed 's/ /|/g')HSD|${METAL_ION_RESNAME}" ${PROTEIN_GRO}
\`\`\`

## RMSD

\`\`\`bash
echo -e "Backbone\\nBackbone" | ${GMX} rms -s ${MD_TPR} -f ${PROD_DEFFNM}.xtc -o rmsd.xvg -tu ns
\`\`\`
EOF

log_ok "Analiz notları: ${ANALYSIS_DOC}"
log_info "Sonraki adım: ./${RUN_SCRIPT} nvt  (veya config'te LOCAL_NVT_RUN=yes ile otomatik)"

mark_done "${STAGE}"
