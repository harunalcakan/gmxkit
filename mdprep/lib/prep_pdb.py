#!/usr/bin/env python3
"""Metalloenzim PDB hazırlığı: HSD yeniden adlandırma + Zn önüne TER."""
from __future__ import annotations

import argparse
import re
import sys


def prepare_metallo_pdb(
    input_path: str,
    output_path: str,
    hsd_residues: list[int],
    chain: str = "A",
    metal_resname: str = "ZN",
) -> dict:
    with open(input_path, encoding="utf-8") as f:
        lines = f.readlines()

    hsd_set = set(hsd_residues)
    stats = {
        "hsd_renamed": 0,
        "ter_inserted": False,
        "zn_found": False,
        "hsd_residues": hsd_residues,
    }

    out: list[str] = []
    zn_idx: int | None = None

    for i, line in enumerate(lines):
        if line.startswith(("ATOM  ", "HETATM")):
            m = re.match(
                r"^(ATOM  |HETATM)\s+\d+\s+\S+\s+(\S+)\s+(\S+)\s+(\d+)",
                line,
            )
            if m:
                resname, ch, resseq_s = m.group(2), m.group(3), m.group(4)
                resseq = int(resseq_s)
                if (
                    line.startswith("ATOM  ")
                    and resname == "HIS"
                    and ch == chain
                    and resseq in hsd_set
                ):
                    line = line.replace(f" HIS {chain}", f" HSD {chain}", 1)
                    stats["hsd_renamed"] += 1
                if resname == metal_resname and line.startswith("HETATM"):
                    stats["zn_found"] = True
                    if zn_idx is None:
                        zn_idx = len(out)
        out.append(line)

    if zn_idx is not None:
        prev = out[zn_idx - 1] if zn_idx > 0 else ""
        if not prev.startswith("TER"):
            out.insert(zn_idx, "TER\n")
            stats["ter_inserted"] = True

    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(out)

    return stats


def main() -> int:
    ap = argparse.ArgumentParser(description="Metalloenzim PDB hazırlığı (CA/Zn)")
    ap.add_argument("input_pdb")
    ap.add_argument("output_pdb")
    ap.add_argument("--hsd", required=True, help="HSD yapılacak residue numaraları: 94,96,119")
    ap.add_argument("--chain", default="A")
    ap.add_argument("--metal", default="ZN")
    args = ap.parse_args()

    hsd = [int(x.strip()) for x in args.hsd.replace(" ", ",").split(",") if x.strip()]
    stats = prepare_metallo_pdb(
        args.input_pdb, args.output_pdb, hsd, args.chain, args.metal.upper()
    )
    print(f"OK: {args.output_pdb}")
    print(f"  HSD satır: {stats['hsd_renamed']} (hedef: {stats['hsd_residues']})")
    print(f"  Zn bulundu: {stats['zn_found']}")
    print(f"  TER eklendi: {stats['ter_inserted']}")
    if not stats["zn_found"]:
        print("UYARI: PDB'de Zn (HETATM) yok — CA simülasyonu için Zn koordinatını ekleyin.", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
