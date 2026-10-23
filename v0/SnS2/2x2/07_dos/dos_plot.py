#!/usr/bin/env python3

# ============================================================
# dos_plot.py
#
# Usage: python3 dos_plot.py
# ============================================================

import numpy as np
from pathlib import Path
import matplotlib

matplotlib.use("Agg")

import matplotlib.pyplot as plt

PREFIX = "SnS2.2x2"

STAGE_DIR = Path(__file__).resolve().parent

DATA_FILE = STAGE_DIR / "results" / f"{PREFIX}.dos.dat"
PLOT_FILE = STAGE_DIR / "results" / f"{PREFIX}.dos.pdf"

# Plot settings
ENERGY_MIN_EV = -5.0
ENERGY_MAX_EV = 5.0
# Padding percentage 
X_PADDING = 0.05
Y_PADDING = 0.05
TITLE = "Density of States: SnS$_2 2x2$"


# Read the Fermi energy from the QE DOS header.
with DATA_FILE.open() as file:
    header = file.readline()

fermi_energy = float(header.split("EFermi =")[1].split("eV")[0])

# QE DOS:
# column 1 = energy (eV)
# column 2 = total DOS (states/eV)
# column 3 = integrated DOS
data = np.loadtxt(DATA_FILE, comments="#")

energy = data[:, 0] - fermi_energy
dos = data[:, 1]

x_padding = X_PADDING * (ENERGY_MAX_EV - ENERGY_MIN_EV)

x_min = ENERGY_MIN_EV - x_padding
x_max = ENERGY_MAX_EV + x_padding

visible = (energy >= x_min) & (energy <= x_max)
visible_dos = dos[visible]
y_padding = Y_PADDING * np.ptp(visible_dos)

y_min = visible_dos.min() - y_padding
y_max = visible_dos.max() + y_padding


fig, ax = plt.subplots(figsize=(15 / 2.54, 10 / 2.54))

ax.plot(
    energy,
    dos,
    color="navy",
    linewidth=1.8,
    label="Total DOS",
)

# The Fermi level is at zero after shifting the energy.
ax.vlines(
    0,
    y_min,
    y_max,
    color="red",
    linestyle="--",
    linewidth=1.2,
    label=f"Fermi Energy = {fermi_energy:.3f} eV",
)

ax.set_xlim(x_min, x_max)
ax.set_ylim(y_min, y_max)

ax.set_xlabel(r"Energy (eV)")
ax.set_ylabel("DOS (states/eV)")
ax.set_title(TITLE)

ax.legend(frameon=False)
ax.tick_params(direction="in", top=True, right=True)

fig.tight_layout()
fig.savefig(PLOT_FILE)
plt.close(fig)

print(f"Fermi energy: {fermi_energy:.6f} eV")
print(f"Plot: {PLOT_FILE}")
