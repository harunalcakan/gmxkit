# -*- coding: utf-8 -*-
"""Resistance-only publication figures data — Creality Falcon 2 22W."""
import pandas as pd
import numpy as np

PATH = r"C:\Users\zenbook\Desktop\Çalışmalar\GENEL\.MSc_Tez\LIG_sentez_optimizasyon\Son Tarama Verileri.xlsx"
OUT = r"C:\Users\zenbook\Desktop\native_ca1_test_cursor\lig_resistance_figure_data.csv"

MAX_W = 22.0  # Creality Falcon 2 22W at 100%

def pct_to_w(pct):
    return MAX_W * pct / 100.0

def line_energy_j_per_mm(power_w, speed_mm_min):
    v_mm_s = speed_mm_min / 60.0
    return power_w / v_mm_s

def areal_energy_j_per_mm2(power_w, speed_mm_min, spacing_mm):
    v_mm_s = speed_mm_min / 60.0
    return power_w / (v_mm_s * spacing_mm)

def parse_val(val):
    if val is None or (isinstance(val, float) and np.isnan(val)):
        return None
    if isinstance(val, (int, float)):
        return float(val)
    s = str(val).strip()
    if s in ("-", ""):
        return None
    try:
        return float(s.replace(",", "."))
    except ValueError:
        return None

df = pd.read_excel(PATH, sheet_name="OFAT", header=0)
df = df.iloc[1:].copy()
df["Altlık_norm"] = df["Altlık"].ffill().str.upper().replace({"CAM": "Cam"})

gf_avg = "Unnamed: 12"
gf_rsd = "Unnamed: 14"
rows = []

# Power sweep (4200 mm/min, 1 pass, 0.075 spacing)
mask_pwr = (df["Hız (mm/dk)"] == 4200) & (df["Geçiş Sayısı"] == 1) & (df["Aralık (mm)"] == 0.075)
for _, r in df[mask_pwr].iterrows():
    pct = r["Güç (%)"]
    sub = r["Altlık_norm"]
    if pd.isna(pct) or pd.isna(sub):
        continue
    R = parse_val(r[gf_avg])
    if R is None:
        continue
    P = pct_to_w(pct)
    spd = 4200.0
    sp = 0.075
    rows.append({
        "series": "power_sweep",
        "substrate": sub,
        "power_pct": pct,
        "power_W": P,
        "speed_mm_min": spd,
        "passes": 1,
        "spacing_mm": sp,
        "z_offset_mm": r["Z-Offset (mm)"] if pd.notna(r["Z-Offset (mm)"]) else 0,
        "R_mean_Ohm": R,
        "RSD_pct": r[gf_rsd],
        "line_energy_J_mm": line_energy_j_per_mm(P, spd),
        "areal_energy_J_mm2": areal_energy_j_per_mm2(P, spd, sp),
        "log10_R": np.log10(R),
    })

# Speed sweep (10%, 1 pass, 0.075)
idx = df[df["Parametre"] == "HIZ"].index[0]
sub_df = df.loc[idx + 1 : idx + 20]
for _, r in sub_df.iterrows():
    spd = r["Hız (mm/dk)"]
    if pd.isna(spd) or r["Güç (%)"] != 10:
        continue
    sub = r["Altlık_norm"]
    R = parse_val(r[gf_avg])
    if R is None or pd.isna(sub):
        continue
    P = pct_to_w(10)
    sp = 0.075
    rows.append({
        "series": "speed_sweep",
        "substrate": sub,
        "power_pct": 10,
        "power_W": P,
        "speed_mm_min": spd,
        "passes": 1,
        "spacing_mm": sp,
        "z_offset_mm": 0,
        "R_mean_Ohm": R,
        "RSD_pct": r[gf_rsd],
        "line_energy_J_mm": line_energy_j_per_mm(P, spd),
        "areal_energy_J_mm2": areal_energy_j_per_mm2(P, spd, sp),
        "log10_R": np.log10(R),
    })

# Passes
idx = df[df["Parametre"] == "GEÇİŞ SAYISI"].index[0]
for _, r in df.loc[idx : idx + 6].iterrows():
    n = r["Geçiş Sayısı"]
    if pd.isna(n) or pd.isna(r["No"]):
        continue
    R = parse_val(r[gf_avg])
    if R is None:
        continue
    sub = r["Altlık_norm"]
    P = pct_to_w(10)
    spd = 4000.0
    sp = 0.075
    rows.append({
        "series": "pass_sweep",
        "substrate": sub,
        "power_pct": 10,
        "power_W": P,
        "speed_mm_min": spd,
        "passes": int(n),
        "spacing_mm": sp,
        "z_offset_mm": 0,
        "R_mean_Ohm": R,
        "RSD_pct": r[gf_rsd],
        "line_energy_J_mm": line_energy_j_per_mm(P, spd) * int(n),
        "areal_energy_J_mm2": areal_energy_j_per_mm2(P, spd, sp) * int(n),
        "log10_R": np.log10(R),
    })

# Spacing
idx = df[df["Parametre"] == "ARALIK"].index[0]
for _, r in df.loc[idx : idx + 8].iterrows():
    sp = r["Aralık (mm)"]
    if pd.isna(sp) or pd.isna(r["No"]) or pd.isna(r["Altlık_norm"]):
        continue
    R = parse_val(r[gf_avg])
    if R is None:
        continue
    sub = r["Altlık_norm"]
    P = pct_to_w(10)
    spd = 4000.0
    rows.append({
        "series": "spacing_sweep",
        "substrate": sub,
        "power_pct": 10,
        "power_W": P,
        "speed_mm_min": spd,
        "passes": 1,
        "spacing_mm": sp,
        "z_offset_mm": 0,
        "R_mean_Ohm": R,
        "RSD_pct": r[gf_rsd],
        "line_energy_J_mm": line_energy_j_per_mm(P, spd),
        "areal_energy_J_mm2": areal_energy_j_per_mm2(P, spd, sp),
        "log10_R": np.log10(R),
    })

# Z-offset
idx = df[df["Parametre"] == "Z-Offset"].index[0]
for _, r in df.loc[idx : idx + 6].iterrows():
    z = r["Z-Offset (mm)"]
    if pd.isna(z) or pd.isna(r["No"]):
        continue
    R = parse_val(r[gf_avg])
    if R is None:
        continue
    sub = r["Altlık_norm"]
    P = pct_to_w(10)
    spd = 4000.0
    sp = 0.075
    rows.append({
        "series": "zoffset_sweep",
        "substrate": sub,
        "power_pct": 10,
        "power_W": P,
        "speed_mm_min": spd,
        "passes": 1,
        "spacing_mm": sp,
        "z_offset_mm": z,
        "R_mean_Ohm": R,
        "RSD_pct": r[gf_rsd],
        "line_energy_J_mm": line_energy_j_per_mm(P, spd),
        "areal_energy_J_mm2": areal_energy_j_per_mm2(P, spd, sp),
        "log10_R": np.log10(R),
    })

out_df = pd.DataFrame(rows)
out_df.to_csv(OUT, index=False, encoding="utf-8-sig")
print(f"Rows: {len(out_df)}")
print(f"Written: {OUT}")
print("\nPower sweep line energy range (J/mm):")
pwr = out_df[out_df["series"] == "power_sweep"]
for sub in ["Cam", "PLA"]:
    s = pwr[pwr["substrate"] == sub].sort_values("power_pct")
    print(f"  {sub}: {s['power_pct'].tolist()} % -> R {s['R_mean_Ohm'].tolist()}")
