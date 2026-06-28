#!/usr/bin/env bash
# =============================================================================
# 06_truba_pack.sh - self-contained slurm + md.mdp nsteps + analiz notları
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/../lib/common.sh"

STAGE="06_truba_pack"
ANALYSIS_DOC="${MDPREP_DIR}/ANALYSIS.md"

stage_guard "${STAGE}" || exit 0

is_done "05_index_posre" || die "Önce: ./mdprep/run.sh stage 05"

log_info "================ TRUBA PAKETİ ================"
require_file "${PROTEIN_TOP}" "topoloji"
require_file "${INDEX_NDX}" "index.ndx"
require_file "${EM_MDP}" "em mdp"
require_file "${NVT_MDP}" "nvt mdp"
require_file "${NPT_MDP}" "npt mdp"
require_file "${PROD_MDP}" "md mdp"

for f in "${SLURM_EM}" "${SLURM_NVT}" "${SLURM_NPT}" "${SLURM_MD}" "${PROD_MDP}"; do
    [[ -f "${f}" ]] && backup_file "${f}"
done

# --- md.mdp nsteps (PROD_NS) ------------------------------------------------
nsteps=$((PROD_NS * 500000))
log_info "Production: ${PROD_NS} ns -> nsteps=${nsteps}"

if [[ "${DRY_RUN}" == "yes" ]]; then
    log_warn "DRY_RUN: slurm ve mdp yazımı atlandı."
    exit 0
fi

if grep -qE '^[[:space:]]*nsteps[[:space:]]*=' "${PROD_MDP}"; then
    sed -i "s/^[[:space:]]*nsteps[[:space:]]*=.*/nsteps                  = ${nsteps}     ; ${PROD_NS} ns (pipeline)/" \
        "${PROD_MDP}"
else
    die "${PROD_MDP} içinde nsteps satırı bulunamadı"
fi
log_ok "${PROD_MDP} nsteps=${nsteps}"

# --- slurm ortak başlık -----------------------------------------------------
truba_header() {
    local partition="$1"
    local jobname="$2"
    local time_limit="$3"
    local ntasks="$4"
    local cpus_per_task="${5:-1}"
    cat <<EOF
#!/bin/bash
#SBATCH -p ${partition}
#SBATCH -A ${TRUBA_ACCOUNT}
#SBATCH -J ${jobname}
#SBATCH -N 1
#SBATCH --ntasks=${ntasks}
#SBATCH --cpus-per-task=${cpus_per_task}
#SBATCH -C weka
#SBATCH --time=${time_limit}
#SBATCH -o slurm-%j.out
#SBATCH -e slurm-%j.err

module purge
module load comp/gcc/14.1.0 lib/openmpi/4.1.6 comp/cmake/3.31.1
source ${TRUBA_GMXRC}

export OMP_NUM_THREADS=\${SLURM_CPUS_PER_TASK:-1}
cd \$SLURM_SUBMIT_DIR

echo "=== \${SLURM_JOB_NAME} basladi: \$(date) ==="
EOF
}

# --- em.slurm (barbun — weka yok) -------------------------------------------
cat > "${SLURM_EM}" <<EOF
#!/bin/bash
#SBATCH -p ${TRUBA_PARTITION_EM}
#SBATCH -A ${TRUBA_ACCOUNT}
#SBATCH -J EM
#SBATCH -N 1
#SBATCH -n ${TRUBA_NTASKS_EM}
#SBATCH -c ${TRUBA_CPUS_PER_TASK_EM}
#SBATCH --time=01:00:00
#SBATCH -o slurm-%j.out
#SBATCH -e slurm-%j.err

export OMP_NUM_THREADS=\${SLURM_CPUS_PER_TASK}

cd \$SLURM_SUBMIT_DIR
echo "=== EM basladi: \$(date) ==="

gmx_mpi grompp -f ${EM_MDP} -c ${SOLV_IONS_GRO} -p ${PROTEIN_TOP} -o ${EM_TPR} -maxwarn ${GROMPP_MAXWARN}
mpirun gmx_mpi mdrun -v -deffnm em -ntomp \${OMP_NUM_THREADS}

echo "=== EM tamamlandi: \$(date) ==="
EOF

# --- nvt.slurm --------------------------------------------------------------
{
    truba_header "${TRUBA_PARTITION_MD}" "NVT" "04:00:00" "${TRUBA_NTASKS_MD}"
    cat <<EOF

gmx_mpi grompp -f ${NVT_MDP} -c ${EM_GRO} -r ${EM_GRO} -p ${PROTEIN_TOP} -n ${INDEX_NDX} -o ${NVT_TPR} -maxwarn ${GROMPP_MAXWARN}
mpirun -np \${SLURM_NTASKS} gmx_mpi mdrun -v -deffnm nvt

echo "=== NVT tamamlandi: \$(date) ==="
EOF
} > "${SLURM_NVT}"

# --- npt.slurm --------------------------------------------------------------
{
    truba_header "${TRUBA_PARTITION_MD}" "NPT" "08:00:00" "${TRUBA_NTASKS_MD}"
    cat <<EOF

gmx_mpi grompp -f ${NPT_MDP} -c nvt.gro -t nvt.cpt -r nvt.gro -p ${PROTEIN_TOP} -n ${INDEX_NDX} -o ${NPT_TPR} -maxwarn ${GROMPP_MAXWARN}
mpirun -np \${SLURM_NTASKS} gmx_mpi mdrun -v -deffnm npt

echo "=== NPT tamamlandi: \$(date) ==="
EOF
} > "${SLURM_NPT}"

# --- md.slurm ---------------------------------------------------------------
{
    truba_header "${TRUBA_PARTITION_MD}" "MD_${PROD_NS}ns" "3-00:00:00" "${TRUBA_NTASKS_MD}"
    cat <<EOF

gmx_mpi grompp -f ${PROD_MDP} -c npt.gro -t npt.cpt -p ${PROTEIN_TOP} -n ${INDEX_NDX} -o ${MD_TPR} -maxwarn ${GROMPP_MAXWARN}
mpirun -np \${SLURM_NTASKS} gmx_mpi mdrun -v -deffnm ${PROD_DEFFNM} -cpi ${PROD_DEFFNM}.cpt

echo "=== Production MD tamamlandi: \$(date) ==="
EOF
} > "${SLURM_MD}"

chmod +x "${SLURM_EM}" "${SLURM_NVT}" "${SLURM_NPT}" "${SLURM_MD}" 2>/dev/null || true

log_ok "Slurm dosyaları yazıldı: ${SLURM_EM}, ${SLURM_NVT}, ${SLURM_NPT}, ${SLURM_MD}"

# --- analiz notları ---------------------------------------------------------
cat > "${ANALYSIS_DOC}" <<EOF
# Analiz komutları

Sistem: \`${WORKDIR}\`
Production deffnm: \`${PROD_DEFFNM}\` (${PROD_NS} ns)

## TRUBA submit sırası

\`\`\`bash
cd \$SLURM_SUBMIT_DIR
sbatch ${SLURM_EM}
sbatch ${SLURM_NVT}    # EM bittikten sonra
sbatch ${SLURM_NPT}    # NVT bittikten sonra
sbatch ${SLURM_MD}     # NPT bittikten sonra
\`\`\`

## RMSD (protein backbone)

\`\`\`bash
echo -e "Backbone\\nBackbone" | gmx rms -s ${MD_TPR} -f ${PROD_DEFFNM}.xtc -o rmsd.xvg -tu ns
\`\`\`

## Rg (radius of gyration)

\`\`\`bash
echo "Protein" | gmx gyrate -s ${MD_TPR} -f ${PROD_DEFFNM}.xtc -o gyrate.xvg
\`\`\`

## H-bond (protein-ligand)

\`\`\`bash
gmx hbond -s ${MD_TPR} -f ${PROD_DEFFNM}.xtc -num hbond.xvg
\`\`\`

## Enerji

\`\`\`bash
echo "Potential" | gmx energy -f ${PROD_DEFFNM}.edr -o potential.xvg
\`\`\`

Grup adları \`index.ndx\` ile uyumlu olmalı (\`${GRP_PROTEIN_LIG}\`, \`${GRP_WATER_IONS}\`).
EOF

log_ok "Analiz notları: ${ANALYSIS_DOC}"
log_info "Pipeline hazırlığı tamamlandı. TRUBA'da sbatch ile sırayla gönder."

mark_done "${STAGE}"
