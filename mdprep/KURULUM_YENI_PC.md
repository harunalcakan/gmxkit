# GmxKit — Dağıtım ve kurulum rehberi

**English (detailed):** [docs/en/INSTALL.md](docs/en/INSTALL.md) · [FIRST_RUN_CHECKLIST.md](docs/en/FIRST_RUN_CHECKLIST.md)

**Release zip:** [GitHub Releases](https://github.com/harunalcakan/gmxkit/releases)

---

| Kurulur (script) | Kurulmaz (siz) |
|------------------|----------------|
| pip: numpy, networkx (cgenff) | **GROMACS (`gmx`)** |
| isteğe `--with-apt`: python3, perl | Force field klasörü |
| `./md` launcher | protein.pdb, ligand.mol2, *.mdp |

```bash
./md install              # yalnızca pip venv
./md install --with-apt   # + python3/perl (sudo), gmx yok
```

## GROMACS

Script **asla** `apt install gromacs` yapmaz. Kendi kurulumunuz:

- Modül: `module load gromacs/2024`
- Derleme: `/opt/gromacs/bin/gmx`
- WSL apt (elle): `sudo apt install gromacs` — sizin kararınız

`mdprep/config.sh`:

```bash
GMX="gmx"                          # PATH'te
# GMX="/opt/gromacs2026/bin/gmx"   # tam yol
```

## Proje paketi (yayınlarken)

```
proje/
├── mdprep/          export_portable ile (.venv hariç)
├── protein.pdb, ligand.mol2, *.mdp
├── charmm36-....ff/
└── cgenff_*.py, sort_mol2_bonds.pl
```

Kullanıcı: GROMACS kur → proje zip aç → `./md install` → `./md`

## Yeni bilgisayar

```bash
# 1) GROMACS — siz (script karışmaz)
# 2) Proje klasörü
./md install
./md
```
