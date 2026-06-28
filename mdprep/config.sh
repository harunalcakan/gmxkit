#!/usr/bin/env bash
# =============================================================================
# config.sh - GROMACS protein-ligand MD hazırlık pipeline'ı için TEK config
# =============================================================================
# Bu dosya pipeline'ın TEK gerçek kaynağıdır (single source of truth).
# Hiçbir stage script'i dosya adı / parametre GÖMMEZ; her şey buradan okunur.
# Tutorial'daki "jz4" gibi adlar burada LIG'e karşılık gelir.
#
# DİKKAT (WSL/Linux): Bu dosyalar LF satır sonu ile çalışmalıdır. Windows'tan
# düzenlersen CRLF olmadığından emin ol. Gerekirse:  sed -i 's/\r$//' *.sh
# =============================================================================

# -----------------------------------------------------------------------------
# 0) ÇALIŞMA DİZİNİ
# -----------------------------------------------------------------------------
# Pipeline yerinde (in-place) çalışır: girdi dosyaları bu dizindedir.
# WORKDIR boş bırakılırsa config.sh'in bir üst klasörü (mdprep'in üstü) kullanılır.
WORKDIR=""

# -----------------------------------------------------------------------------
# 0b) UI LANGUAGE (en | tr) — ./md lang tr
# -----------------------------------------------------------------------------
MDLANG="en"

# -----------------------------------------------------------------------------
# 1) GMX İKİLİSİ (yerel hazırlık için)
# -----------------------------------------------------------------------------
# Yerel WSL/iş istasyonunda hazırlık + simülasyon "gmx" ile çalışır.
GMX="gmx"
GMX_MDRUN_EXTRA=""               # örn. "-nt 8" veya "-ntmpi 4 -ntomp 2"

# Çalıştırma hedefi: local (iş istasyonu) | truba (slurm — eski)
RUN_TARGET="local"

# -----------------------------------------------------------------------------
# 2) FORCE FIELD ve SU MODELİ
# -----------------------------------------------------------------------------
# Klasördeki .ff dizininin adından ".ff" çıkarılmış hali (pdb2gmx -ff buna verilir).
FF_NAME="charmm36-feb2026_ljpme_cgenff-5.0"
FF_DIR="${FF_NAME}.ff"            # diskteki gerçek klasör
WATER_MODEL="tip3p"               # watermodels.dat: CHARMM-modified TIP3P (önerilen)

# -----------------------------------------------------------------------------
# 3) GİRDİ DOSYALARI
# -----------------------------------------------------------------------------
PROTEIN_PDB="protein.pdb"
PROTEIN_PDB_PREP="protein_prep.pdb"   # 00b çıktısı (METAL_ENZYME=yes)
LIGAND_MOL2="ligand.mol2"
LIG_STR_ALT="ligand_fix.str"          # eski workflow adı (02 fallback)

# Yardımcı script'ler (klasörde mevcut)
SORT_MOL2_PL="sort_mol2_bonds.pl"

# cgenff dönüştürücü — BACKEND'e göre seçilir (02_ligand.sh)
# legacy: Python 2.7 + networkx 1.11 (kullanıcı doğruladı; tutorial uyumlu)
# py3:    Python 3 + networkx 2.x (cgenff_charmm2gmx_py3_nx2.py)
CGENFF_BACKEND="py3"
CGENFF_SCRIPT_LEGACY="cgenff_charmm2gmx_py2.py"
CGENFF_SCRIPT_PY3="cgenff_charmm2gmx_py3_nx2.py"
CGENFF_SCRIPT=""   # boş = backend'e göre otomatik; elle override edilebilir
CGENFF_CONDA_ENV="mdprep-cgenff"

# -----------------------------------------------------------------------------
# 3b) PROTEİN AŞAMASI ÇIKTILARI (pdb2gmx)
# -----------------------------------------------------------------------------
PROTEIN_GRO="processed.gro"
PROTEIN_TOP="topol.top"
PROTEIN_POSRE="posre.itp"

# pdb2gmx bayrakları. CA için HSD PDB'de hazırlanır (00b); -his gerekmez.
PDB2GMX_IGNH="yes"
PDB2GMX_MISSING="yes"
PDB2GMX_INTER="no"
PDB2GMX_TER="no"

# -----------------------------------------------------------------------------
# 3c) METALLOenzim (Karbonik Anhidraz / Zn2+) — kılavuz Adım 1–3
# -----------------------------------------------------------------------------
METAL_ENZYME="yes"                    # no → 00b atlanır, genel protein-ligand
METAL_CHAIN="A"
METAL_ION_RESNAME="ZN"
# Zn koordinasyon Histidinleri → HSD (CA tipik: 94, 96, 119)
METAL_HSD_RESIDUES="94 96 119"

# -----------------------------------------------------------------------------
# 4) LİGAND KİMLİĞİ
# -----------------------------------------------------------------------------
# ligand.mol2 içindeki RESI/residue adı. Bu ad cgenff'e verilir ve .str içindeki
# RESI ile AYNI olmalıdır. cgenff script'i çıktıları KÜÇÜK HARF üretir:
#   LIG -> lig.itp, lig.prm, lig.top, lig_ini.pdb
LIG_RESNAME="LIG"
LIG_LOWER="lig"                   # cgenff çıktı öneki (otomatik küçük harf)

# CGenFF .str dosyası (web sunucusundan manuel indirilir). Manuel kapı bunu bekler.
LIG_STR="${LIG_LOWER}.str"
CGENFF_URL="https://cgenff.umaryland.edu/initguess/"

# -----------------------------------------------------------------------------
# 4b) LİGAND AŞAMASI ÇIKTILARI
# -----------------------------------------------------------------------------
LIGAND_MOL2_SORTED="ligand_sorted.mol2"   # sort_mol2_bonds.pl çıktısı (CGenFF'e yüklenecek)
LIG_ITP="${LIG_LOWER}.itp"
LIG_PRM="${LIG_LOWER}.prm"
LIG_TOP="${LIG_LOWER}.top"
LIG_INI_PDB="${LIG_LOWER}_ini.pdb"
LIGAND_GRO="ligand.gro"

# -----------------------------------------------------------------------------
# 4c) KOMPLEKS ve SOLVASYON ÇIKTILARI
# -----------------------------------------------------------------------------
COMPLEX_GRO="complex.gro"
NEWBOX_GRO="newbox.gro"
SOLV_GRO="solv.gro"
SOLV_IONS_GRO="solv_ions.gro"

# -----------------------------------------------------------------------------
# 4d) INDEX ve EQUİLİBRASYON
# -----------------------------------------------------------------------------
INDEX_NDX="index.ndx"
INDEX_LIG_NDX="index_lig.ndx"
EM_MDP="em.mdp"
NVT_MDP="nvt.mdp"
NPT_MDP="npt.mdp"
EM_TPR="em.tpr"
EM_GRO="em.gro"
NVT_TPR="nvt.tpr"
NPT_TPR="npt.tpr"
NVT_DEFFNM="nvt"
NPT_DEFFNM="npt"

# Yerel EM mdrun (stage 04) — hayır: EM ./md queue ile (NVT/NPT/MD ile aynı kuyruk)
LOCAL_EM_RUN="no"

# Hazırlık: kritik GROMACS kararlarından önce parametreleri göster + onay iste
# yes → pdb2gmx FF/su, genion, index vb. öncesi [Y/n/e=config]
# no  → tam otomatik (CI / batch)
PREP_INTERACTIVE="yes"

# Yerel dengeleme + üretim (stage 06) — iş istasyonu
# Uzun simülasyonlar ./md queue (yerel kuyruk) veya ./md → [J] ile gider.
LOCAL_MD_RUN="no"                 # yes → NVT/NPT/MD mdrun otomatik (uzun sürer!)
LOCAL_NVT_RUN="no"                # stage 06: NVT mdrun
LOCAL_NPT_RUN="no"                # stage 06: NPT mdrun
LOCAL_PROD_RUN="no"               # stage 06: 300 ns MD (genelde elle başlatılır)

# run_local_md.sh: her adımda süre/sıcaklık sor (Enter = mevcut değer)
INTERACTIVE_MD="yes"

# Ligand–aktif site kontrolü (gmx mindist + RMSD; VMD gerekmez)
CHECK_BINDING="yes"
CHECK_BINDING_STRICT="no"         # yes → eşik aşılırsa script durur
CHECK_LIG_RESNAME="2Q38"          # gro/tpr ligand residue adı (cgenff)
CHECK_ZN_LIG_WARN="0.35"          # nm — uyarı
CHECK_ZN_LIG_FAIL="0.50"
CHECK_HSD_LIG_WARN="0.40"
CHECK_HSD_LIG_FAIL="0.55"
CHECK_LIG_RMSD_WARN="0.25"
CHECK_LIG_RMSD_FAIL="0.40"

# Simülasyon sıcaklığı (K) — fizyolojik 310 K
REF_TEMP="310"
NPT_STEPS="250000"                # 500 ps @ 2 fs
NVT_STEPS="50000"                 # 100 ps @ 2 fs (ısınma)

# -----------------------------------------------------------------------------
# 4e) TRUBA slurm (RUN_TARGET=truba ise stage 06_truba_pack kullanılır)
# -----------------------------------------------------------------------------
SLURM_EM="em.slurm"
SLURM_NVT="nvt.slurm"
SLURM_NPT="npt.slurm"
SLURM_MD="md.slurm"
TRUBA_GMXRC="/arf/home/hnalcakan/gromacs_2026/bin/GMXRC"
TRUBA_ACCOUNT="hnalcakan"
TRUBA_PARTITION_EM="barbun"
TRUBA_PARTITION_MD="hamsi"
TRUBA_NTASKS_EM="4"
TRUBA_CPUS_PER_TASK_EM="5"
TRUBA_NTASKS_MD="56"

# Kuyruk backend: local (varsayılan, iş istasyonu PID kuyruğu) | slurm (TRUBA sbatch)
QUEUE_BACKEND="local"
# Yerel kayıt: mdprep/.state/jobs.json  |  Slurm: mdprep/.state/jobs.tsv
QUEUE_USE_DEPENDENCY="yes"        # chain: önceki job bitene kadar bekle

# Python yardımcıları (mdprep/lib/)
GRO_TOOLS="mdprep/lib/gro_tools.py"
TOP_TOOLS="mdprep/lib/top_tools.py"
NDX_TOOLS="mdprep/lib/ndx_tools.py"

# -----------------------------------------------------------------------------
# 5) KUTU ve SOLVASYON
# -----------------------------------------------------------------------------
BOX_TYPE="dodecahedron"           # editconf -bt
BOX_DIST="1.0"                    # editconf -d (nm), protein-kenar mesafesi
WATER_GRO="spc216.gro"            # solvate -cs (TIP3P için spc216 standarttır)

# -----------------------------------------------------------------------------
# 6) İYONLAR
# -----------------------------------------------------------------------------
ION_PNAME="NA"
ION_NNAME="CL"
ION_NEUTRAL="yes"
ION_CONC="0.15"                   # fizyolojik NaCl (M); boş=sadece nötrleştir
IONS_MDP="ions.mdp"

# genion'da iyonlarla yer değiştirecek grup (SOL = su). Adı parse ile doğrulanır.
SOLVENT_GROUP="SOL"

# -----------------------------------------------------------------------------
# 7) INDEX GRUPLARI (mdp dosyalarındaki tc-grps ile BİREBİR uyumlu olmalı)
# -----------------------------------------------------------------------------
# mdp tc-grps ile BİREBİR uyumlu (CA kılavuzu: Protein_ZN_LIG + Solvent)
GRP_PROTEIN_LIG="Protein_ZN_LIG"
GRP_WATER_IONS="Solvent"

# -----------------------------------------------------------------------------
# 8) LİGAND POSİSYON KISITLAMA (posre)
# -----------------------------------------------------------------------------
LIG_POSRE_ITP="posre_${LIG_LOWER}.itp"
LIG_POSRE_FC="1000 1000 1000"     # genrestr -fc (x y z)

# -----------------------------------------------------------------------------
# 9) ÜRETİM (PRODUCTION) MD
# -----------------------------------------------------------------------------
# md.mdp kanonik. deffnm = md_out (md.slurm ile uyumlu).
PROD_MDP="md.mdp"
PROD_DEFFNM="md_0_1"
MD_TPR="${PROD_DEFFNM}.tpr"
PROD_NS="300"

# grompp -maxwarn (lig.prm çakışmaları için kılavuz: 15)
GROMPP_MAXWARN="15"

# -----------------------------------------------------------------------------
# 10) ANALİZ — PBC düzeltme + RMSD/RMSF/Rg/SASA (./md analyze)
# -----------------------------------------------------------------------------
# trjconv: -pbc mol -ur compact -center -fit rot+trans (gruplar index.ndx'ten)
ANALYSIS_OUT_DIR="mdprep/logs/analysis"
ANALYSIS_PBC_XTC="md_pbc.xtc"
ANALYSIS_FIT_GROUP="Backbone"           # trjconv fit + ligand RMSD hizalama
ANALYSIS_CENTER_GROUP="Protein"         # trjconv -center
ANALYSIS_LIG_GROUP=""                   # boş = CHECK_LIG_RESNAME (2Q38)
ANALYSIS_RMSD_BB_GROUP="Backbone"       # protein RMSD
ANALYSIS_RMSF_GROUP="C-alpha"
ANALYSIS_RG_GROUP="Protein"
ANALYSIS_SASA_PROTEIN="Protein"
ANALYSIS_SASA_LIG=""                    # boş = CHECK_LIG_RESNAME
ANALYSIS_USE_PBC_FOR_BINDING="yes"      # binding check PBC traj kullansın

# -----------------------------------------------------------------------------
# 11) DAVRANIŞ BAYRAKLARI
# -----------------------------------------------------------------------------
# DRY_RUN=yes ./run.sh ile geçersiz kılınabilir (config sabiti env'i ezmesin)
: "${DRY_RUN:=no}"                      # "yes" -> komutlar çalıştırılmaz, sadece loglanır

# -----------------------------------------------------------------------------
# 12) PYTHON ORTAMI
# -----------------------------------------------------------------------------
: "${DRY_RUN:=no}"

PIPELINE_VENV_DIR="mdprep/.venv"
REQ_FILE="mdprep/requirements.txt"
REQ_PY3_FILE="mdprep/requirements-py3.txt"
ENV_LEGACY_FILE="mdprep/environment-legacy.yml"
CGENFF_PYTHON_PTR="mdprep/.cgenff_python_path"
