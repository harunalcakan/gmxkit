# GmxKit — User Guide

GmxKit prepares and runs GROMACS protein–ligand MD simulations from a single menu (`./md`).

## Quick start

```bash
./md install          # Python deps (not GROMACS)
./md lang en          # UI language: en | tr (default: en)
./md                  # main menu
```

## Main menu (after prep stage 06)

| Key | Action |
|-----|--------|
| **J** | Queue — background EM/NVT/NPT/MD |
| **S** | Simulation — foreground (asks duration/temperature) |
| **K** | Control — binding checks, audit |
| **L** | Analysis — PBC trajectory + RMSD/RMSF/Rg/SASA |
| **P** | Prep — stages 00–06 |
| **A** | Tools — cleanup, reset, config |

## CLI examples

```bash
./md prep                    # run prep pipeline
./md queue chain             # EM → NVT → NPT → MD in queue
./md analyze                 # full analysis report
./md audit --fix-mdp         # prep validation + MDP sync
./md lang tr                 # switch UI to Turkish
```

## Prep stages

| ID | Stage |
|----|--------|
| 00 | Environment check |
| 00b | Metalloenzyme PDB (optional) |
| 01 | Protein (pdb2gmx) |
| 02 | Ligand (CGenFF) |
| 03 | Complex |
| 04 | Solvation + ions + em.tpr |
| 05 | Index + ligand posre |
| 06 | Local MD scripts |

## Requirements you install

- GROMACS (`gmx`) — set `GMX=` in `mdprep/config.sh`
- Force field folder (`charmm36-*.ff`)
- Input files: `protein.pdb`, `ligand.mol2`, `*.mdp`

See also: [KURULUM_YENI_PC.md](../KURULUM_YENI_PC.md) (install notes), [ANALYSIS.md](../ANALYSIS.md).
