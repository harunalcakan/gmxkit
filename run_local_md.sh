#!/usr/bin/env bash
# Yerel GROMACS MD — 300 ns @ 310 K (CA/Zn kılavuzu)
set -o errexit -o nounset -o pipefail
cd "/mnt/c/Users/zenbook/Desktop/native_ca1_test_cursor"

GMX="gmx"
MW="15"
NDX="index.ndx"
TOP="topol.top"
MDRUN_EXTRA=""
INTERACTIVE="yes"

# shellcheck source=mdprep/lib/mdp_prompt.sh
source "/mnt/c/Users/zenbook/Desktop/native_ca1_test_cursor/mdprep/lib/mdp_prompt.sh"
# shellcheck source=mdprep/config.sh
source "/mnt/c/Users/zenbook/Desktop/native_ca1_test_cursor/mdprep/config.sh"

_run_binding_check() {
  local phase="$1"
  [[ "${CHECK_BINDING:-yes}" == "yes" ]] || return 0
  echo ""
  if ! bash "/mnt/c/Users/zenbook/Desktop/native_ca1_test_cursor/mdprep/lib/check_binding.sh" "${phase}"; then
    local rc=$?
    if [[ "${CHECK_BINDING_STRICT:-no}" == "yes" ]]; then
      echo "[run_local_md] Binding check başarısız (strict)." >&2
      exit "${rc}"
    fi
  fi
}

usage() {
  cat <<USAGE
Kullanım: $0 {nvt|npt|md|all|resume} [-y]

  nvt / npt / md   Adımı çalıştır (INTERACTIVE=yes ise süre/sıcaklık sorulur)
  all              Üç adımı sırayla çalıştır
  resume           Production MD'yi checkpoint'ten sürdür
  -y               Soru sormadan mevcut mdp değerlerini kullan

Örnek:
  ./run_local_md.sh npt          # NPT süresini/sıcaklığını sor
  ./run_local_md.sh npt -y       # npt.mdp olduğu gibi
  INTERACTIVE=no ./run_local_md.sh md
USAGE
}

parse_args() {
  PHASE=""
  for arg in "$@"; do
    case "${arg}" in
      -y|--yes) INTERACTIVE=no ;;
      nvt|npt|md|all|resume) PHASE="${arg}" ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Bilinmeyen argüman: ${arg}"; usage; exit 1 ;;
    esac
  done
  PHASE="${PHASE:-all}"
}

run_nvt() {
  configure_mdp_nvt "nvt.mdp"
  ${GMX} grompp -f nvt.mdp -c em.gro -r em.gro -p ${TOP} -n ${NDX} \
    -o nvt.tpr -maxwarn ${MW}
  ${GMX} mdrun -v -deffnm nvt ${MDRUN_EXTRA}
  _run_binding_check nvt
}

run_npt() {
  configure_mdp_npt "npt.mdp"
  ${GMX} grompp -f npt.mdp -c nvt.gro -r nvt.gro -t nvt.cpt \
    -p ${TOP} -n ${NDX} -o npt.tpr -maxwarn ${MW}
  ${GMX} mdrun -v -deffnm npt ${MDRUN_EXTRA}
  _run_binding_check npt
}

run_prod() {
  configure_mdp_md "md.mdp"
  ${GMX} grompp -f md.mdp -c npt.gro -t npt.cpt \
    -p ${TOP} -n ${NDX} -o md_0_1.tpr -maxwarn ${MW}
  ${GMX} mdrun -v -deffnm md_0_1 ${MDRUN_EXTRA}
  _run_binding_check md
}

parse_args "$@"

case "${PHASE}" in
  nvt)    run_nvt ;;
  npt)    run_npt ;;
  md)     run_prod ;;
  all)    run_nvt; run_npt; run_prod ;;
  resume) ${GMX} mdrun -v -deffnm md_0_1 -cpi md_0_1.cpt ${MDRUN_EXTRA} ;;
  *)      usage; exit 1 ;;
esac
