# Analiz komutları (yerel)

Sistem: `/mnt/c/Users/zenbook/Desktop/native_ca1_test_cursor`
Production: `md_0_1` (300 ns @ 310 K)
Index grupları: `Protein_ZN_LIG`, `Solvent`

## Çalıştırma

```bash
./run_local_md.sh nvt    # etkileşimli: süre (ps), sıcaklık (K)
./run_local_md.sh npt    # etkileşimli: süre, T, basınç
./run_local_md.sh md     # etkileşimli: süre (ns), sıcaklık
./run_local_md.sh npt -y # soru sormadan mevcut mdp ile çalıştır
# veya: ./run_local_md.sh all

# Kesinti sonrası:
./run_local_md.sh resume
```

## Kalite kontrol

```bash
echo "Temperature" | gmx energy -f nvt.edr -o nvt_temp.xvg
echo "Density" | gmx energy -f npt.edr -o npt_density.xvg
grep -E "94|96|119HSD|ZN" processed.gro
```

## RMSD

```bash
echo -e "Backbone\nBackbone" | gmx rms -s md_0_1.tpr -f md_0_1.xtc -o rmsd.xvg -tu ns
```
