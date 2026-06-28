# GmxKit — First-run checklist

Print or keep this open while setting up a new machine.

---

## A. Environment

- [ ] **WSL2 Ubuntu** or Linux terminal (not Windows CMD alone)
- [ ] Project folder contains `./md` and `mdprep/`
- [ ] `chmod +x md` (and scripts if needed)

## B. GROMACS

- [ ] `gmx --version` works in the same shell you will use for `./md`
- [ ] If not on PATH: `GMX="/full/path/to/gmx"` set in `mdprep/config.sh`

## C. Force field & inputs

- [ ] `charmm36-*.ff/` folder in **project root** (next to `./md`)
- [ ] `FF_NAME` in `config.sh` matches your folder (without `.ff` suffix)
- [ ] `protein.pdb` present
- [ ] `ligand.mol2` present
- [ ] `em.mdp`, `nvt.mdp`, `npt.mdp`, `md.mdp` present

## D. GmxKit install

- [ ] `./md install` completed without fatal errors
- [ ] `mdprep/.venv/` exists
- [ ] `mdprep/.state/.installed` exists
- [ ] Optional: `./md install --with-apt` on fresh Ubuntu (python3, perl)

## E. Validation

- [ ] `./md check` or prep stage **00** — all checks **OK**
- [ ] `./md lang en` (or `tr`) — language as preferred
- [ ] `./md` opens main menu without errors

## F. Before production MD

- [ ] Prep stages **00–06** complete (menu shows prep 8/8 ✓)
- [ ] `./md audit` — no critical failures
- [ ] Stage **02**: CGenFF `.str` downloaded manually when prompted
- [ ] `em.tpr` exists (stage 04)
- [ ] `./md queue submit em` or `./md queue chain` — job starts, log in `mdprep/logs/queue/`

## G. After MD

- [ ] `./md analyze` — report in `mdprep/logs/analysis/ANALYSIS_REPORT.txt`

---

**Quick commands**

```bash
./md install
./md check
./md
./md queue chain
./md analyze
```

Full guide: [INSTALL.md](INSTALL.md)
