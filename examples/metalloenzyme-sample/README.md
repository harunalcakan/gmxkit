# Metalloenzyme sample (optional)

Copy into a **project folder** (not the install directory):

```bash
mkdir ~/projects/my-system
cp protein.pdb ligand.mol2 ~/projects/my-system/
cd ~/projects/my-system
gmxkit
```

For Zn + HSD prep, enable metalloenzyme in `gmxkit.env` — see `mdprep/profiles/ca2_6i0l_2q38.env`.

Set `LIG_RESNAME` and `CHECK_LIG_RESNAME` to match your ligand's mol2 / CGenFF residue name.
