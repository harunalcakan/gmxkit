# GmxKit — Installation Guide

Step-by-step setup on **WSL2 (Ubuntu)** or **Linux**. GmxKit does not run natively in Windows CMD/PowerShell.

---

## What you need

| Item | Notes |
|------|--------|
| WSL2 + Ubuntu (Windows users) | [Microsoft WSL guide](https://learn.microsoft.com/en-us/windows/wsl/install) |
| **GROMACS** (`gmx` on PATH) | **Required.** Install yourself — GmxKit never installs GROMACS |
| **CHARMM36 + CGenFF** force field | **Included** in repo / release zip |
| Python 3, perl | Installed by `gmxkit install` |

---

## 1 — Get GmxKit

**Release zip:** [GitHub Releases](https://github.com/harunalcakan/gmxkit/releases)

**Or clone:**

```bash
git clone https://github.com/harunalcakan/gmxkit.git ~/opt/gmxkit
cd ~/opt/gmxkit
chmod +x gmxkit md mdprep/*.sh mdprep/lib/*.sh mdprep/stages/*.sh
```

---

## 2 — Force field

**Included in the repository** — after clone or unzip you should already have:

```
~/opt/gmxkit/charmm36-feb2026_ljpme_cgenff-5.0.ff/
```

If the folder name differs from your `mdprep/config.sh` → `FF_NAME` / `FF_DIR`, rename the folder or edit config.

See [FORCE_FIELD.md](../FORCE_FIELD.md) for attribution notes.

---

## 3 — Install GmxKit (once)

```bash
cd ~/opt/gmxkit
gmxkit install
```

This creates the Python venv, registers **`~/.local/bin/gmxkit`**, and runs a **software check** (Python, CGenFF, bundled force field). No `protein.pdb` or `ligand.mol2` is required in the install folder.

If `gmxkit` is not found, add to `~/.bashrc`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Verify GROMACS separately:

```bash
gmx --version
```

---

## 4 — Run a project

Create a folder, add inputs, run GmxKit **from that folder**:

```bash
mkdir ~/projects/my-system
cp protein.pdb ligand.mol2 ~/projects/my-system/
# optional demo: cp examples/metalloenzyme-sample/{protein.pdb,ligand.mol2} ~/projects/my-system/
cd ~/projects/my-system
gmxkit
```

No `init` required if `protein.pdb` and `ligand.mol2` are present — templates and `.gmxkit/` are created automatically.

Optional scaffold:

```bash
gmxkit init ~/projects/my-system
```

**Windows folder via WSL:**

```bash
cd /mnt/c/Users/you/Documents/ca1
gmxkit
```

---

## 5 — Typical workflow

1. **1 — Preparation** — run all prep steps (topology → solvation → index)
2. **CGenFF pause** — stage 02 stops for manual `.str` download from the CGenFF web server
3. **2 — Simulation** → **1 — Full chain** — EM → NVT → NPT → MD in the background queue
4. **3 — Analysis** — after MD finishes

See [FIRST_RUN_CHECKLIST.md](FIRST_RUN_CHECKLIST.md) and [USAGE.md](USAGE.md).

---

## Customizing

Edit **`mdprep/config.sh`** in the install folder, or create **`gmxkit.env`** in the project folder:

| Setting | Purpose |
|---------|---------|
| `LIG_RESNAME` | Ligand residue name in mol2/top |
| `METAL_ENZYME` | `yes` for metalloenzymes |
| `PROD_NS` | Production MD length |
| `GMX` | Path to gmx if not on PATH |
| `MDLANG` | `en` or `tr` |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `gmxkit: command not found` | `export PATH="$HOME/.local/bin:$PATH"` |
| `gmx not found` | Install GROMACS; set `GMX=` in config.sh |
| Force field missing | Add `charmm36-*.ff/` to `~/opt/gmxkit/` |
| `$'\r': command not found` | Windows line endings — `sed -i 's/\r$//' gmxkit mdprep/**/*.sh` |

Logs: `<project>/.gmxkit/logs/`  
Install report: `~/opt/gmxkit/.gmxkit/state/install_report.txt`

---

## Uninstall

Remove GmxKit-installed components (not GROMACS, force field, or project data):

```bash
cd ~/opt/gmxkit
gmxkit uninstall              # venv + ~/.local/bin/gmxkit + install state
gmxkit uninstall -y           # no prompt
gmxkit uninstall --purge-home # also delete entire ~/opt/gmxkit folder
```
