# GmxKit

GROMACS protein–ligand MD toolkit: preparation, simulation queue, and analysis. Menu-driven via **`gmxkit`** on WSL/Linux.

**Default UI language: English.** Switch in the menu (Settings → 8) or:

```bash
gmxkit lang tr
gmxkit lang en
```

## Requirements

| You provide | GmxKit provides |
|-------------|-----------------|
| **GROMACS** (`gmx` on PATH) | Python venv (numpy, networkx) |
| **CHARMM36 + CGenFF** force field folder | Prep pipeline, queue, analysis |
| `protein.pdb`, `ligand.mol2` per project | MDP templates, checkpoints, logs |

GmxKit does **not** install GROMACS. You must have `gmx` available before running simulations.

Details: [Installation guide](mdprep/docs/en/INSTALL.md) · [First-run checklist](mdprep/docs/en/FIRST_RUN_CHECKLIST.md)

## Install once

```bash
git clone https://github.com/harunalcakan/gmxkit.git ~/opt/gmxkit
cd ~/opt/gmxkit
# add charmm36-*.ff/ here (once)
./gmxkit install
```

This installs Python dependencies and registers the **`gmxkit`** command in `~/.local/bin`.  
Ensure `~/.local/bin` is on your PATH (add to `~/.bashrc` if needed).

## Use from any project folder

```bash
mkdir ~/projects/ca1
cp protein.pdb ligand.mol2 ~/projects/ca1/
cd ~/projects/ca1
gmxkit
```

GmxKit detects `protein.pdb` / `ligand.mol2`, copies MDP templates, links the force field from the install folder, and writes logs to `.gmxkit/` in that folder. GROMACS outputs (`topol.top`, `*.gro`, `*.tpr`, …) appear in the project folder as you run prep.

**Windows:** open your folder in Explorer, then in WSL:

```bash
cd /mnt/c/Users/you/projects/ca1
gmxkit
```

## Menu (numbers only)

| # | After prep | Before prep |
|---|------------|---------------|
| **1** | Preparation (re-run steps) | Preparation (run all steps) |
| **2** | Simulation (EM → MD queue) | Settings |
| **3** | Analysis | — |
| **4** | Settings | — |
| **0** | Exit | Exit |

## CLI (optional)

```bash
gmxkit prep              # all prep steps
gmxkit prep protein      # one step (short name)
gmxkit stage ligand      # same
gmxkit protein           # shortcut for single step
gmxkit queue chain       # EM → NVT → NPT → MD
gmxkit analyze           # trajectory analysis
```

**Prep step codes:** `check` · `metal` · `protein` · `ligand` · `complex` · `solvate` · `index` · `scripts`  
Menu numbers **1–8** also work. Legacy `00`–`06` still accepted.

## Project layout

```
~/opt/gmxkit/              ← install once (scripts + force field)
~/projects/ca1/            ← each system
├── protein.pdb
├── ligand.mol2
├── topol.top, *.gro, …    ← GROMACS files (created during prep/sim)
└── .gmxkit/               ← logs, checkpoints, queue (not mixed between projects)
```

## Documentation

- [docs/en/INSTALL.md](mdprep/docs/en/INSTALL.md)
- [docs/en/FIRST_RUN_CHECKLIST.md](mdprep/docs/en/FIRST_RUN_CHECKLIST.md)
- [docs/en/USAGE.md](mdprep/docs/en/USAGE.md)
- [docs/tr/KULLANIM.md](mdprep/docs/tr/KULLANIM.md)

## Maintainers — release zip

```bash
bash mdprep/make_release.sh 1.0.0
```
