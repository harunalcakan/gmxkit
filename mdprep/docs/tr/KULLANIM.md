# GmxKit — Kullanım Kılavuzu

Bu kılavuz, **GmxKit** (`mdprep/`) ile GROMACS protein–ligand MD hazırlığını nasıl kullanacağınızı anlatır. Örnek profil: **CA + Zn²⁺ + ligand** (2Q38); farklı sistemlerde config değişir, akış aynı kalır.  
Hedef örnekler: **CA I / CA II** yapıları (ör. PDB **6I0L**), ligand **2Q38** — farklı komplekslerde PDB/ligand değişir, akış aynı kalır.

---

## 1. Genel bakış — GmxKit menüsü

Proje kökünden **tek komut**:

```bash
cd /path/to/native_ca1_test_cursor
./md
```

Ana menü **hazırlık durumuna göre** değişir:

| Durum | Ekran | Seçenekler |
|-------|--------|------------|
| Hazırlık devam | Tam aşama tablosu (00–06) | **1** Hazırlık · **2** Araçlar |
| Hazırlık tamam | Özet: EM/NVT/NPT/MD ✓/· + kuyruk satırı | **1** Kuyruk · **2** Simülasyon · **3** Kontrol · **4** Hazırlık · **5** Araçlar |

Numara veya harf kısayolu (ör. `1` veya `J`) aynı menüyü açar. **`r`** = kuyruk durumu (hazırlık tamamken).

| Tuş | Menü | Ne yapar |
|-----|------|----------|
| **1 / J** | Kuyruk | EM/NVT/NPT/MD arka planda — job ID, log, iptal |
| **2 / S** | Simülasyon | Ön planda NVT/NPT/MD — süre/sıcaklık sorar |
| **3 / K** | Kontrol | Binding check (Zn–ligand, RMSD) |
| **4 / P** | Hazırlık | Aşama 00–06 (tek tek veya `a`=hepsi) |
| **5 / A** | Araçlar | Temizlik, reset, config, kurulum |
| **0 / Q** | Çıkış | |

**S vs J:** S terminalde bekler (test/kısa koşu). J arka planda çalışır (uzun NPT/MD, zincir).

### Hazırlık vs simülasyon

| Faz | Ne yapılır | EM mdrun? |
|-----|------------|-----------|
| **P — Hazırlık 00–06** | pdb2gmx, CGenFF, solvasyon, **em.tpr** | Hayır — sadece grompp |
| **J — Kuyruk** | EM → NVT → NPT → MD (mdrun) | Evet — ilk kuyruk adımı |

Hazırlıkta kritik GROMACS kararları (`PREP_INTERACTIVE=yes`) **sorulmadan gizlenmez**: stage başında parametreler ekrana yazılır, `[Y/n/e=config]` ile onay veya `config.sh` düzenleme.

Önerilen akış:

```
./md  →  P  (00–06; onay kapılarında FF, su, genion, index kontrol)
     →  J  →  EM  →  NVT  →  NPT  →  MD   (veya 5 = zincir)
     →  r       kuyruk durumu
     →  K       binding (npt / md)
     →  L       analiz (PBC + RMSD/RMSF/Rg/SASA)
```

CLI: `./md queue submit nvt`, `./md queue status`, `./md analyze`, `./md audit`, `./md help`

### Analiz — `./md analyze` veya menü **[L]**

GROMACS grup menüsü sorulmaz; gruplar `config.sh` + `index.ndx`:

| Adım | Tarif |
|------|--------|
| trjconv 1 | `-pbc mol -ur compact -center Protein` → `md_nopbc.xtc` |
| trjconv 2 | `-fit rot+trans Backbone` → `md_pbc.xtc` |
| Protein RMSD | Fit+ölçüm: **Backbone** (`md_nopbc.xtc`) |
| Ligand RMSD | Fit **Backbone**, ölçüm **2Q38** |
| RMSF / Rg / SASA | Fit edilmiş `md_pbc.xtc` |
| Binding | `md_pbc.xtc` üzerinde Zn–lig, HSD–lig |

Çıktı: `mdprep/logs/analysis/` + `ANALYSIS_REPORT.txt`

| Script | Görevi |
|--------|--------|
| `./md` / `mdprep/md.sh` | **GmxKit** — menü + CLI |
| `mdprep/run.sh` | Hazırlık aşamaları (00–06) |
| `run_local_md.sh` | NVT → NPT → production MD |
| `check_binding.sh` | Ligand aktif sitede mi? (gmx mindist + RMSD) |
| `mdprep/config.sh` | **Tek ayar dosyası** — her yeni kompleks için düzenlenir |

**VMD gerekmez** otomasyon için; isteğe bağlı görsel teyit: `vmd npt.gro npt.xtc`

---

## 2. Kurulum (bir kez)

WSL/Linux içinde proje klasöründe:

```bash
cd /path/to/native_caX_complex   # her kompleks için ayrı klasör önerilir

./mdprep/run.sh setup --system   # gromacs, perl, vb.
./mdprep/run.sh setup            # python venv + cgenff (py3)
./mdprep/md.sh check             # ortam + girdi dosyaları
```

Gerekli dosyalar (WORKDIR kökünde):

- `protein.pdb` — CA + **Zn** (HETATM)
- `ligand.mol2`
- `charmm36-feb2026_ljpme_cgenff-5.0.ff/` (veya config'teki FF)
- `*.mdp` (em, ions, nvt, npt, md)

---

## 3. Yeni kompleks: CA1 / CA2 (6I0L + 2Q38 örneği)

### Önerilen klasör yapısı

Her kompleks **ayrı dizin** — karışıklığı önler:

```
ca2_6i0l_2q38/
├── protein.pdb          ← 6I0L'den (Zn + protein)
├── ligand.mol2          ← 2Q38
├── ligand_fix.str       ← CGenFF çıktısı (veya lig.str)
├── mdprep/config.sh     ← bu komplexe özel
├── em.mdp nvt.mdp ...
└── mdprep/
```

CA I için ikinci klasör: `ca1_.../` — aynı ligand, farklı protein PDB.

### `config.sh` — komplese göre değiştirin

| Ayar | CA II (örnek mevcut test) | Yeni kompleste |
|------|---------------------------|----------------|
| `METAL_HSD_RESIDUES` | `94 96 119` | PyMOL/VMD'den Zn koordinasyon histidinleri |
| `CHECK_LIG_RESNAME` | `2Q38` | CGenFF/mol2 residue adı (lig.itp moleculetype) |
| `METAL_ION_RESNAME` | `ZN` | genelde aynı |
| `METAL_CHAIN` | `A` | PDB chain |
| `PROD_NS` | `300` | production süresi (ns) |

**Önemli:** `METAL_HSD_RESIDUES` numaraları **PDB'ye göre** değişir; CA I ile CA II aynı olmayabilir.

### CGenFF adımı (stage 02)

1. Pipeline `lig.str` beklerken durur (veya siz önceden `ligand_fix.str` koyarsınız).
2. https://cgenff.umaryland.edu/initguess/ → `ligand_sorted.mol2` yükleyin.
3. `.str` indirin → `lig.str` veya `ligand_fix.str`.
4. `./mdprep/md.sh stage 02` ile devam.

Ligand `.itp` içindeki **moleculetype** (ör. `2Q38`) → `CHECK_LIG_RESNAME` ile aynı olmalı.

---

## 4. Hazırlık pipeline'ı

```bash
./mdprep/md.sh prep          # tüm aşamalar (kaldığı yerden devam)
./mdprep/md.sh status        # hangi aşama bitti?
./mdprep/md.sh stage 04      # tek aşama
./mdprep/md.sh reset         # checkpoint sıfırla (dosyalar kalır)
```

| Aşama | Çıktı (özet) |
|-------|----------------|
| 00b | `protein_prep.pdb` (HSD, TER, Zn) |
| 01 | `processed.gro`, `topol.top` |
| 02 | `lig.itp`, `ligand.gro` |
| 03 | `complex.gro` |
| 04 | `em.gro` (+ EM sonrası binding check) |
| 05 | `index.ndx` (`Protein_ZN_LIG`, `Solvent`) |
| 06 | `run_local_md.sh`, `check_binding.sh` |

---

## 5. MD simülasyonu

Etkileşimli (süre/sıcaklık sorar):

```bash
./mdprep/md.sh nvt
./mdprep/md.sh npt
./mdprep/md.sh md
```

Soru sormadan:

```bash
./mdprep/md.sh npt -y
INTERACTIVE=no ./run_local_md.sh md
```

**Süre birimleri (script soruları):**

| Adım | Sorulan birim | Örnek kısa test |
|------|----------------|-----------------|
| NVT / NPT | ps | `50` |
| Production MD | ns | `0.05` (= 50 ps) veya `300` |

Sıcaklık varsayılan: **310 K** (Enter = değiştirme).

---

## 6. Ligand–aktif site kontrolü

```bash
./mdprep/md.sh binding em
./mdprep/md.sh binding npt
./mdprep/md.sh binding md
```

`run_local_md.sh` her faz sonrası otomatik çalıştırır (`CHECK_BINDING=yes`).

Ölçülenler:

1. **Zn – ligand** minimum mesafe (trajectory'de en kötü frame)
2. **HSD (config'teki resid'ler) – ligand** minimum mesafe
3. **Ligand RMSD** (referans: `em.tpr`, son frame)

Grafikler: `mdprep/logs/binding_checks/*.xvg`

Kapatmak: `config.sh` → `CHECK_BINDING="no"`  
Eşik aşılınca durdurmak: `CHECK_BINDING_STRICT="yes"`

Eşikler `config.sh` içinde (nm): `CHECK_ZN_LIG_WARN`, `CHECK_HSD_LIG_WARN`, vb.

---

## 6b. Hazırlık denetimi — `./md audit`

Kuyruğa göndermeden önce veya şüphede:

```bash
./md audit              # dosya + index + HSD/Zn + mdp kontrol
./md audit --fix-mdp    # + config'ten nvt/npt/md nsteps senkronize
```

Menü: **[K] Kontrol → 5** (denetim) veya **6** (MDP senkron).

Rapor: `mdprep/logs/audit_report.txt`

---

## 6c. Analiz — `./md analyze` veya menü **[L]**

PBC düzeltme + RMSD/RMSF/Rg/SASA (gruplar config'ten, soru yok):

| Adım | Tarif |
|------|--------|
| trjconv 1 | `-pbc mol -center Protein` → `md_nopbc.xtc` |
| trjconv 2 | `-fit rot+trans Backbone` → `md_pbc.xtc` |
| Protein/ligand RMSD | Fit **Backbone** on `md_nopbc.xtc` |
| RMSF / Rg / SASA | Fit edilmiş `md_pbc.xtc` |

Çıktı: `mdprep/logs/analysis/` + `ANALYSIS_REPORT.txt`

**Not:** Kısa test (5 ps) trajektorisinde 1 frame olabilir — RMSD anlamlı değildir; 300 ns MD sonrası kullanın.

---

## 7. Sorun giderme

| Sorun | Çözüm |
|-------|--------|
| pdb2gmx / lipid.rtp hatası | FF paketini yeniden indir; `lipid.rtp` bütünlüğü |
| `posre.itp` boş / yok (01) | Normal: TER+Zn ile `posre_Protein_chain_*.itp` oluşur; aşama 01 otomatik düzeltir |
| CGenFF bekliyor | `lig.str` / `ligand_fix.str` manuel indir |
| `[ molecules ]` ligand adı | `lig.itp` moleculetype ile eşleştir (`2Q38` ≠ `LIG`) |
| Binding uyarıları | Eşikleri kalibre edin; PyMOL/VMD ile aktif siteye bakın |
| WSL yavaş mdrun | Normal; `-nt` ile thread sayısı (`GMX_MDRUN_EXTRA`) |

Loglar: `mdprep/logs/`

---

## 8. Strateji: önce ne, sonra ne?

### Şimdi (önerilen)

1. **CA II + 2Q38** (mevcut test) ile uçtan uca doğrulayın.
2. **6I0L + 2Q38** için **yeni klasör** açın; sadece `protein.pdb` + `config.sh` (HSD resid'leri!) güncelleyin.
3. CA I için üçüncü klasör — aynı akış.

Bu aşamada “akıllı sistem” şart değil; **her kompleks = bir WORKDIR + bir config.sh** yeterli.

### Sonra (geliştirme)

| Adım | Fayda |
|------|--------|
| `mdprep/profiles/ca2_6i0l.env` | Kopyala-yapıştır config şablonları |
| `md.sh init ca2_6i0l` | Yeni proje klasörü + şablon config |
| Tek PDB'den HSD/Zn otomatik tespit | `prep_pdb.py` genişletme |
| Tek tık `./mdprep/md.sh all-in-one` | prep + kısa NVT/NPT/MD + binding raporu |

**Önce işleri bitirin, sonra profil katmanı ekleyin** — aksi halde henüz test edilmemiş otomasyon üstüne otomasyon bindirirsiniz.

---

## 9. Hızlı komut özeti

```bash
./md                            # etkileşimli menü (önerilen)
./md check
./md prep
./md status
./md clean --dry-run            # silinecekleri listele
./md clean                      # çıktıları sil, girdileri koru
./md npt
./md binding npt
```

### Sistemi baştan kurmak

| Komut | Ne yapar |
|-------|----------|
| `reset` | Sadece checkpoint sıfırlar, dosyalar kalır |
| `clean --dry-run` | Silinecekleri listeler |
| `clean` | gro/tpr/topol/index/MD çıktıları + checkpoint siler |
| `clean --remove-backups` | mdprep/backups/ de siler |
| `clean --remove-str` | lig.str / ligand_fix.str de siler (CGenFF yeniden) |

**Korunanlar:** `protein.pdb`, `ligand.mol2`, `*.mdp`, force field, `mdprep/` scriptleri, (varsayılan) `.str` dosyaları.

---

## 10. Referans dosyalar

- `mdprep/config.sh` — tüm parametreler
- `mdprep/PROJECT.md` — mimari kararlar
- `mdprep/MANUAL_RUN.md` — eski script eşlemesi, adım adım teknik notlar
- `mdprep/ANALYSIS.md` — üretim sonrası analiz komutları (stage 06)
