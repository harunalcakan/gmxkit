# GmxKit

Protein–ligand MD with GROMACS. Menu-driven tool for **prep → simulation → analysis**.

Runs on **WSL / Linux** (not Windows CMD). You need **GROMACS** (`gmx`) installed yourself — everything else is in this repo (including the force field).

---

## Install (once)

```bash
git clone https://github.com/harunalcakan/gmxkit.git ~/opt/gmxkit
cd ~/opt/gmxkit
chmod +x gmxkit md
./gmxkit install
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
gmxkit check
```

`gmxkit install` checks **software only** (Python, CGenFF, bundled force field). It does not require `protein.pdb` or `ligand.mol2` in the install folder.

Example inputs for testing: `examples/metalloenzyme-sample/` (optional).

---

## Run a project

Put **`protein.pdb`** and **`ligand.mol2`** in a folder. Run GmxKit from that folder:

```bash
mkdir ~/projects/my-system
cp protein.pdb ligand.mol2 ~/projects/my-system/
cd ~/projects/my-system
gmxkit
```

From a Windows folder in WSL:

```bash
cd "/mnt/c/Users/you/Desktop/my-system"
gmxkit
```

**Menu**

| Key | Action |
|-----|--------|
| **1** | Preparation (topology, solvation, …) |
| **2** | Simulation (EM → NVT → NPT → MD) — after prep |
| **3** | Analysis |
| **4** | Settings |
| **0** | Exit |

Inside **Preparation**: press **1** to run all steps, or pick a step number (**2** = check, **4** = protein, **5** = ligand, …).

Ligand step pauses for **CGenFF** — upload `ligand_sorted.mol2`, save `.str` to the project folder, continue.

---

## Useful commands

```bash
gmxkit check          # environment test
gmxkit prep           # all prep steps
gmxkit queue chain    # EM → NVT → NPT → MD
gmxkit fresh -y       # reset project folder (keeps input files)
gmxkit lang tr        # Turkish menu
gmxkit uninstall      # remove Python venv + global command
```

---

## Folders

```
~/opt/gmxkit/                 ← program + force field (install once)
~/projects/my-system/         ← your simulation
  protein.pdb  ligand.mol2    ← you add these
  topol.top  *.gro  …         ← GROMACS creates these
  .gmxkit/                    ← logs & checkpoints
```

---

## More help

- [Install guide](mdprep/docs/en/INSTALL.md)
- [First-run checklist](mdprep/docs/en/FIRST_RUN_CHECKLIST.md)
- [Turkish guide](mdprep/docs/tr/KULLANIM.md)
