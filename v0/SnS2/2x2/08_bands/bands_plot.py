#!/usr/bin/env python3

# ============================================================
# bands_plot.py
#
# Usage: python3 bands_plot.py [cold|fixed]
# ============================================================

import re
import sys
from pathlib import Path

import matplotlib.pyplot as plt

from Bands import bndplot, get_bandgap


# Plot configuration
QE_PREFIX = "SnS2.2x2"
METHOD = sys.argv[1] if len(sys.argv) > 1 else "fixed"
if METHOD not in {"cold", "fixed"}:
    raise SystemExit("Usage: bands_plot.py [cold|fixed]")

PREFIX = f"{QE_PREFIX}.{METHOD}"
SHIFT_FERMI = True
ENERGY_RANGE = (-8, 8)
K_POINT_LABELS = [
    r"$\Gamma$",
    "M",
    "K",
    r"$\Gamma$",
]
TITLE = f"Band Structure: SnS$_2$ 2x2 ({METHOD})"

STAGE_DIR = Path(__file__).resolve().parent
DATA_FILE = STAGE_DIR / "results" / METHOD / f"{PREFIX}.bands.dat.gnu"
SYMMETRY_FILE = STAGE_DIR / "outputs" / METHOD / f"{PREFIX}.bandsx.out"
FIGURE_FILE = STAGE_DIR / "results" / METHOD / f"{PREFIX}.bands.pdf"
SCF_OUTPUT = STAGE_DIR / "../06_scf/outputs" / f"{QE_PREFIX}.out"


def read_fermi_energy(path):
    pattern = re.compile(
        r"the Fermi energy is\s+([-+]?(?:\d+(?:\.\d*)?|\.\d+))\s+ev",
        re.IGNORECASE,
    )
    value = None
    with path.open() as handle:
        for line in handle:
            match = pattern.search(line)
            if match:
                value = float(match.group(1))
    if value is None:
        raise ValueError(f"Fermi energy not found in {path}")
    return value


FERMI_ENERGY = read_fermi_energy(SCF_OUTPUT)

CALCULATE_BAND_GAP = True


fig, ax = plt.subplots(figsize=(8, 6))

bndplot(
    DATA_FILE,
    FERMI_ENERGY,
    SYMMETRY_FILE,
    ax,
    shift_fermi=SHIFT_FERMI,
    color="black",
    linestyle="solid",
    name_k_points=K_POINT_LABELS,
    range=ENERGY_RANGE,
)

ax.set_title(TITLE)

fig.tight_layout()
FIGURE_FILE.parent.mkdir(parents=True, exist_ok=True)
fig.savefig(FIGURE_FILE, bbox_inches="tight")

print(f"Fermi energy: {FERMI_ENERGY:.6f} eV")

if CALCULATE_BAND_GAP:
    band_gap, vbm, cbm = get_bandgap(DATA_FILE, FERMI_ENERGY)
    print(f"VBM: {vbm:.6f} eV")
    print(f"CBM: {cbm:.6f} eV")
    print(f"Band gap: {band_gap:.6f} eV")

plt.show()
