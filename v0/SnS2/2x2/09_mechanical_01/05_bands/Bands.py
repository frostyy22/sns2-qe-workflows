#!/usr/bin/env python3

# ============================================================
# Bands.py
#
# Usage: from Bands import bndplot, get_band_edges
# ============================================================

import numpy as np


def Symmetries(fstring):
    """Extract path-vertex coordinates from the bands.x output."""
    coordinates = []
    with open(fstring) as file:
        for line in file:
            if "high-symmetry" in line:
                coordinates.append(float(line.split()[-1]))
    return np.asarray(coordinates)


def read_bands(datafile):
    """Return GNU path coordinates and a (k-point, band) energy array."""
    data = np.atleast_2d(np.loadtxt(datafile))
    if data.shape[1] != 2 or data.shape[0] < 2:
        raise ValueError(f"expected two-column band data in: {datafile}")
    if not np.isfinite(data).all():
        raise ValueError(f"non-finite band data found in: {datafile}")

    x_values = np.unique(data[:, 0])
    if len(x_values) < 2:
        raise ValueError(f"expected at least two k-points in: {datafile}")

    counts = [np.count_nonzero(data[:, 0] == x_value) for x_value in x_values]
    if len(set(counts)) != 1:
        raise ValueError(f"inconsistent band count across k-points in: {datafile}")

    energies = np.asarray(
        [data[data[:, 0] == x_value, 1] for x_value in x_values]
    )
    return x_values, energies


def bndplot(datafile, fermi, symmetryfile, subplot, **kwargs):
    """Plot the bands.x GNU data on an existing Matplotlib axis."""
    bool_shift_efermi = kwargs.get("shift_fermi", 0)
    color_bnd = kwargs.get("color", "black")
    line_bnd = kwargs.get("linestyle", "solid")
    alpha_bnd = kwargs.get("alpha", 1.0)

    x_values, energies = read_bands(datafile)
    fermi = float(fermi)
    fermi_shift = fermi if bool_shift_efermi else 0

    for band_index in range(energies.shape[1]):
        subplot.plot(
            x_values,
            energies[:, band_index] - fermi_shift,
            color=color_bnd,
            linestyle=line_bnd,
            linewidth=0.9,
            alpha=alpha_bnd,
        )

    symmetry_points = Symmetries(symmetryfile)
    for point in symmetry_points:
        subplot.axvline(
            x=point,
            linestyle="dashed",
            color="black",
            alpha=0.75,
            linewidth=0.8,
        )

    subplot.axhline(
        y=fermi - fermi_shift,
        color="red",
        linestyle="dotted",
        linewidth=1.0,
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


def get_edge_bands(datafile, occupied_band_count=52):
    """Return the occupied and empty edge-band dispersions along the path."""
    x_values, energies = read_bands(datafile)
    if energies.shape[1] <= occupied_band_count:
        raise ValueError(
            f"need at least {occupied_band_count + 1} bands in: {datafile}"
        )

    # Occupation is defined by electron count, not by the smeared Fermi level.
    sorted_energies = np.sort(energies, axis=1)
    valence = sorted_energies[:, occupied_band_count - 1]
    conduction = sorted_energies[:, occupied_band_count]

    return x_values, valence, conduction


def get_band_edges(datafile, occupied_band_count=52, tolerance=1.0e-6):
    """Return path-sampled band edges using the known occupied-band count."""
    x_values, valence, conduction = get_edge_bands(
        datafile,
        occupied_band_count,
    )

    vbm = float(np.max(valence))
    cbm = float(np.min(conduction))
    raw_gap = cbm - vbm

    vbm_indices = np.flatnonzero(np.abs(valence - vbm) <= tolerance)
    cbm_indices = np.flatnonzero(np.abs(conduction - cbm) <= tolerance)
    common_indices = np.intersect1d(vbm_indices, cbm_indices)

    if raw_gap <= tolerance:
        gap_character = "overlapping"
        band_gap = 0.0
    elif len(common_indices) > 0:
        gap_character = "direct"
        band_gap = raw_gap
    else:
        gap_character = "indirect"
        band_gap = raw_gap

    if gap_character == "direct":
        vbm_index = cbm_index = int(common_indices[0])
    else:
        vbm_index = int(vbm_indices[0])
        cbm_index = int(cbm_indices[0])

    return {
        "vbm": vbm,
        "cbm": cbm,
        "band_gap": float(band_gap),
        "gap_character": gap_character,
        "vbm_k_distance": float(x_values[vbm_index]),
        "cbm_k_distance": float(x_values[cbm_index]),
    }
