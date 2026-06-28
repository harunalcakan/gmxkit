# GmxKit — İlk çalıştırma kontrol listesi (Türkçe)

Detaylı kurulum: [docs/en/INSTALL.md](en/INSTALL.md) (İngilizce adım adım)

## Ortam
- [ ] WSL2 Ubuntu veya Linux terminal
- [ ] `./md` çalıştırılabilir (`chmod +x md`)

## GROMACS
- [ ] `gmx --version` aynı shell'de çalışıyor
- [ ] Gerekirse `mdprep/config.sh` → `GMX=`

## Force field ve girdiler
- [ ] `charmm36-*.ff/` proje kökünde
- [ ] `protein.pdb`, `ligand.mol2`, `*.mdp` mevcut

## Kurulum
- [ ] `./md install` tamamlandı
- [ ] `./md check` veya aşama 00 — hata yok

## Production öncesi
- [ ] Hazırlık 00–06 tamam
- [ ] `./md audit` OK
- [ ] CGenFF `.str` (aşama 02, manuel)

## Hızlı komutlar

```bash
./md install && ./md check && ./md
```
