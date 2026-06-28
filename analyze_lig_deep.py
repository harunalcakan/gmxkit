# -*- coding: utf-8 -*-
"""Deep analysis of LIG OFAT resistance data."""
import pandas as pd
import numpy as np
import re
import sys

path = sys.argv[1]
out = sys.argv[2] if len(sys.argv) > 2 else "lig_deep_analysis.txt"

def parse_ohm(val):
    if val is None or (isinstance(val, float) and np.isnan(val)):
        return None
    if isinstance(val, (int, float)):
        return float(val)
    s = str(val).strip()
    if s in ('-', '', 'NaN'):
        return None
  # European comma as decimal or thousands
    s_clean = s.replace(',', '.')
    m = re.match(r'^([\d.]+)\s*M$', s_clean, re.I)
    if m:
        return float(m.group(1)) * 1e6
    m = re.match(r'^([\d.]+)\s*k$', s_clean, re.I)
    if m:
        return float(m.group(1)) * 1e3
    try:
        return float(s_clean)
    except ValueError:
        return None

df = pd.read_excel(path, sheet_name='OFAT', header=0)
# Row 0 is sub-header (1,2,3,4, Ortalama...)
df = df.iloc[1:].copy()

lines = []
def log(x=""):
    lines.append(str(x))

log("=== LIG OFAT DEEP ANALYSIS ===\n")

# Normalize substrate names
df['Altlık_norm'] = df['Altlık'].ffill().str.upper().replace({'CAM': 'Cam'})

# GuoFeng columns
gf_cols = ['GuoFeng LCR-106X (Ω)', 'Unnamed: 9', 'Unnamed: 10', 'Unnamed: 11']
gf_avg = 'Unnamed: 12'
gf_std = 'Unnamed: 13'
gf_rsd = 'Unnamed: 14'

# DM3068 columns
dm_cols = ['Rigol DM3068 (Ω)', 'Unnamed: 42', 'Unnamed: 43', 'Unnamed: 44']
dm_avg = 'Unnamed: 45'

def section_power():
    log("\n" + "="*70)
    log("1. GÜÇ (POWER) SWEEP - Cam vs PLA")
    log("="*70)
    mask = df['Parametre'].isna() & df['Güç (%)'].notna() & df['Hız (mm/dk)'] == 4200
    sub = df[mask].copy()
    for substrate in ['Cam', 'PLA']:
        s = sub[sub['Altlık_norm'] == substrate].sort_values('Güç (%)')
        log(f"\n--- {substrate} (GuoFeng LCR ortalama) ---")
        for _, r in s.iterrows():
            p = r['Güç (%)']
            avg = parse_ohm(r[gf_avg])
            rsd = r[gf_rsd]
            dm = parse_ohm(r[dm_avg])
            if avg is not None:
                log(f"  Güç {p}%: LCR={avg:.1f} Ω (RSD={rsd}%), DM3068 avg={dm}")
            else:
                log(f"  Güç {p}%: no LIG / open circuit")

def section_speed():
    log("\n" + "="*70)
    log("2. HIZ (SPEED) SWEEP @ 10% power")
    log("="*70)
    # Rows after HIZ label
    idx = df[df['Parametre'] == 'HIZ'].index[0]
    sub = df.loc[idx+1:].copy()
    sub = sub[sub['Hız (mm/dk)'].notna() & sub['Güç (%)'] == 10]
    sub = sub[sub['Parametre'].isna() | sub['Parametre'].isin(['HIZ'])]
    sub = sub[sub['No'].notna()]
    for substrate in ['Cam', 'PLA']:
        s = sub[sub['Altlık_norm'] == substrate].sort_values('Hız (mm/dk)')
        log(f"\n--- {substrate} ---")
        for _, r in s.iterrows():
            h = r['Hız (mm/dk)']
            avg = parse_ohm(r[gf_avg])
            if avg:
                log(f"  {h} mm/dk: {avg:.1f} Ω")

def section_passes():
    log("\n" + "="*70)
    log("3. GEÇİŞ SAYISI (PASSES) @ 10%, 4000 mm/dk")
    log("="*70)
    idx = df[df['Parametre'] == 'GEÇİŞ SAYISI'].index[0]
    sub = df.loc[idx:idx+6]
    for _, r in sub.iterrows():
        if pd.notna(r['Geçiş Sayısı']) and pd.notna(r['No']) and parse_ohm(r[gf_avg]):
            sub_name = r['Altlık_norm'] or 'Cam/PLA'
            avg = parse_ohm(r[gf_avg])
            log(f"  {sub_name} passes={int(r['Geçiş Sayısı'])}: {avg:.1f} Ohm")

def section_spacing():
    log("\n" + "="*70)
    log("4. ARALIK (LINE SPACING) @ 10%, 4000 mm/dk")
    log("="*70)
    idx = df[df['Parametre'] == 'ARALIK'].index[0]
    sub = df.loc[idx:idx+8]
    for _, r in sub.iterrows():
        avg = parse_ohm(r[gf_avg])
        if pd.notna(r['Aralık (mm)']) and pd.notna(r['No']) and r['Altlık_norm'] and avg:
            log(f"  {r['Altlık_norm']} spacing={r['Aralık (mm)']} mm: {avg:.1f} Ohm")

def section_zoffset():
    log("\n" + "="*70)
    log("5. Z-OFFSET @ 10%, 4000 mm/dk")
    log("="*70)
    idx = df[df['Parametre'] == 'Z-Offset'].index[0]
    sub = df.loc[idx:idx+6]
    for _, r in sub.iterrows():
        avg = parse_ohm(r[gf_avg])
        if pd.notna(r['Z-Offset (mm)']) and pd.notna(r['No']) and avg:
            log(f"  {r['Altlık_norm']} Z={r['Z-Offset (mm)']} mm: {avg:.1f} Ohm")

def compare_devices():
    log("\n" + "="*70)
    log("6. CİHAZ KARŞILAŞTIRMASI (Güç taraması, ortak noktalar)")
    log("="*70)
    mask = df['Parametre'].isna() & df['Güç (%)'].notna() & df['Hız (mm/dk)'] == 4200
    sub = df[mask]
    ratios = []
    for _, r in sub.iterrows():
        lcr = parse_ohm(r[gf_avg])
        dm = parse_ohm(r[dm_avg])
        if lcr and dm and lcr > 0:
            ratio = dm / lcr
            ratios.append((r['Altlık_norm'], r['Güç (%)'], lcr, dm, ratio))
    log(f"  N comparable points: {len(ratios)}")
    if ratios:
        rvals = [x[4] for x in ratios]
        log(f"  DM3068/LCR ratio: mean={np.mean(rvals):.2f}, std={np.std(rvals):.2f}")
        log(f"  min ratio={min(rvals):.2f}, max ratio={max(rvals):.2f}")
        log("\n  Worst disagreements (|ratio-1|):")
        for item in sorted(ratios, key=lambda x: abs(x[4]-1), reverse=True)[:8]:
            log(f"    {item[0]} {item[1]}%: LCR={item[2]:.0f}, DM={item[3]:.0f}, ratio={item[4]:.2f}")

def sweet_spot():
    log("\n" + "="*70)
    log("7. SWEET SPOT ÖZETİ (düşük direnç + makul tekrarlanabilirlik)")
    log("="*70)
    mask = df['Parametre'].isna() & df['Güç (%)'].notna()
    records = []
    for _, r in df[mask].iterrows():
        avg = parse_ohm(r[gf_avg])
        rsd = r[gf_rsd]
        if avg and avg < 5000 and isinstance(rsd, (int, float)) and rsd < 10:
            records.append({
                'param': 'power',
                'sub': r['Altlık_norm'],
                'setting': f"{r['Güç (%)']}%",
                'R': avg,
                'RSD': rsd
            })
    # speed
    idx = df[df['Parametre'] == 'HIZ'].index[0]
    for _, r in df.loc[idx+1:idx+20].iterrows():
        avg = parse_ohm(r[gf_avg])
        rsd = r[gf_rsd]
        if avg and isinstance(rsd, (int, float)) and rsd < 5:
            records.append({
                'param': 'speed',
                'sub': r['Altlık_norm'],
                'setting': f"{r['Hız (mm/dk)']} mm/dk",
                'R': avg,
                'RSD': rsd
            })
    records.sort(key=lambda x: x['R'])
    log("  Top low-R configurations (RSD constraints):")
    for rec in records[:15]:
        log(f"    {rec['sub']} {rec['param']} {rec['setting']}: R={rec['R']:.1f} Ω, RSD={rec['RSD']:.2f}%")

section_power()
section_speed()
section_passes()
section_spacing()
section_zoffset()
compare_devices()
sweet_spot()

with open(out, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
print("Done:", out)
