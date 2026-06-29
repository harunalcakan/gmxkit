# GmxKit v1.0.0

First public release — GROMACS protein–ligand MD prep, local job queue, and analysis.

## Included in this zip

- GmxKit scripts (`mdprep/`, `./md` launcher)
- Bundled: force field, MDP templates, helper scripts
- Optional demo inputs: `examples/metalloenzyme-sample/`
- CGenFF helper scripts (`cgenff_*.py`, `sort_mol2_bonds.pl`)
- English + Turkish UI (`./md lang en|tr`)

## Not included (you must add)

- **GROMACS** — install separately; set `GMX=` in `mdprep/config.sh`
- **Force field** — `charmm36-*.ff/` folder in project root

## Quick start

```bash
chmod +x md
# Add charmm36-....ff/ to this folder
./md install
./md check
./md
```

See **INSTALL.md** and **QUICKSTART_CHECKLIST.md** in the zip.

## Requirements

- WSL2 (Ubuntu) or Linux
- GROMACS 2020+ recommended
- ~500 MB disk for venv + prep outputs (MD trajectories need more)
