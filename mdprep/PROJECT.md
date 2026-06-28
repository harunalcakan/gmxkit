# GROMACS Protein–Ligand MD Hazırlık Pipeline'ı

> **Amaç:** `native_ca1_test_cursor` (ve benzeri) klasörlerinde protein–ligand kompleksleri için GROMACS MD hazırlığını tekrarlanabilir, doğrulanabilir ve checkpoint'li bir script setiyle otomatikleştirmek.
>
> **Durum (2026-06-24):** Tüm aşamalar (00–06) yazıldı. Gerçek veriyle test/kalibrasyon bekliyor.
>
> **Bu dosya:** Sohbet geçmişi olmadan başka bilgisayarda devam etmek için tek referans belgesidir.

---

## 1. Proje konumu

**Ana çalışma dizini (WORKDIR):**

```
D:\JOBS\02_PROJELER_VE_VERİLER\GDP01_FBG-2025-4390_KANSER\01_DATA\20260624_md_inputs\ca1_complexes\native_ca1_test_cursor
```

**WSL yolu (örnek):**

```
/mnt/d/JOBS/02_PROJELER_VE_VERİLER/GDP01_FBG-2025-4390_KANSER/01_DATA/20260624_md_inputs/ca1_complexes/native_ca1_test_cursor
```

**Pipeline dizini:**

```
native_ca1_test_cursor/mdprep/
```

Pipeline **in-place** çalışır: girdi dosyaları (`protein.pdb`, `ligand.mol2`, `.ff`, `.mdp`, `.slurm`) WORKDIR'de kalır; `mdprep/` altında script'ler ve log/checkpoint tutulur.

---

## 2. Ne yapıyoruz?

GROMACS ile protein–ligand moleküler dinamik simülasyonu hazırlığı. Referans: sunum *"GROMACS ile Moleküler Dinamik Simülasyonu (Protein & Ligand)"* — ancak script tutorial'daki eski dosya adlarını (`jz4`, `charmm36-JUL2021`, Python 2.7) **kullanmaz**; gerçek dosyalara göre kalibre edilir.

### Pipeline aşamaları (hedef)

| # | Aşama | Açıklama | Durum |
|---|-------|----------|-------|
| 00 | `check_env` | Ortam + girdi doğrulaması | **Hazır** |
| 01 | `protein` | `pdb2gmx` ile protein topolojisi | **Hazır** |
| 02 | `ligand` | mol2 düzenleme, CGenFF, cgenff script, `ligand.gro` | **Hazır** |
| 03 | `complex` | `complex.gro` montajı + `topol.top` cerrahisi | **Hazır** |
| 04 | `solvate_ions` | kutu, solvasyon, iyon ekleme, EM hazırlığı | **Hazır** |
| 05 | `index_posre` | `index.ndx` (Protein_LIG, Water_and_Ions), ligand posre | **Hazır** |
| 06 | `truba_pack` | self-contained slurm (grompp+mdrun), analiz komutları | **Hazır** |

---

## 3. Mimari kararlar (değişmemeli)

| Konu | Karar |
|------|-------|
| Dil | **Modüler bash** + Python yardımcıları (`gro_tools.py`, `top_tools.py`, `ndx_tools.py`) |
| Config | Tek kaynak: `mdprep/config.sh`. Hiçbir stage script'i dosya adı gömmez |
| Çalışma modu | In-place (mevcut veri klasöründe) |
| CGenFF `.str` | **Manuel web kapısı** — script durur, kullanıcı `.str` üretir, script doğrular ve devam eder |
| Batch | Önce **tek kompleks** sağlam; sonra çoklu komplekse genişlet |
| TRUBA slurm | **Self-contained**: her slurm dosyasında `grompp` + `mdrun` birlikte |
| Production MD | `md.mdp` kanonik; süre `config.sh` → `PROD_NS` ile ayarlanır |
| `deffnm` | `em`, `nvt`, `npt`, **`md_out`** (mevcut `md.slurm` ile uyumlu) |
| Checkpoint | Her aşama `.state/<asama>.done` yazar; `FORCE=1` ile zorlanır |
| Dry-run | `DRY_RUN=yes ./run.sh` komutları çalıştırmadan loglar |

---

## 4. Mevcut dosya yapısı

### Girdi dosyaları (WORKDIR — değişmez kabul edilir)

```
native_ca1_test_cursor/
├── protein.pdb                          # temiz (HETATM/HOH yok, ~3960 ATOM)
├── ligand.mol2                          # molekül adı: LIG, 34 atom
├── charmm36-feb2026_ljpme_cgenff-5.0.ff/
├── cgenff_charmm2gmx_py3_nx2.py         # Python 3 + networkx 2.x
├── sort_mol2_bonds.pl
├── em.mdp, ions.mdp, nvt.mdp, npt.mdp, md.mdp, md_200ns.mdp
├── em.slurm, nvt.slurm, npt.slurm, md.slurm
└── mdprep/                              # pipeline (aşağıda)
```

### Pipeline dosyaları (mdprep/)

```
mdprep/
├── PROJECT.md          ← bu dosya
├── config.sh           ← tüm parametreler
├── run.sh              ← orkestratör
├── lib/
│   ├── common.sh
│   ├── gro_tools.py
│   ├── top_tools.py
│   └── ndx_tools.py
├── stages/
│   ├── 00_check_env.sh
│   ├── 01_protein.sh
│   ├── 02_ligand.sh
│   ├── 03_complex.sh
│   ├── 04_solvate_ions.sh
│   ├── 05_index_posre.sh
│   └── 06_truba_pack.sh
├── requirements.txt    ← pip bağımlılıkları (numpy, networkx==2.3)
├── environment.yml     ← conda alternatifi
├── setup_env.sh        ← kurulum script'i
├── .venv/              ← setup sonrası (gitignore)
├── logs/               ← çalışınca oluşur
├── backups/            ← in-place düzenleme öncesi yedekler
└── .state/             ← checkpoint dosyaları (*.done)
```

---

## 5. config.sh özeti (kritik değerler)

| Parametre | Değer | Not |
|-----------|-------|-----|
| `GMX` | `gmx` | Yerel WSL; TRUBA'da `gmx_mpi` (slurm içinde) |
| `FF_NAME` | `charmm36-feb2026_ljpme_cgenff-5.0` | `pdb2gmx -ff` |
| `WATER_MODEL` | `tip3p` | CHARMM-modified TIP3P |
| `LIG_RESNAME` | `LIG` | mol2 ve .str RESI ile aynı olmalı |
| `LIG_LOWER` | `lig` | cgenff çıktı öneki: `lig.itp`, `lig.prm`, `lig_ini.pdb` |
| `LIG_STR` | `lig.str` | CGenFF'ten manuel indirilir |
| `LIGAND_MOL2_SORTED` | `ligand_sorted.mol2` | sort_mol2_bonds.pl çıktısı |
| `LIGAND_GRO` | `ligand.gro` | editconf `-o` |
| `CGENFF_BACKEND` | `legacy` | py2.7+nx1.11 (varsayılan) veya `py3` |
| `CGENFF_SCRIPT_LEGACY` | `cgenff_charmm2gmx_py2.py` | Python 2.7 + networkx 1.11 |
| `CGENFF_SCRIPT_PY3` | `cgenff_charmm2gmx_py3_nx2.py` | alternatif |
| `CGENFF_CONDA_ENV` | `mdprep-cgenff` | legacy kurulum conda env |
| `BOX_TYPE` | `dodecahedron` | `editconf -bt` |
| `BOX_DIST` | `1.0` nm | |
| `WATER_GRO` | `spc216.gro` | TIP3P için standart |
| `GRP_PROTEIN_LIG` | `Protein_LIG` | nvt/npt/md.mdp `tc-grps` ile uyumlu |
| `GRP_WATER_IONS` | `Water_and_Ions` | |
| `PROD_MDP` | `md.mdp` | |
| `PROD_DEFFNM` | `md_out` | md.slurm ile uyumlu |
| `PROD_NS` | `300` | nsteps = ns × 500000 (dt=0.002) |
| `GROMPP_MAXWARN` | `1` | em.slurm ile tutarlı |
| `PROTEIN_GRO` | `processed.gro` | pdb2gmx `-o` |
| `PROTEIN_TOP` | `topol.top` | pdb2gmx `-p` |
| `PROTEIN_POSRE` | `posre.itp` | pdb2gmx `-i` |
| `PDB2GMX_*` | `-ignh -missing -inter no -ter no` | non-interaktif pdb2gmx |

---

## 6. Bilinen "landmine"lar (script bunlara özel dikkat etmeli)

1. **Tutorial adları kullanılmamalı** — `jz4.gro` → `ligand.gro` / `lig.gro`; grup no `1 | 13` sabit değil, `make_ndx` çıktısından parse edilmeli.

2. **Index grup isimleri** — `nvt.mdp`, `npt.mdp`, `md.mdp` → `tc-grps = Protein_LIG Water_and_Ions`. `md_200ns.mdp` eski stil (`Protein Non-Protein`) — kanonik değil.

3. **cgenff çıktıları küçük harf** — `LIG` verilirse `lig.itp`, `lig.prm`, `lig_ini.pdb` üretilir.

4. **`topol.top` cerrahisi** — satır numarasıyla sed yapılmaz; anchor desenine göre `#include lig.itp`, `#include lig.prm`, `#ifdef POSRES` + `posre_lig.itp`, `[ molecules ]` altına `LIG 1`.

5. **`complex.gro`** — 2. satır atom sayısı = protein + ligand; son satır kutu vektörü korunmalı. Python ile byte-hassas montaj planlandı.

6. **Na/Cl düzeltmesi** — EM'de sodyum iyonu hatası alınırsa `topol.top` ve `solv_ions.gro` içindeki Na tanımları düzeltilmeli (koşullu adım).

7. **Mevcut slurm dosyaları** — `nvt.slurm`, `npt.slurm`, `md.slurm` sadece `mdrun` çalıştırıyor; `grompp` yok. Aşama 6'da self-contained hale getirilecek.

8. **CGenFF manuel** — https://cgenff.umaryland.edu/initguess/ (ücretsiz üyelik). `.str` dosyası script tarafından üretilemez.

9. **CRLF uyarısı** — Windows'tan düzenlenen `.sh` dosyaları LF olmalı: `sed -i 's/\r$//' mdprep/**/*.sh`

---

## 7. Hızlı başlangıç (yeni bilgisayarda)

### 7.1 Gereksinimler

| Bileşen | Sürüm / not |
|---------|-------------|
| **cgenff (varsayılan)** | Python **2.7** + networkx **1.11** (`cgenff_charmm2gmx_py2.py`, conda) |
| Pipeline yardımcıları | Python **3** (gro/top/ndx) |
| GROMACS | `gmx` PATH'te |
| Perl | `sort_mol2_bonds.pl` |

> Py3 alternatif: `CGENFF_BACKEND="py3"` + `./run.sh setup --py3`

### 7.2 İlk kurulum

```bash
cd "/mnt/d/JOBS/.../native_ca1_test_cursor"

./mdprep/run.sh setup          # conda: py2.7 + networkx 1.11
./mdprep/run.sh setup --system # + perl, gromacs (isteğe bağlı)
./mdprep/run.sh check
```

### 7.3 run.sh komutları

```bash
./mdprep/run.sh setup          # legacy cgenff ortamı (conda)
./mdprep/run.sh setup --legacy # aynı
./mdprep/run.sh setup --py3    # alternatif py3 cgenff
./mdprep/run.sh setup --system # + apt paketleri
./mdprep/run.sh check          # ortam kontrolü
./mdprep/run.sh list           # aşama durumları
./mdprep/run.sh all            # tanımlı tüm aşamalar (şu an sadece 00)
./mdprep/run.sh stage 01       # tek aşama (yazıldığında)
./mdprep/run.sh reset          # checkpoint temizle (dosyalara dokunmaz)

DRY_RUN=yes ./mdprep/run.sh check    # komut çalıştırmadan dene
FORCE=1 ./mdprep/run.sh stage 03     # tamamlanmış aşamayı zorla tekrarla
```

---

## 8. Cursor / AI ile devam etmek

Yeni sohbette şunu yapıştır:

```
Proje: native_ca1_test_cursor altında GROMACS protein-ligand MD prep pipeline.
mdprep/PROJECT.md dosyasını oku ve oradan devam et.
Şu an Aşama 0 hazır; Aşama 1 (protein topolojisi) yazılacak.
```

Manuel akış notların varsa `mdprep/MANUAL_RUN.md` dosyasına ekle (şablon aşağıda).

---

## 9. Manuel akış notları şablonu

Manuel çalıştırma yapıyorsan her adımı bu formatta `mdprep/MANUAL_RUN.md` dosyasına kaydet. Script kalibrasyonu için kritik.

```markdown
## ADIM: [kısa ad, örn. pdb2gmx]

**Komut(lar):**
```bash
gmx pdb2gmx -f protein.pdb -o processed.gro -ff ... -water ...
```

**Girdi dosyaları:**
- protein.pdb

**Üretilen dosyalar:**
- processed.gro, topol.top, posre.itp

**İnteraktif seçimler:**
- force field: ...
- water model: ...

**Manuel düzenleme:**
- (dosya, ne değişti, önce/sonra)

**Hata/uyarı:**
- ...

**Çözüm:**
- ...

**Doğrulama:**
- (nasıl anladın ki adım doğru?)
```

### Özellikle kaydedilmesi gerekenler

- [ ] `pdb2gmx` tam komutu ve seçilen ff/water
- [ ] CGenFF `.str` dosya adı ve RESI satırı
- [ ] `cgenff_charmm2gmx_py3_nx2.py` tam komutu ve üretilen dosyalar
- [ ] `topol.top` — `#include` satırları ve `[ molecules ]` bölümü (kritik satırlar)
- [ ] `complex.gro` — atom sayısı satırı ve ligand ekleme detayı
- [ ] `make_ndx` çıktısındaki **grup listesi** ve birleştirme komutları
- [ ] `genion` — seçilen grup no/adı
- [ ] Na/Cl düzeltmesi gerekli miydi?
- [ ] TRUBA slurm submit komutları ve `deffnm` isimleri
- [ ] Beklenmedik hata ve workaround

---

## 10. Yapılacaklar (sırayla)

- [x] Proje iskeleti (`config.sh`, `run.sh`, `lib/common.sh`)
- [x] Aşama 00: ortam kontrolü
- [x] Aşama 01: protein topolojisi (`pdb2gmx -ff -water` non-interaktif)
- [x] Aşama 02: ligand topolojisi (sort_mol2_bonds, CGenFF kapısı, cgenff script, editconf)
- [x] Aşama 03: kompleks (`complex.gro` + `topol.top` — Python yardımcıları)
- [x] Aşama 04: kutu + solvasyon + iyonlar + EM hazırlığı
- [x] Aşama 05: index grupları + ligand posre
- [x] Aşama 06: TRUBA paketi (self-contained slurm) + analiz
- [x] Python yardımcıları: `gro_tools.py`, `top_tools.py`, `ndx_tools.py`
- [ ] Gerçek veriyle uçtan uca test + MANUAL_RUN.md kalibrasyonu

---

## 11. TRUBA bilgileri (mevcut slurm dosyalarından)

| Dosya | Partition | Hesap | Not |
|-------|-----------|-------|-----|
| `em.slurm` | barbun | hnalcakan | grompp + mdrun var |
| `nvt.slurm` | hamsi | hnalcakan | sadece mdrun (grompp eklenecek) |
| `npt.slurm` | hamsi | hnalcakan | sadece mdrun (grompp eklenecek) |
| `md.slurm` | hamsi | hnalcakan | `md_out` deffnm, 56 task, 3 gün |

GROMACS modülü (md.slurm): `/arf/home/hnalcakan/gromacs_2026/bin/GMXRC`

---

## 12. Referanslar

- Tutorial: http://www.mdtutorials.com/gmx/complex/01_pdb2gmx.html
- CGenFF sunucu: https://cgenff.umaryland.edu/initguess/
- PDB indirme: https://www.rcsb.org/
- CHARMM36 force field: `charmm36-feb2026_ljpme_cgenff-5.0.ff` (klasörde mevcut)

---

## 13. Taşınabilirlik kontrol listesi

Başka bilgisayara geçerken şunları taşı:

- [ ] `native_ca1_test_cursor/` klasörünün tamamı (girdiler + `mdprep/`)
- [ ] Bu `PROJECT.md` dosyası
- [ ] Varsa `MANUAL_RUN.md` (manuel notlar)
- [ ] Cursor'da aynı klasörü workspace olarak aç
- [ ] WSL'de `run.sh check` çalıştır ve çıktıyı doğrula

Sohbet geçmişine **güvenme** — bu dosya + diskteki `mdprep/` yeterli.
