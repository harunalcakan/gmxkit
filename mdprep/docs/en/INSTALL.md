# GmxKit — Installation Guide (new computer)

Step-by-step setup on **WSL2 (Ubuntu)** or **Linux**. GmxKit does not run natively on Windows CMD/PowerShell.

---

## What you need before starting

| Item | Who installs | Notes |
|------|----------------|-------|
| WSL2 + Ubuntu (Windows users) | You | [Microsoft WSL guide](https://learn.microsoft.com/en-us/windows/wsl/install) |
| **GROMACS** (`gmx`) | You | GmxKit never installs GROMACS |
| **CHARMM36 + CGenFF** force field folder | You | Not included in GitHub / release zip |
| Python 3, perl | `./md install` | Optional `--with-apt` on fresh Ubuntu |
| Example inputs | Included | `protein.pdb`, `ligand.mol2`, `*.mdp` in the package |

---

## Option A — Download release zip (recommended for end users)

1. Open [GitHub Releases](https://github.com/harunalcakan/gmxkit/releases) and download the latest `gmxkit-*.zip`.
2. Unzip to a folder, e.g. `~/projects/gmxkit`.
3. Continue from [Step 3 — Force field](#step-3--force-field) below.

## Option B — Git clone (developers)

```bash
git clone https://github.com/harunalcakan/gmxkit.git
cd gmxkit
```

---

## Step 1 — WSL / Linux shell

Open **Ubuntu** (WSL) or a Linux terminal. All commands below run there.

```bash
cd /path/to/gmxkit    # folder containing ./md and mdprep/
chmod +x md mdprep/*.sh mdprep/lib/*.sh mdprep/stages/*.sh
```

---

## Step 2 — Install GROMACS

GmxKit calls `gmx` from your environment. Pick one method:

### Ubuntu / WSL (simple)

```bash
sudo apt update
sudo apt install -y gromacs
gmx --version
```

### HPC cluster

```bash
module load gromacs/2024    # name depends on your site
gmx --version
```

### Custom build

Set the full path in `mdprep/config.sh`:

```bash
GMX="/opt/gromacs/bin/gmx"
```

---

## Step 3 — Force field

Download a **CHARMM36m + CGenFF** force field bundle (folder name like `charmm36-feb2026_ljpme_cgenff-5.0.ff`).

Place the **entire `.ff` directory** in the project root (same level as `./md`):

```
gmxkit/
├── md
├── mdprep/
├── protein.pdb
├── ligand.mol2
├── *.mdp
└── charmm36-feb2026_ljpme_cgenff-5.0.ff/   ← here
```

Update `mdprep/config.sh` if your folder name differs:

```bash
FF_NAME="charmm36-feb2026_ljpme_cgenff-5.0"
FF_DIR="${FF_NAME}.ff"
```

---

## Step 4 — GmxKit dependencies

From the project root:

```bash
./md install              # Python venv (numpy, networkx)
./md install --with-apt   # optional: also apt python3 + perl (sudo)
```

This creates `mdprep/.venv` and marks install complete. **GROMACS is not installed here.**

---

## Step 5 — First-run check

```bash
./md install    # if not done
./md check      # or: ./md prep → stage 00
```

Fix anything marked **FAIL** (missing gmx, FF folder, input files).

Interactive menu:

```bash
./md lang en    # English UI (default)
./md            # main menu
```

Use the printable checklist: [FIRST_RUN_CHECKLIST.md](FIRST_RUN_CHECKLIST.md).

---

## Step 6 — Typical workflow

1. **Prep** — menu `[P]` or `./md prep` (stages 00–06)  
2. **CGenFF** — stage 02 pauses for manual `.str` download from the CGenFF web server  
3. **Queue** — `./md queue chain` (EM → NVT → NPT → MD in background)  
4. **Analysis** — `./md analyze` after MD finishes  

See [USAGE.md](USAGE.md) for menu details.

---

## Customizing for your system

Edit **`mdprep/config.sh`** (single source of truth):

| Setting | Purpose |
|---------|---------|
| `LIG_RESNAME` | Ligand residue name in mol2/top (example: `2Q38`) |
| `METAL_ENZYME` | `yes` for CA/Zn; `no` for generic protein–ligand |
| `PROD_NS` | Production MD length |
| `GMX` | Path to gmx binary |
| `MDLANG` | `en` or `tr` |

Profile example: `mdprep/profiles/ca2_6i0l_2q38.env` — source or copy values into `config.sh`.

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `./md: Permission denied` | `chmod +x md` |
| `gmx not found` | Install GROMACS; set `GMX=` in config.sh |
| `FF klasörü yok` | Add `charmm36-*.ff/` to project root |
| `$'\r': command not found` | Windows line endings — run `sed -i 's/\r$//' md mdprep/**/*.sh` |
| CGenFF fails | Run `./md install`; check `python3` + networkx in venv |
| Menu in wrong language | `./md lang en` or `./md lang tr` |

Logs: `mdprep/logs/`  
Install report: `mdprep/.state/install_report.txt`

---

## Create a release zip (maintainers)

```bash
bash mdprep/make_release.sh 1.0.0
# → dist/gmxkit-1.0.0.zip
```
