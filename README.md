# GmxKit

GROMACS protein–ligand MD toolkit: prep, local job queue, simulation, and analysis. Menu-driven via `./md` on WSL/Linux.

**Default UI language: English.** Switch anytime:

```bash
./md lang tr    # Turkish menus
./md lang en    # English (default)
```

Language is saved in `mdprep/config.sh` (`MDLANG=en|tr`).

## Requirements

| You install | `./md install` provides |
|-------------|-------------------------|
| **GROMACS** (`gmx`) | Python venv (numpy, networkx) |
| Force field (`charmm36-*.ff`) | `./md` launcher |
| `protein.pdb`, `ligand.mol2`, `*.mdp` | — |

Details: [Installation guide](mdprep/docs/en/INSTALL.md) · [First-run checklist](mdprep/docs/en/FIRST_RUN_CHECKLIST.md)

## Download (end users)

**[GitHub Releases](https://github.com/harunalcakan/gmxkit/releases)** — download `gmxkit-*.zip`, add force field + GROMACS, then `./md install`.

Or clone:

```bash
git clone https://github.com/harunalcakan/gmxkit.git
```

## Quick start

```bash
# 1) Place force field in project root
# 2) Ensure gmx is on PATH (config.sh → GMX="gmx")
./md install
./md
```

## Commands

| Command | Description |
|---------|-------------|
| `./md` | Interactive menu |
| `./md prep` | Prep stages 00–06 |
| `./md queue chain` | Queue EM → NVT → NPT → MD |
| `./md analyze` | PBC + RMSD/RMSF/Rg/SASA |
| `./md audit` | Prep validation |
| `./md install` | Python dependencies (no GROMACS) |
| `./md lang en\|tr` | UI language |

## Project layout

```
./
├── md                 # GmxKit launcher
├── mdprep/            # pipeline scripts
│   ├── i18n/          # en.sh, tr.sh UI strings
│   └── docs/en|tr/    # user guides
├── protein.pdb
├── ligand.mol2
├── *.mdp
└── charmm36-....ff/   # not in git — add locally
```

## Portable package

```bash
bash mdprep/export_portable.sh /target/dir
```

Excludes `.venv`, logs, and simulation outputs.

## Documentation

- [docs/en/INSTALL.md](mdprep/docs/en/INSTALL.md) — **step-by-step install (new PC)**
- [docs/en/FIRST_RUN_CHECKLIST.md](mdprep/docs/en/FIRST_RUN_CHECKLIST.md) — printable checklist
- [docs/en/USAGE.md](mdprep/docs/en/USAGE.md) — menu & workflow
- [docs/tr/KULLANIM.md](mdprep/docs/tr/KULLANIM.md) — Turkish guide
- [KURULUM_YENI_PC.md](mdprep/KURULUM_YENI_PC.md) — Turkish install notes
- [PROJECT.md](mdprep/PROJECT.md) — architecture
- [ANALYSIS.md](mdprep/ANALYSIS.md) — analysis workflow

## Maintainers — build release zip

```bash
bash mdprep/make_release.sh 1.0.0
# → dist/gmxkit-1.0.0.zip
```
