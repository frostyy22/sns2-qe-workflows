#!/usr/bin/env python3

# ============================================================
# Bands.py
#
# Usage: from Bands import bndplot, get_bandgap
# ============================================================

# This was written by Levi Lentz for the Kolpak Group at MIT
# This is distributed under the MIT license
# Modified by QuantumNerd 13.Apr.2020

import numpy as np


def Symmetries(fstring):
    """Extract high-symmetry coordinates from the bands.x output."""
    coordinates = np.zeros(0)
    with open(fstring) as file:
        for line in file:
            if "high-symmetry" in line:
                coordinates = np.append(coordinates, float(line.split()[-1]))
    return coordinates


def bndplot(datafile, fermi, symmetryfile, subplot, **kwargs):
    """Plot the bands.x GNU data on an existing Matplotlib axis."""
    bool_shift_efermi = kwargs.get("shift_fermi", 0)
    color_bnd = kwargs.get("color", "black")
    line_bnd = kwargs.get("linestyle", "solid")

    data = np.loadtxt(datafile)
    x_values = np.unique(data[:, 0])
    band_count = len(data[data[:, 0] == x_values[1]])
    fermi = float(fermi)
    fermi_shift = fermi if bool_shift_efermi else 0

    bands = [np.zeros((len(x_values), 2)) for _ in range(band_count)]
    for i, x_value in enumerate(x_values):
        selected = data[data[:, 0] == x_value]
        for j in range(band_count):
            bands[j][i][0] = x_value
            bands[j][i][1] = selected[j][1]

    for band in bands:
        subplot.plot(
            band[:, 0],
            band[:, 1] - fermi_shift,
            color=color_bnd,
            linestyle=line_bnd,
        )

    if "legend" in kwargs:
        subplot.plot(
            [None],
            [None],
            color=color_bnd,
            linestyle=line_bnd,
            label=kwargs["legend"],
        )

    symmetry_points = Symmetries(symmetryfile)
    for point in symmetry_points:
        subplot.axvline(
            x=point,
            linestyle="dashed",
            color="black",
            alpha=0.75,
        )

    subplot.axhline(
        y=fermi - fermi_shift,
        color="red",
        linestyle="dotted",
    )
    subplot.set_xticks(symmetry_points)
    subplot.set_xticklabels([])

    if "name_k_points" in kwargs:
        labels = kwargs["name_k_points"]
        if len(labels) == len(symmetry_points):
            subplot.set_xticklabels(labels)

    if "range" in kwargs:
        subplot.set_ylim(kwargs["range"])

    subplot.set_xlim(x_values.min(), x_values.max())
    subplot.set_xlabel("High Symmetry Point")
    subplot.set_ylabel("Energy (eV)")

    if "legend" in kwargs:
        subplot.legend()


def get_bandgap(datafile, fermi):
    """Return the path-sampled band gap and band edges relative to Fermi."""
    data = np.loadtxt(datafile)
    x_values = np.unique(data[:, 0])
    energies = np.array([data[data[:, 0] == k, 1] for k in x_values])
    shifted_energies = energies - float(fermi)

    crosses_fermi = np.any(
        (shifted_energies.min(axis=0) <= 0.0)
        & (shifted_energies.max(axis=0) >= 0.0)
    )
    if crosses_fermi:
        raise ValueError("Band Crossing Fermi")

    vbm = shifted_energies[shifted_energies < 0.0].max()
    cbm = shifted_energies[shifted_energies > 0.0].min()
    band_gap = cbm - vbm

    return band_gap, vbm, cbm
