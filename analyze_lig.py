# -*- coding: utf-8 -*-
import pandas as pd
import os
import sys

path = sys.argv[1] if len(sys.argv) > 1 else None
out = sys.argv[2] if len(sys.argv) > 2 else "lig_analysis_output.txt"

if not path:
    print("Usage: python analyze_lig.py <xlsx_path> [output.txt]")
    sys.exit(1)

if not os.path.exists(path):
    print("File not found:", path)
    sys.exit(1)

lines = []

def log(msg=""):
    lines.append(str(msg))

xl = pd.ExcelFile(path)
log("Sheets: " + str(xl.sheet_names))

for s in xl.sheet_names:
    df = pd.read_excel(path, sheet_name=s)
    log("\n" + "=" * 60)
    log("Sheet: " + s)
    log("Shape: " + str(df.shape))
    log("Columns: " + str(list(df.columns)))
    log("\n--- First 67 rows (all) ---")
    log(df.to_string())
    log("\n--- Data types ---")
    log(df.dtypes.to_string())
    log("\n--- Numeric summary ---")
    num = df.select_dtypes(include='number')
    if len(num.columns):
        log(num.describe().to_string())
    log("\n--- Missing values ---")
    log(df.isnull().sum().to_string())
    log("\n--- Column unique values (low cardinality) ---")
    for col in df.columns:
        n = df[col].nunique()
        if n < 30:
            vals = df[col].dropna().unique()
            log("  %s (%d): %s" % (col, n, list(vals)[:25]))

with open(out, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))

print("Written to", out)
