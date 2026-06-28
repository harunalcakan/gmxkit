#!/usr/bin/env python3
"""make_ndx / genion grup parse ve index oluşturma."""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path


def parse_groups(text: str) -> dict[int, str]:
    groups: dict[int, str] = {}
    for line in text.splitlines():
        m = re.match(r"^\s*(\d+)\s+(\S+)", line)
        if m:
            groups[int(m.group(1))] = m.group(2)
    return groups


def list_groups(gmx: str, gro: str, cwd: str | None = None) -> dict[int, str]:
    with tempfile.NamedTemporaryFile(suffix=".ndx", delete=False) as tmp:
        ndx = tmp.name
    try:
        proc = subprocess.run(
            [gmx, "make_ndx", "-f", gro, "-o", ndx],
            input="q\n",
            text=True,
            capture_output=True,
            cwd=cwd,
        )
        text = (proc.stdout or "") + (proc.stderr or "")
        if proc.returncode != 0:
            raise RuntimeError(f"make_ndx başarısız:\n{text}")
        return parse_groups(text)
    finally:
        Path(ndx).unlink(missing_ok=True)


def find_group(groups: dict[int, str], *candidates: str) -> int:
    for cand in candidates:
        c = cand.lower()
        for nr, name in groups.items():
            n = name.lower()
            if n == c or n.startswith(c):
                return nr
    raise KeyError(f"Grup bulunamadı: {candidates} (mevcut: {groups})")


def run_make_ndx(
    gmx: str,
    gro: str,
    ndx_out: str,
    commands: str,
    cwd: str | None = None,
    ndx_in: str | None = None,
) -> str:
    cmd = [gmx, "make_ndx", "-f", gro, "-o", ndx_out]
    if ndx_in:
        cmd.extend(["-n", ndx_in])
    proc = subprocess.run(
        cmd,
        input=commands if commands.endswith("\n") else commands + "\n",
        text=True,
        capture_output=True,
        cwd=cwd,
    )
    text = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0:
        raise RuntimeError(f"make_ndx başarısız:\n{text}")
    return text


def last_made_group(text: str) -> int | None:
    found = re.findall(r"Made group\s+(\d+):", text)
    if found:
        return int(found[-1])
    # OR-merge sonrası: " NN Name : M atoms" — etkileşimli bölüm help metninden sonra gelir
    marker = "'q': save and quit"
    post = text.split(marker)[-1] if marker in text else text
    groups = re.findall(
        r"^\s*(\d+)\s+\S+\s*:\s*\d+\s*atoms",
        post,
        re.MULTILINE,
    )
    return int(groups[-1]) if groups else None


def group_number_for_name(text: str, name: str) -> int | None:
    for line in text.splitlines():
        m = re.match(rf"^\s*(\d+)\s+{re.escape(name)}\s", line)
        if m:
            return int(m.group(1))
    return None


def make_ligand_heavy_index(gmx: str, ligand_gro: str, ndx_out: str, cwd: str | None = None) -> int:
    out = run_make_ndx(gmx, ligand_gro, ndx_out, "0 & ! a H*\nq\n", cwd)
    nr = last_made_group(out)
    if nr is not None:
        return nr
    groups = list_groups(gmx, ligand_gro, cwd)
    return max(groups) if groups else 0


def make_complex_index(
    gmx: str,
    gro: str,
    ndx_out: str,
    lig_resname: str,
    grp_protein_lig: str,
    grp_water_ions: str,
    cwd: str | None = None,
    metal_resname: str | None = None,
) -> None:
    # em.gro atom sırası: Protein (1–4033) | ligand | ZN | su — grup numaraları
    # make_ndx listesinden alınmalı; ara ndx yazımı numaraları kaydırır.
    groups = list_groups(gmx, gro, cwd)
    protein_nr = find_group(groups, "Protein", "Protein_chain_A")
    lig_nr = find_group(groups, lig_resname)

    union_parts = [str(protein_nr)]
    if metal_resname:
        metal_nr = find_group(groups, metal_resname, metal_resname.upper())
        union_parts.append(str(metal_nr))
    union_parts.append(str(lig_nr))
    union = " | ".join(dict.fromkeys(union_parts))

    out = run_make_ndx(gmx, gro, ndx_out, f"{union}\nq\n", cwd)
    pl_nr = last_made_group(out)
    if pl_nr is None:
        raise RuntimeError(f"Birleşik grup oluşturulamadı: {union}")

    out2 = run_make_ndx(
        gmx, gro, ndx_out,
        f"name {pl_nr} {grp_protein_lig}\n! {pl_nr}\nq\n",
        cwd, ndx_in=ndx_out,
    )
    wi_nr = last_made_group(out2)
    if wi_nr is None:
        raise RuntimeError(f"Solvent tümleyeni oluşturulamadı (! {pl_nr})")

    run_make_ndx(
        gmx, gro, ndx_out,
        f"name {wi_nr} {grp_water_ions}\nq\n",
        cwd, ndx_in=ndx_out,
    )
    print(f"OK: {ndx_out} ({grp_protein_lig}={pl_nr}, {grp_water_ions}={wi_nr})")


def sol_group_number(gmx: str, gro: str, cwd: str | None = None) -> int:
    groups = list_groups(gmx, gro, cwd)
    return find_group(groups, "SOL", "Water")


def read_ndx_file(ndx_path: str | Path) -> dict[str, int]:
    """index.ndx [ Group ] satırları → GROMACS stdin grup numarası (0-based)."""
    groups: dict[str, int] = {}
    idx = 0
    with open(ndx_path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = re.match(r"^\[\s*(.+?)\s*\]", line.strip())
            if m:
                groups[m.group(1).strip()] = idx
                idx += 1
    return groups


def resolve_ndx_group(groups: dict[str, int], *candidates: str) -> int:
    for cand in candidates:
        if not cand:
            continue
        if cand in groups:
            return groups[cand]
        cl = cand.lower()
        for name, nr in groups.items():
            if name.lower() == cl:
                return nr
    raise KeyError(f"Index grubu yok: {candidates} (mevcut: {sorted(groups)})")


def main() -> int:
    ap = argparse.ArgumentParser(description="GROMACS index yardımcıları")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p1 = sub.add_parser("list-groups")
    p1.add_argument("--gmx", default="gmx")
    p1.add_argument("gro")

    p2 = sub.add_parser("ligand-heavy")
    p2.add_argument("--gmx", default="gmx")
    p2.add_argument("ligand_gro")
    p2.add_argument("ndx_out")

    p3 = sub.add_parser("complex-index")
    p3.add_argument("--gmx", default="gmx")
    p3.add_argument("gro")
    p3.add_argument("ndx_out")
    p3.add_argument("--lig-resname", required=True)
    p3.add_argument("--grp-pl", required=True)
    p3.add_argument("--grp-wi", required=True)
    p3.add_argument("--metal-resname", default="")

    p4 = sub.add_parser("sol-group")
    p4.add_argument("--gmx", default="gmx")
    p4.add_argument("gro")

    p5 = sub.add_parser("list-ndx")
    p5.add_argument("ndx")

    p6 = sub.add_parser("group-num")
    p6.add_argument("ndx")
    p6.add_argument("names", nargs="+", help="Aday grup adları (ilk eşleşen)")

    args = ap.parse_args()
    if args.cmd == "list-groups":
        for k, v in sorted(list_groups(args.gmx, args.gro).items()):
            print(f"{k:4d} {v}")
    elif args.cmd == "ligand-heavy":
        print(make_ligand_heavy_index(args.gmx, args.ligand_gro, args.ndx_out))
    elif args.cmd == "complex-index":
        metal = args.metal_resname.strip() or None
        make_complex_index(
            args.gmx, args.gro, args.ndx_out,
            args.lig_resname, args.grp_pl, args.grp_wi,
            metal_resname=metal,
        )
    elif args.cmd == "sol-group":
        print(sol_group_number(args.gmx, args.gro))
    elif args.cmd == "list-ndx":
        for name, nr in read_ndx_file(args.ndx).items():
            print(f"{nr:4d} {name}")
    elif args.cmd == "group-num":
        groups = read_ndx_file(args.ndx)
        print(resolve_ndx_group(groups, *args.names))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
