#!/usr/bin/env python3

# ============================================================
# bands_plot.py
#
# Usage: BANDS_METHOD=<cold|fixed> python3 bands_plot.py <CASE_LABEL> [CASE_LABEL ...]
# Example: BANDS_METHOD=fixed python3 bands_plot.py biaxial_0p0
# ============================================================

import csv
import os
import re
import sys
from pathlib import Path

import matplotlib
import numpy as np


matplotlib.use("Agg")

import matplotlib.pyplot as plt

from Bands import bndplot, get_band_edges, get_edge_bands


STAGE_DIR = Path(__file__).resolve().parent
RESULTS_DIR = STAGE_DIR / "results"
METHOD = os.environ.get("BANDS_METHOD", "fixed")
if METHOD not in ("cold", "fixed"):
    raise ValueError(f"unsupported band method: {METHOD}")
SUMMARY_FILE = RESULTS_DIR / f"{METHOD}.bands_results.csv"
COMPARISON_FILE = RESULTS_DIR / f"{METHOD}.bands_comparison.pdf"
GAP_FILE = RESULTS_DIR / f"{METHOD}.band_gap_vs_strain.pdf"
BAND_EDGES_FILE = RESULTS_DIR / f"{METHOD}.band_edges_vs_strain.pdf"
EDGE_BANDS_COMPARISON_FILE = (
    RESULTS_DIR / f"{METHOD}.band_edges_kpath_comparison.pdf"
)

ENERGY_RANGE = (-4, 4)
FIGURE_SIZE = (8, 6)
K_POINT_LABELS = [r"$\Gamma$", "M", "K", r"$\Gamma$"]
NORMALIZED_PATH_VERTICES = np.arange(len(K_POINT_LABELS), dtype=float)
POSITIVE_FIVE_COLOR = "#ff1744"
CASE_PATTERN = re.compile(r"^biaxial_(-?\d+)p(\d+)$")
SUMMARY_FIELDS = [
    "strain_percent",
    "case_label",
    "status",
    "fermi_energy_ev",
    "vbm_relative_to_fermi_ev",
    "cbm_relative_to_fermi_ev",
    "band_gap_ev",
    "gap_character",
    "vbm_k_distance",
    "cbm_k_distance",
    "bands_data_file",
    "plot_file",
]


def strain_from_case_label(case_label):
    match = CASE_PATTERN.fullmatch(case_label)
    if match is None:
        raise ValueError(f"invalid case label: {case_label}")
    return float(f"{match.group(1)}.{match.group(2)}")


def strain_text(strain_percent):
    return f"{strain_percent:+.1f}%"


def read_summary():
    with SUMMARY_FILE.open(newline="") as file:
        rows = list(csv.DictReader(file))
    if len(rows) != 7:
        raise ValueError(f"expected seven rows in: {SUMMARY_FILE}")
    return rows


def write_summary(rows):
    with SUMMARY_FILE.open("w", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        writer.writerows(rows)


def mark_band_edges(
    ax,
    record,
    marker_size,
    normalized=False,
    color="black",
):
    vbm_position = (
        record["normalized_vbm_k"] if normalized else record["vbm_k_distance"]
    )
    cbm_position = (
        record["normalized_cbm_k"] if normalized else record["cbm_k_distance"]
    )
    return ax.scatter(
        [vbm_position, cbm_position],
        [record["relative_vbm"], record["relative_cbm"]],
        s=marker_size,
        marker="o",
        facecolor=color,
        edgecolor=color,
        linewidth=0.8,
        alpha=0.75,
        zorder=5,
        label="Band-gap edges",
    )


def plot_case(record):
    plot_file = RESULTS_DIR / record["case_label"] / f"{METHOD}.bands.pdf"
    fig, ax = plt.subplots(figsize=FIGURE_SIZE)

    bndplot(
        record["data_file"],
        record["fermi_energy"],
        record["symmetry_file"],
        ax,
        shift_fermi=True,
        color="black",
        linestyle="solid",
        alpha=0.75,
        name_k_points=K_POINT_LABELS,
        range=ENERGY_RANGE,
    )
    edge_marker = mark_band_edges(ax, record, marker_size=30)

    ax.set_title(
        rf"Band Structure ({METHOD} occupations): hexagonal SnS$_2$ 2x2"
        "\n"
        rf"Biaxial strain = {strain_text(record['strain_percent'])}"
    )
    ax.set_ylabel(r"Energy relative to $E_F$ (eV)")
    ax.tick_params(direction="in", top=True, right=True)
    ax.legend(
        handles=[edge_marker],
        frameon=True,
        fancybox=False,
        framealpha=1.0,
        edgecolor="0.3",
        loc="upper right",
    )

    fig.tight_layout()
    fig.savefig(plot_file, bbox_inches="tight")
    plt.close(fig)

    print(f"[plot] {record['case_label']}: {plot_file}")


def plot_comparison(records):
    fig, axes = plt.subplots(2, 4, figsize=(16, 8), sharey=True)
    axes = axes.ravel()

    edge_marker = None
    for ax, record in zip(axes, records):
        bndplot(
            record["data_file"],
            record["fermi_energy"],
            record["symmetry_file"],
            ax,
            shift_fermi=True,
            color="black",
            linestyle="solid",
            alpha=0.75,
            name_k_points=K_POINT_LABELS,
            range=ENERGY_RANGE,
        )
        edge_marker = mark_band_edges(ax, record, marker_size=25)
        ax.set_title(strain_text(record["strain_percent"]))
        ax.set_xlabel("")
        ax.set_ylabel("")
        ax.tick_params(direction="in", top=True, right=True)

    unused_axes = axes[len(records) :]
    if len(unused_axes) > 0 and edge_marker is not None:
        legend_ax = unused_axes[0]
        legend_ax.axis("off")
        legend_ax.legend(
            handles=[edge_marker],
            frameon=True,
            fancybox=False,
            framealpha=1.0,
            edgecolor="0.3",
            loc="upper right",
        )
        for ax in unused_axes[1:]:
            ax.set_visible(False)

    fig.suptitle(
        rf"Band Structure Comparison ({METHOD} occupations): hexagonal SnS$_2$ 2x2"
    )
    fig.text(
        0.01,
        0.5,
        r"Energy relative to $E_F$ (eV)",
        va="center",
        rotation="vertical",
    )
    fig.text(0.5, 0.01, r"Path: $\Gamma$-M-K-$\Gamma$", ha="center")
    fig.tight_layout(rect=(0.03, 0.04, 1.0, 0.95))
    fig.savefig(COMPARISON_FILE, bbox_inches="tight")
    plt.close(fig)

    print(f"[comparison] {COMPARISON_FILE}")


def plot_band_gap(records):
    strain = np.asarray([record["strain_percent"] for record in records])
    band_gap = np.asarray([record["band_gap"] for record in records])

    fig, ax = plt.subplots(figsize=FIGURE_SIZE)
    ax.plot(strain, band_gap, color="navy", marker="o", linewidth=1.8)
    ax.set_xlabel("Biaxial strain (%)")
    ax.set_ylabel(r"Band Gap (eV)")
    ax.set_title(
        r"Band Gap Along $\Gamma$-M-K-$\Gamma$: hexagonal SnS$_2$ 2x2"
    )
    ax.tick_params(direction="in", top=True, right=True)
    ax.grid(alpha=0.25)

    fig.tight_layout()
    fig.savefig(GAP_FILE, bbox_inches="tight")
    plt.close(fig)

    print(f"[band-gap] {GAP_FILE}")


def plot_band_edges(records):
    strain = np.asarray([record["strain_percent"] for record in records])
    relative_vbm = np.asarray([record["relative_vbm"] for record in records])
    relative_cbm = np.asarray([record["relative_cbm"] for record in records])

    fig, ax = plt.subplots(figsize=FIGURE_SIZE)
    ax.plot(
        strain,
        relative_vbm,
        color="royalblue",
        marker="o",
        linewidth=1.8,
        label=r"VBM $- E_F$",
    )
    ax.plot(
        strain,
        relative_cbm,
        color="firebrick",
        marker="s",
        linewidth=1.8,
        label=r"CBM $- E_F$",
    )
    ax.axhline(
        0.0,
        color="black",
        linestyle="--",
        linewidth=1.0,
        label=r"Each case's $E_F = 0$",
    )
    ax.set_xlabel("Biaxial strain (%)")
    ax.set_ylabel(r"Energy relative to each case's $E_F$ (eV)")
    ax.set_title(
        r"Relative Band Edges Along $\Gamma$-M-K-$\Gamma$: hexagonal SnS$_2$ 2x2"
    )
    ax.tick_params(direction="in", top=True, right=True)
    ax.grid(alpha=0.25)
    ax.legend(frameon=False)

    fig.tight_layout()
    fig.savefig(BAND_EDGES_FILE, bbox_inches="tight")
    plt.close(fig)

    print(f"[band-edges] {BAND_EDGES_FILE}")


def plot_edge_bands_comparison(records):
    fig, ax = plt.subplots(figsize=FIGURE_SIZE)
    strain_handles = []
    edge_marker = None
    colors = plt.cm.coolwarm(np.linspace(0, 1, len(records)))

    for record, color in zip(records, colors):
        if record["case_label"] == "biaxial_5p0":
            color = POSITIVE_FIVE_COLOR

        valence_handle, = ax.plot(
            record["normalized_k_path"],
            record["relative_valence_band"],
            color=color,
            linestyle="solid",
            linewidth=1.4,
            alpha=0.75,
            label=strain_text(record["strain_percent"]),
        )
        ax.plot(
            record["normalized_k_path"],
            record["relative_conduction_band"],
            color=color,
            linestyle="dashed",
            linewidth=1.4,
            alpha=0.75,
        )
        edge_marker = mark_band_edges(
            ax,
            record,
            marker_size=30,
            normalized=True,
            color=color,
        )
        strain_handles.append(valence_handle)

    for vertex in NORMALIZED_PATH_VERTICES:
        ax.axvline(
            vertex,
            color="gray",
            linestyle="dotted",
            linewidth=0.8,
            alpha=0.7,
        )

    ax.axhline(
        0.0,
        color="black",
        linestyle="dotted",
        linewidth=1.0,
    )
    ax.set_xlim(NORMALIZED_PATH_VERTICES[0], NORMALIZED_PATH_VERTICES[-1])
    ax.set_ylim(ENERGY_RANGE)
    ax.set_xticks(NORMALIZED_PATH_VERTICES)
    ax.set_xticklabels(K_POINT_LABELS)
    ax.set_xlabel(r"Path: $\Gamma$-M-K-$\Gamma$")
    ax.set_ylabel(r"Energy relative to each case's $E_F$ (eV)")
    ax.set_title(r"Band-Edge Comparison: hexagonal SnS$_2$ 2x2")
    ax.tick_params(direction="in", top=True, right=True)

    strain_legend = ax.legend(
        handles=strain_handles,
        title="Biaxial strain",
        frameon=False,
        fontsize=8,
        ncol=2,
        loc="upper right",
    )
    ax.add_artist(strain_legend)

    valence_style, = ax.plot(
        [],
        [],
        color="black",
        linestyle="solid",
        linewidth=1.4,
        label="Band 52 (valence)",
    )
    conduction_style, = ax.plot(
        [],
        [],
        color="black",
        linestyle="dashed",
        linewidth=1.4,
        label="Band 53 (conduction)",
    )
    style_handles = [valence_style, conduction_style]
    if edge_marker is not None:
        style_handles.append(edge_marker)
    ax.legend(
        handles=style_handles,
        frameon=False,
        fontsize=8,
        loc="lower right",
    )

    fig.tight_layout()
    fig.savefig(EDGE_BANDS_COMPARISON_FILE, bbox_inches="tight")
    plt.close(fig)

    print(f"[edge-bands] {EDGE_BANDS_COMPARISON_FILE}")


def main(case_labels):
    rows = read_summary()
    rows_by_case = {row["case_label"]: row for row in rows}
    records = []

    for case_label in case_labels:
        row = rows_by_case.get(case_label)
        if row is None or row["status"] != "ready":
            continue

        try:
            data_file = STAGE_DIR / row["bands_data_file"]
            data_suffix = f".{METHOD}.bands.dat.gnu"
            if not data_file.name.endswith(data_suffix):
                raise ValueError(
                    f"unexpected {METHOD} band-data name: {data_file}"
                )
            run_name = data_file.name[: -len(".bands.dat.gnu")]
            symmetry_file = (
                STAGE_DIR / "outputs" / case_label / f"{run_name}.bandsx.out"
            )
            strain_percent = strain_from_case_label(case_label)
            fermi_energy = float(row["fermi_energy_ev"])
            edges = get_band_edges(data_file)
            x_values, valence_band, conduction_band = get_edge_bands(data_file)
            relative_vbm = edges["vbm"] - fermi_energy
            relative_cbm = edges["cbm"] - fermi_energy
            normalized_k_path = np.linspace(
                NORMALIZED_PATH_VERTICES[0],
                NORMALIZED_PATH_VERTICES[-1],
                len(x_values),
            )

            record = {
                "case_label": case_label,
                "strain_percent": strain_percent,
                "fermi_energy": fermi_energy,
                "data_file": data_file,
                "symmetry_file": symmetry_file,
                "band_gap": edges["band_gap"],
                "relative_vbm": relative_vbm,
                "relative_cbm": relative_cbm,
                "vbm_k_distance": edges["vbm_k_distance"],
                "cbm_k_distance": edges["cbm_k_distance"],
                "normalized_k_path": normalized_k_path,
                "normalized_vbm_k": float(
                    np.interp(
                        edges["vbm_k_distance"],
                        x_values,
                        normalized_k_path,
                    )
                ),
                "normalized_cbm_k": float(
                    np.interp(
                        edges["cbm_k_distance"],
                        x_values,
                        normalized_k_path,
                    )
                ),
                "relative_valence_band": valence_band - fermi_energy,
                "relative_conduction_band": conduction_band - fermi_energy,
            }
            plot_case(record)

            row["status"] = "complete"
            row["vbm_relative_to_fermi_ev"] = f"{relative_vbm:.8f}"
            row["cbm_relative_to_fermi_ev"] = f"{relative_cbm:.8f}"
            row["band_gap_ev"] = f"{edges['band_gap']:.8f}"
            row["gap_character"] = edges["gap_character"]
            row["vbm_k_distance"] = f"{edges['vbm_k_distance']:.8f}"
            row["cbm_k_distance"] = f"{edges['cbm_k_distance']:.8f}"
            records.append(record)
        except (OSError, ValueError) as error:
            row["status"] = "invalid_data"
            row["plot_file"] = ""
            print(f"[skip] {case_label}: {error}")

    records.sort(key=lambda record: record["strain_percent"])
    write_summary(rows)

    if records:
        plot_comparison(records)
        plot_band_gap(records)
        plot_band_edges(records)
        plot_edge_bands_comparison(records)
    else:
        print("[plot] no valid band cases")


if __name__ == "__main__":
    if len(sys.argv) == 1:
        raise SystemExit(f"Usage: {Path(sys.argv[0]).name} <CASE_LABEL> [...]")

    main(sys.argv[1:])
