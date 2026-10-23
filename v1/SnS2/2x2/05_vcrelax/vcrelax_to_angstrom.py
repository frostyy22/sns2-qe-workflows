#!/usr/bin/env python3

# ============================================================
# vcrelax_to_angstrom.py
#
# Usage: python3 vcrelax_to_angstrom.py [QE_OUTPUT]
# ============================================================

"""Print the final QE vc-relax structure in angstrom for the SCF input."""

import sys
from pathlib import Path

from ase.io import read


stage = Path(__file__).resolve().parent
output = Path(sys.argv[1]) if len(sys.argv) > 1 else stage / "outputs/SnS2.2x2.paw.out"
text = output.read_text(errors="replace")
if "bfgs converged" not in text or "JOB DONE." not in text:
    raise SystemExit(f"Relaxation is not complete: {output}")

atoms = read(output, index=-1, format="espresso-out")
symbols = atoms.get_chemical_symbols()
if len(atoms) != 12 or symbols.count("Sn") != 4 or symbols.count("S") != 8:
    raise SystemExit("Expected 4 Sn and 8 S atoms in the final structure")

print("CELL_PARAMETERS angstrom")
for vector in atoms.cell:
    print(" ".join(f"{value:16.10f}" for value in vector))

print("\nATOMIC_POSITIONS angstrom")
for symbol, position in zip(symbols, atoms.positions):
    print(f"{symbol:2s} " + " ".join(f"{value:16.10f}" for value in position))
