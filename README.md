# GROMACS CA + Ligand MD Pipeline

Protein–ligand (CA metalloenzim + Zn²⁺ + 2Q38) GROMACS hazırlık ve yerel MD kuyruğu. WSL veya Linux'ta menüden yönetilir.

## Gereksinimler

| Siz kurarsınız | `./md install` kurar |
|----------------|----------------------|
| **GROMACS** (`gmx`) | Python venv (numpy, networkx) |
| Force field klasörü (`charmm36-*.ff`) | `./md` launcher |
| `protein.pdb`, `ligand.mol2`, `*.mdp` | — |

Detay: [mdprep/KURULUM_YENI_PC.md](mdprep/KURULUM_YENI_PC.md)

## Hızlı başlangıç

```bash
# 1) Force field'i proje köküne koyun (charmm36-feb2026_ljpme_cgenff-5.0.ff)
# 2) GROMACS PATH'te olsun (config.sh → GMX="gmx")
./md install
./md
```

## Komutlar

| Komut | Açıklama |
|-------|----------|
| `./md` | Menü (J=kuyruk, S=simülasyon, P=hazırlık, L=analiz) |
| `./md prep` | Hazırlık aşamaları 00–06 |
| `./md queue chain` | EM → NVT → NPT → MD kuyruğu |
| `./md analyze` | PBC + RMSD/RMSF/Rg/SASA |
| `./md audit` | Hazırlık denetimi |
| `./md install` | Python bağımlılıkları (GROMACS kurmaz) |

## Dizin yapısı

```
./
├── md                 # launcher
├── mdprep/            # pipeline script'leri
├── protein.pdb
├── ligand.mol2
├── *.mdp
├── cgenff_*.py
└── charmm36-....ff/   # ayrı indirin (repo'da yok)
```

## Taşınabilir paket

```bash
bash mdprep/export_portable.sh /hedef/klasor
```

`.venv`, log ve simülasyon çıktıları hariç kopyalar.

## Dokümantasyon

- [KULLANIM.md](mdprep/KULLANIM.md) — menü ve akış
- [PROJECT.md](mdprep/PROJECT.md) — mimari ve kararlar
- [ANALYSIS.md](mdprep/ANALYSIS.md) — analiz tarifi
