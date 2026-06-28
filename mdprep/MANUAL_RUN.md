# Manuel Akış Notları

> Script kalibrasyonu için kritik. Pipeline (`mdprep/`) ile eski script seti arasındaki eşleme aşağıda.
>
> Sistem: `native_ca1_test_cursor`
> Tarih başlangıç: 2026-06-24

---

## Eski script → mdprep eşlemesi

| Eski dosya | Eski adım | mdprep aşaması | Config / çıktı |
|------------|-----------|----------------|----------------|
| `script.py` §1 | `pdb2gmx` → `protein.gro` | **01_protein** | `processed.gro`, `topol.top`, `posre.itp` |
| `script.py` §2 | `sort_mol2_bonds.pl` → `ligand_fix.mol2` | **02_ligand** | `ligand_sorted.mol2` |
| `script.py` §3 | CGenFF bekle → `ligand_fix.str` | **02_ligand** (manuel kapı) | `lig.str` |
| `script.py` §4–5 | cgenff + `editconf` | **02_ligand** | `lig.itp`, `lig.prm`, `lig_ini.pdb`, `ligand.gro` |
| `script.py` §5–6 | `merge_protein_ligand` + `modify_topol_file` | **03_complex** | `complex.gro`, `topol.top` cerrahisi |
| `script.py` §7–9 | kutu + solvasyon + ions grompp | **04_solvate_ions** | `newbox.gro`, `solv.gro`, `ions.tpr` |
| `step10.py` | `genion` | **04_solvate_ions** | `solv_ions.gro` |
| `step11.py` | EM grompp + mdrun | **04_solvate_ions** | `em.tpr`, `em.gro` |
| `step12.py` | ligand `make_ndx` + `genrestr` | **05_index_posre** | `posre_lig.itp` |
| `step13/14.py` | `make_ndx` `1 \| 13` | **05_index_posre** | `index.ndx` (parse ile) |
| `step15.py` | NVT + NPT | **06_truba_pack** | slurm self-contained |

**Eski scriptte kullanılmayan / değişen:**
- FF: `charmm36-jul2021` → `charmm36-feb2026_ljpme_cgenff-5.0`
- Molekül adı: `LIG1` → `LIG`
- Kutu: `cubic` → `dodecahedron`
- pdb2gmx: interaktif `printf "1\n1\n"` → `-ff -water -inter no -ter no`

---

## ADIM 00: Ortam kontrolü

**Kurulum (yeni bilgisayar):**
```bash
./mdprep/run.sh setup              # conda: py2.7 + networkx 1.11 (cgenff)
./mdprep/run.sh setup --system     # + perl, gromacs
./mdprep/run.sh check
```

**cgenff komutu (legacy):**
```bash
conda run -n mdprep-cgenff python cgenff_charmm2gmx_py2.py LIG ligand_sorted.mol2 lig.str charmm36-feb2026_ljpme_cgenff-5.0.ff
```

**Not:** Varsayılan backend `legacy` (py2.7 + nx 1.11). Py3 alternatif: `CGENFF_BACKEND=py3` + `setup --py3`.

**Komut(lar):**
```bash
./mdprep/run.sh check
```

**Girdi dosyaları:**
- `protein.pdb`, `ligand.mol2`, `.ff`, mdp, slurm dosyaları

**Üretilen dosyalar:**
- yok (sadece doğrulama)
- checkpoint: `mdprep/.state/00_check_env.done`

**Doğrulama:**
- gmx, perl, python3, numpy, networkx 2.x, FF klasörü, su modeli tip3p

---

## ADIM 01: Protein topolojisi (pdb2gmx)

**Komut(lar):**
```bash
./mdprep/run.sh stage 01
# veya doğrudan:
gmx pdb2gmx -f protein.pdb -o processed.gro -p topol.top -i posre.itp \
  -ff charmm36-feb2026_ljpme_cgenff-5.0 -water tip3p -ignh -missing -inter no -ter no
```

**Girdi dosyaları:**
- `protein.pdb`

**Üretilen dosyalar:**
- `processed.gro`, `topol.top`, `posre.itp`

**İnteraktif seçimler:**
- yok (config'ten non-interaktif)

**Eski script farkı:**
- Eski: `protein.gro`, interaktif FF seçimi
- Yeni: `processed.gro`, `-ff`/`-water` config'ten

**Doğrulama (WSL test 2026-06-24):**
- `processed.gro` 2. satır: **3959** atom
- `[ molecules ]`: `Protein_chain_A 1`
- **Not:** `lipid.rtp` bozuksa pdb2gmx fail olur; FF paketini yeniden indir

---

## ADIM 02: Ligand topolojisi

**Komut(lar):**
```bash
./mdprep/run.sh stage 02
```

**Adım adım (pipeline içi):**
```bash
# 1) mol2 bond sıralama
perl sort_mol2_bonds.pl ligand.mol2 ligand_sorted.mol2

# 2) MANUEL — CGenFF
#    https://cgenff.umaryland.edu/initguess/
#    Yükle: ligand_sorted.mol2
#    RESI: LIG  |  "Include parameters already in CGenFF" SEÇME
#    İndir → lig.str

# 3) cgenff dönüştürme (legacy — py2.7 + networkx 1.11)
conda run -n mdprep-cgenff python cgenff_charmm2gmx_py2.py LIG ligand_sorted.mol2 lig.str charmm36-feb2026_ljpme_cgenff-5.0.ff

# 4) gro
gmx editconf -f lig_ini.pdb -o ligand.gro
```

**Girdi dosyaları:**
- `ligand.mol2`
- `lig.str` (CGenFF'ten manuel)

**Üretilen dosyalar:**
- `ligand_sorted.mol2`
- `lig.itp`, `lig.prm`, `lig.top`, `lig_ini.pdb`
- `ligand.gro`

**CGenFF:**
- .str dosya adı: `lig.str`
- RESI satırı: `LIG`
- Sunucu: https://cgenff.umaryland.edu/initguess/

**Eski script farkı:**
- Eski: `ligand_fix.mol2`, `ligand_fix.str`, cgenff script çağrısı yok (eksik adım)
- Yeni: `ligand_sorted.mol2`, `lig.str`, tam cgenff + editconf

**Doğrulama:**
- `lig.str` içinde `RESI LIG`
- `lig.itp`, `lig.prm`, `lig_ini.pdb` dolu
- `ligand.gro` atom sayısı mol2 ile tutarlı

---

## ADIM 03: Kompleks oluşturma

**Komut(lar):**
```bash
./mdprep/run.sh stage 03
# veya:
python3 mdprep/lib/gro_tools.py processed.gro ligand.gro complex.gro
python3 mdprep/lib/top_tools.py add-ligand topol.top topol.top \
  --prm lig.prm --itp lig.itp --resname LIG
```

**Kaynak:** `script.py` → `merge_protein_ligand()` + `modify_topol_file()`

**complex.gro:**
- protein atom sayısı: (processed.gro 2. satır)
- ligand atom sayısı: (ligand.gro 2. satır)
- toplam (2. satır): protein + ligand

**topol.top kritik satırlar:**
- `#include "lig.prm"` (forcefield.itp sonrası)
- `#include "lig.itp"` (posre.itp / #endif sonrası)
- `[ molecules ]` → `LIG 1`

---

## ADIM 04: Kutu + solvasyon + iyonlar + EM

**Komut(lar):**
```bash
./mdprep/run.sh stage 04
```

**Adım adım:**
```bash
gmx editconf -f complex.gro -o newbox.gro -bt dodecahedron -d 1.0
gmx solvate -cp newbox.gro -cs spc216.gro -p topol.top -o solv.gro
gmx grompp -f ions.mdp -c solv.gro -p topol.top -o ions.tpr -maxwarn 1
# SOL grubu parse: python3 mdprep/lib/ndx_tools.py sol-group --gmx gmx solv.gro
gmx genion -s ions.tpr -o solv_ions.gro -p topol.top -pname NA -nname CL -neutral
gmx grompp -f em.mdp -c solv_ions.gro -p topol.top -o em.tpr -maxwarn 1
gmx mdrun -v -deffnm em   # LOCAL_EM_RUN=yes ise
```

**Na/Cl düzeltmesi gerekli miydi?**
- EM grompp fail → `python3 mdprep/lib/top_tools.py fix-ions topol.top solv_ions.gro`

---

## ADIM 05: Index + posre

**Komut(lar):**
```bash
./mdprep/run.sh stage 05
```

**Adım adım:**
```bash
python3 mdprep/lib/ndx_tools.py ligand-heavy --gmx gmx ligand.gro index_lig.ndx
gmx genrestr -f ligand.gro -n index_lig.ndx -o posre_lig.itp -fc 1000 1000 1000
python3 mdprep/lib/top_tools.py add-posre topol.top topol.top --itp lig.itp --posre posre_lig.itp
python3 mdprep/lib/ndx_tools.py complex-index --gmx gmx em.gro index.ndx \
  --lig-resname LIG --grp-pl Protein_LIG --grp-wi Water_and_Ions
```

**Not:** Eski `step13.py` sabit `1 | 13` kullanıyordu — pipeline grup numaralarını parse eder.

---

## ADIM 06: TRUBA paketi

**Komut(lar):**
```bash
./mdprep/run.sh stage 06
```

**Üretilen:**
- `em.slurm`, `nvt.slurm`, `npt.slurm`, `md.slurm` (grompp + mdrun self-contained)
- `md.mdp` nsteps güncellenir (`PROD_NS` × 500000)
- `mdprep/ANALYSIS.md`

**TRUBA submit:**
```bash
sbatch em.slurm
sbatch nvt.slurm
sbatch npt.slurm
sbatch md.slurm
```

**deffnm:** `em`, `nvt`, `npt`, `md_out`

---

## ADIM 07: Production MD (TRUBA)

**md.mdp ayarları:**
- PROD_NS / nsteps: 300 ns (config)

---

## ADIM 08: Analiz

**Komut(lar):**
```bash

```
