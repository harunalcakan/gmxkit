# GmxKit

GROMACS protein–ligand MD prep, simulation queue, and analysis.  
Runs on **WSL / Linux**. You only install **GROMACS** yourself — force field and GmxKit scripts are included.

---

## Install (once)

```bash
git clone https://github.com/harunalcakan/gmxkit.git ~/opt/gmxkit
cd ~/opt/gmxkit
chmod +x gmxkit md
./gmxkit install
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc
gmx --version    # must work before prep
gmxkit check
```

---

## Run a project

Put **`protein.pdb`** and **`ligand.mol2`** in a folder, then:

```bash
cd /path/to/my-project
gmxkit
```

GmxKit copies MDP templates, links the force field, and writes logs to `.gmxkit/` in that folder.  
GROMACS files (`topol.top`, `*.gro`, …) appear in the project folder as you run prep.

**Windows folder (WSL):**

```bash
cd "/mnt/c/Users/you/projects/ca1"
gmxkit
```

---

## Menu

| Key | Meaning |
|-----|---------|
| **1** | Preparation (topology → solvation → index) |
| **2** | Simulation (EM → NVT → NPT → MD queue) — after prep |
| **3** | Analysis |
| **4** | Settings |
| **0** | Exit |

Inside **Preparation**: `1` = run all steps · `2`–`9` = one step · or type a code: `check`, `protein`, `ligand`, …

**Metalloenzyme (e.g. CA + Zn):** first run asks, or set in `gmxkit.env`:

```bash
METAL_ENZYME="yes"
METAL_HSD_RESIDUES="94 96 119"
LIG_RESNAME="2Q38"
```

**CGenFF:** ligand step pauses — upload `ligand_sorted.mol2` to the CGenFF site, save `.str` in the project folder, continue.

---

## Useful commands

```bash
gmxkit check              # environment check
gmxkit prep               # all prep steps
gmxkit protein            # one prep step
gmxkit queue chain        # EM → NVT → NPT → MD
gmxkit fresh -y           # reset project (keep inputs only)
gmxkit uninstall          # remove GmxKit venv + global command
gmxkit lang tr            # Turkish UI
```

---

## More help

- [Install guide](mdprep/docs/en/INSTALL.md)
- [First-run checklist](mdprep/docs/en/FIRST_RUN_CHECKLIST.md)
- [Turkish guide](mdprep/docs/tr/KULLANIM.md)

**Repo:** [github.com/harunalcakan/gmxkit](https://github.com/harunalcakan/gmxkit)
