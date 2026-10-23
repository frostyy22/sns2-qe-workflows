#!/usr/bin/env python3

# ============================================================
# dos_plot.py
#
# Usage: python3 dos_plot.py <CASE_LABEL> [CASE_LABEL ...]
# Example: python3 dos_plot.py biaxial_0p0 biaxial_3p0
# ============================================================

import re
import sys
from pathlib import Path

import matplotlib
import numpy as np


matplotlib.use("Agg")

import matplotlib.pyplot as plt


STAGE_DIR = Path(__file__).resolve().parent
RESULTS_DIR = STAGE_DIR / "results"
COMPARISON_FILE = RESULTS_DIR / "dos_comparison.pdf"

ENERGY_MIN_EV = -5.0
ENERGY_MAX_EV = 5.0
Y_PADDING = 0.05
FIGURE_SIZE = (15 / 2.54, 10 / 2.54)
INDIVIDUAL_FIGURE_SIZE = (15 / 2.54, 15 / 2.54)
COMPARISON_ALPHA = 0.75
POSITIVE_FIVE_COLOR = "#ff1744"

CASE_PATTERN = re.compile(r"^biaxial_(-?\d+)p(\d+)$")
FERMI_PATTERN = re.compile(
    r"EFermi\s*=\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[EeDd][-+]?\d+)?)"
)


def strain_from_case_label(case_label):
    match = CASE_PATTERN.fullmatch(case_label)
    if match is None:
        raise ValueError(f"invalid case label: {case_label}")
    return float(f"{match.group(1)}.{match.group(2)}")


def read_dos(data_file):
    fermi_energy = None

    with data_file.open() as file:
        for line in file:
            match = FERMI_PATTERN.search(line)
            if match is not None:
                fermi_energy = float(
                    match.group(1).replace("D", "E").replace("d", "e")
                )
                break

    if fermi_energy is None:
        raise ValueError(f"EFermi not found in: {data_file}")

    data = np.atleast_2d(np.loadtxt(data_file, comments="#"))

    if data.shape[1] < 3 or data.shape[0] < 2:
        raise ValueError(
            "expected energy, DOS, and integrated-DOS columns in: "
            f"{data_file}"
        )
    if not np.isfinite(data).all():
        raise ValueError(f"non-finite DOS values found in: {data_file}")

    energy = data[:, 0] - fermi_energy
    dos = data[:, 1]
    integrated_dos = data[:, 2]
    return fermi_energy, energy, dos, integrated_dos


def visible_y_limits(energy_arrays, dos_arrays):
    visible_values = []
    for energy, dos in zip(energy_arrays, dos_arrays):
        visible = (energy >= ENERGY_MIN_EV) & (energy <= ENERGY_MAX_EV)
        if not np.any(visible):
            raise ValueError("no DOS points inside the display window")
        visible_values.append(dos[visible])

    values = np.concatenate(visible_values)
    lower = float(np.min(values))
    upper = float(np.max(values))
    span = upper - lower
    padding = Y_PADDING * span if span > 0 else 1.0
    return lower - padding, upper + padding


def strain_text(strain_percent):
    return f"{strain_percent:+.1f}%"


def plot_case(record):
    plot_file = RESULTS_DIR / record["case_label"] / "dos.pdf"
    dos_y_limits = visible_y_limits([record["energy"]], [record["dos"]])
    integrated_y_limits = visible_y_limits(
        [record["energy"]],
        [record["integrated_dos"]],
    )

    fig, (dos_axis, integrated_axis) = plt.subplots(
        2,
        1,
        figsize=INDIVIDUAL_FIGURE_SIZE,
        sharex=True,
    )
    dos_axis.plot(
        record["energy"],
        record["dos"],
        color="navy",
        linewidth=1.8,
        label="Total DOS",
    )
    dos_axis.axvline(
        0,
        color="red",
        linestyle="--",
        linewidth=1.2,
        label=f"Fermi energy = {record['fermi_energy']:.3f} eV",
    )

    dos_axis.set_ylim(*dos_y_limits)
    dos_axis.set_ylabel("DOS (states/eV)")
    dos_axis.set_title(
        rf"Density of States: hexagonal SnS$_2$ 2x2, biaxial strain = "
        f"{strain_text(record['strain_percent'])}"
    )
    dos_axis.legend(frameon=False)
    dos_axis.tick_params(direction="in", top=True, right=True)

    integrated_axis.plot(
        record["energy"],
        record["integrated_dos"],
        color="darkgreen",
        linewidth=1.8,
        label="Integrated DOS",
    )
    integrated_axis.axvline(
        0,
        color="red",
        linestyle="--",
        linewidth=1.2,
    )
    integrated_axis.set_xlim(ENERGY_MIN_EV, ENERGY_MAX_EV)
    integrated_axis.set_ylim(*integrated_y_limits)
    integrated_axis.set_xlabel(r"Energy relative to $E_F$ (eV)")
    integrated_axis.set_ylabel("Integrated DOS (states)")
    integrated_axis.legend(frameon=False)
    integrated_axis.tick_params(direction="in", top=True, right=True)

    fig.tight_layout()
    fig.savefig(plot_file)
    plt.close(fig)
    print(f"[plot] {record['case_label']}: {plot_file}")


def plot_comparison(records):
    y_limits = visible_y_limits(
        [record["energy"] for record in records],
        [record["dos"] for record in records],
    )
    colors = plt.cm.coolwarm(np.linspace(0, 1, len(records)))

    fig, ax = plt.subplots(figsize=FIGURE_SIZE)

    for record, color in zip(records, colors):
        if record["case_label"] == "biaxial_5p0":
            color = POSITIVE_FIVE_COLOR

        ax.plot(
            record["energy"],
            record["dos"],
            color=color,
            linewidth=1.4,
            alpha=COMPARISON_ALPHA,
            label=strain_text(record["strain_percent"]),
        )

    ax.axvline(
        0,
        color="black",
        linestyle="--",
        linewidth=1.0,
        label=r"$E_F = 0$",
    )

    ax.set_xlim(ENERGY_MIN_EV, ENERGY_MAX_EV)
    ax.set_ylim(*y_limits)
    ax.set_xlabel(r"Energy relative to $E_F$ (eV)")
    ax.set_ylabel("DOS (states/eV)")
    ax.set_title(r"Density of States Comparison: hexagonal SnS$_2$ 2x2")
    ax.legend(
        title="Biaxial strain",
        frameon=False,
        fontsize=8,
        ncol=2,
    )
    ax.tick_params(direction="in", top=True, right=True)

    fig.tight_layout()
    fig.savefig(COMPARISON_FILE)
    plt.close(fig)

    print(f"[comparison] {COMPARISON_FILE}")


def main(case_labels):
    records = []

    for case_label in case_labels:
        fermi_energy, energy, dos, integrated_dos = read_dos(
            RESULTS_DIR / case_label / "dos.dat"
        )
        records.append(
            {
                "case_label": case_label,
                "strain_percent": strain_from_case_label(case_label),
                "fermi_energy": fermi_energy,
                "energy": energy,
                "dos": dos,
                "integrated_dos": integrated_dos,
            }
        )

    records.sort(key=lambda record: record["strain_percent"])
    for record in records:
        plot_case(record)

    plot_comparison(records)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        raise SystemExit(f"Usage: {Path(sys.argv[0]).name} <CASE_LABEL> [...]")

    main(sys.argv[1:])
