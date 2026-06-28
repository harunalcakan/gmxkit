#!/usr/bin/env python3
"""topol.top cerrahisi: ligand include + molecules + posre."""
from __future__ import annotations

import argparse
import re
import sys


def _already_has(lines: list[str], needle: str) -> bool:
    return any(needle in ln for ln in lines)


def read_moleculetype(itp_path: str) -> str:
    """lig.itp içindeki [ moleculetype ] adını oku (cgenff mol2 başlığından gelir)."""
    in_mt = False
    with open(itp_path, encoding="utf-8") as f:
        for line in f:
            if re.match(r"^\s*\[\s*moleculetype\s*\]", line, re.I):
                in_mt = True
                continue
            if in_mt:
                stripped = line.strip()
                if not stripped or stripped.startswith(";"):
                    continue
                if stripped.startswith("["):
                    break
                return stripped.split()[0]
    raise SystemExit(f"HATA: moleculetype okunamadı: {itp_path}")


def add_ligand_topology(
    input_path: str,
    output_path: str,
    lig_prm: str,
    lig_itp: str,
    lig_resname: str,
) -> None:
    moltype = read_moleculetype(lig_itp)
    with open(input_path, encoding="utf-8") as f:
        lines = f.readlines()

    if _already_has(lines, f'#include "{lig_itp}"'):
        print(f"ATLANDI: {lig_itp} zaten mevcut")
        with open(output_path, "w", encoding="utf-8", newline="\n") as f:
            f.writelines(lines)
        return

    out: list[str] = []
    prm_done = itp_done = mol_done = False
    in_molecules = False

    for i, line in enumerate(lines):
        out.append(line)

        if (
            not prm_done
            and re.search(r'#include\s+".*forcefield\.itp"', line)
            and lig_prm not in line
        ):
            out.append("\n; Include ligand parameters\n")
            out.append(f'#include "{lig_prm}"\n')
            prm_done = True

        if not itp_done and re.match(r"^\s*#endif", line):
            ctx = "".join(lines[max(0, i - 6) : i + 1])
            if "posre.itp" in ctx or "POSRES" in ctx:
                out.append("\n; Include ligand topology\n")
                out.append(f'#include "{lig_itp}"\n')
                itp_done = True

        if re.match(r"^\s*\[\s*molecules\s*\]", line, re.I):
            in_molecules = True
            continue

        if in_molecules and not mol_done:
            stripped = line.strip()
            if stripped and not stripped.startswith(";") and re.match(r"^Protein", stripped):
                out.append(f"{moltype:<15} 1\n")
                mol_done = True

    if not prm_done:
        raise SystemExit("HATA: forcefield.itp include bulunamadı")
    if not itp_done:
        raise SystemExit("HATA: posre.itp / #endif anchor bulunamadı")
    if not mol_done:
        raise SystemExit("HATA: [ molecules ] altında Protein satırı bulunamadı")

    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(out)
    print(f"OK: ligand topolojisi eklendi -> {output_path}")


def add_ligand_posre(
    input_path: str,
    output_path: str,
    lig_itp: str,
    lig_posre_itp: str,
) -> None:
    with open(input_path, encoding="utf-8") as f:
        lines = f.readlines()

    if _already_has(lines, f'#include "{lig_posre_itp}"'):
        print(f"ATLANDI: {lig_posre_itp} zaten mevcut")
        with open(output_path, "w", encoding="utf-8", newline="\n") as f:
            f.writelines(lines)
        return

    out: list[str] = []
    done = False
    for line in lines:
        out.append(line)
        if not done and f'#include "{lig_itp}"' in line:
            out.append("\n; Ligand position restraints\n")
            out.append("#ifdef POSRES\n")
            out.append(f'#include "{lig_posre_itp}"\n')
            out.append("#endif\n")
            done = True

    if not done:
        raise SystemExit(f'HATA: #include "{lig_itp}" satırı bulunamadı')

    with open(output_path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(out)
    print(f"OK: ligand posre eklendi -> {output_path}")


def fix_charmm_ion_names(topol_path: str, gro_path: str) -> bool:
    """CHARMM NA+/CL- <-> NA/CL uyumsuzluğunu düzelt. Değişiklik yapıldıysa True."""
    changed = False
    for path, pairs in (
        (topol_path, (("NA+", "NA "), ("CL-", "CL "))),
        (gro_path, ((" NA+", " NA "), (" CL-", " CL "))),
    ):
        with open(path, encoding="utf-8") as f:
            text = f.read()
        orig = text
        for old, new in pairs:
            text = text.replace(old, new)
        if text != orig:
            with open(path, "w", encoding="utf-8", newline="\n") as f:
                f.write(text)
            print(f"OK: iyon adları düzeltildi -> {path}")
            changed = True
    return changed


def sort_lig_prm_dihedrals(prm_path: str) -> None:
    """lig.prm [ dihedraltypes ] bloğunu alfabetik sırala (GROMACS çakışma hatası)."""
    with open(prm_path, encoding="utf-8") as f:
        lines = f.readlines()

    out: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if re.match(r"^\s*\[\s*dihedraltypes\s*\]", line, re.I):
            out.append(line)
            i += 1
            block: list[str] = []
            while i < len(lines) and not re.match(r"^\s*\[", lines[i]):
                block.append(lines[i])
                i += 1
            comments = [ln for ln in block if not ln.strip() or ln.strip().startswith(";")]
            data_lines = [ln for ln in block if ln.strip() and not ln.strip().startswith(";")]
            data_lines.sort(key=lambda ln: tuple(ln.split()[:4]))
            out.extend(comments)
            out.extend(data_lines)
            continue
        out.append(line)
        i += 1

    with open(prm_path, "w", encoding="utf-8", newline="\n") as f:
        f.writelines(out)
    print(f"OK: dihedraltypes sıralandı -> {prm_path}")


def main() -> int:
    ap = argparse.ArgumentParser(description="topol.top düzenleme")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p1 = sub.add_parser("add-ligand", help="lig.prm, lig.itp, molecules")
    p1.add_argument("input_top")
    p1.add_argument("output_top")
    p1.add_argument("--prm", required=True)
    p1.add_argument("--itp", required=True)
    p1.add_argument("--resname", required=True)

    p2 = sub.add_parser("add-posre", help="posre_lig.itp bloğu")
    p2.add_argument("input_top")
    p2.add_argument("output_top")
    p2.add_argument("--itp", required=True)
    p2.add_argument("--posre", required=True)

    p3 = sub.add_parser("fix-ions", help="NA+/CL- ad düzeltmesi")
    p3.add_argument("topol")
    p3.add_argument("gro")

    p4 = sub.add_parser("sort-prm", help="lig.prm dihedraltypes sırala")
    p4.add_argument("prm")

    args = ap.parse_args()
    if args.cmd == "add-ligand":
        add_ligand_topology(args.input_top, args.output_top, args.prm, args.itp, args.resname)
    elif args.cmd == "add-posre":
        add_ligand_posre(args.input_top, args.output_top, args.itp, args.posre)
    elif args.cmd == "fix-ions":
        fix_charmm_ion_names(args.topol, args.gro)
    elif args.cmd == "sort-prm":
        sort_lig_prm_dihedrals(args.prm)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
