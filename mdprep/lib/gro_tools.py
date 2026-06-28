#!/usr/bin/env python3
"""GROMACS .gro birleştirme: protein + ligand -> complex."""
from __future__ import annotations

import argparse
import sys


def merge_gro(protein_gro: str, ligand_gro: str, output_gro: str) -> int:
    with open(protein_gro, encoding="utf-8") as pf, open(ligand_gro, encoding="utf-8") as lf:
        plines = pf.readlines()
        llines = lf.readlines()

    if len(plines) < 3 or len(llines) < 3:
        print("HATA: geçersiz .gro dosyası (en az 3 satır gerekli)", file=sys.stderr)
        return 1

    try:
        natom_p = int(plines[1].strip())
        natom_l = int(llines[1].strip())
    except ValueError:
        print("HATA: atom sayısı satırı okunamadı", file=sys.stderr)
        return 1

    body_p = plines[2:-1]
    body_l = llines[2:-1]
    if len(body_p) != natom_p or len(body_l) != natom_l:
        print(
            f"UYARI: satır sayısı uyumsuz (protein {len(body_p)}/{natom_p}, "
            f"ligand {len(body_l)}/{natom_l})",
            file=sys.stderr,
        )

    total = natom_p + natom_l
    out = [plines[0], f"{total}\n", *body_p, *body_l, plines[-1]]

    with open(output_gro, "w", encoding="utf-8", newline="\n") as of:
        of.writelines(out)

    print(f"OK: {natom_p} + {natom_l} = {total} atom -> {output_gro}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description="Protein ve ligand .gro birleştir")
    ap.add_argument("protein_gro")
    ap.add_argument("ligand_gro")
    ap.add_argument("output_gro")
    args = ap.parse_args()
    return merge_gro(args.protein_gro, args.ligand_gro, args.output_gro)


if __name__ == "__main__":
    raise SystemExit(main())
