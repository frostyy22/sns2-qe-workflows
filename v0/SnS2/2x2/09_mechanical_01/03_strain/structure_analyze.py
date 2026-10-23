#!/usr/bin/env python3

# ============================================================
# structure_analyze.py
#
# Usage: python3 structure_analyze.py
# ============================================================

"""Analyze Sn-S distances and S-Sn-S angles across the seven strain cases.

Read 0% geometry from 02_scf and nonzero geometries from 03_strain.
Per Sn, minimum-image distance ranks 1-6 are nearest_6 and ranks 7-8
are remaining_2. Angles among nearest_6 are ranked into lower cis (1-6),
upper cis (7-12), and trans (13-15). No distance or angle cutoffs are used.
"""

import csv
import re
import subprocess
import sys
from itertools import combinations
from pathlib import Path
from statistics import fmean, pstdev

try:
    from ase.io import read
except ModuleNotFoundError as error:
    raise SystemExit(
        "ASE is required. Activate a Python environment containing ASE "
        "before running structure_analyze.py."
    ) from error


STAGE_DIR = Path(__file__).resolve().parent
ZERO_SCF_STAGE = STAGE_DIR.parent / "02_scf"
STRAIN_GENERATOR = STAGE_DIR / "generate_strain.py"
RESULTS_DIR = STAGE_DIR / "results"
MEASUREMENTS_FILE = RESULTS_DIR / "structure_measurements.csv"
SUMMARY_FILE = RESULTS_DIR / "structure_summary.csv"

ZERO_RUN_NAME = "SnS2.2x2.hex.scf"
EXPECTED_SN = 4
EXPECTED_S = 8
EXPECTED_CASE_COUNT = 7
NEAREST_S_COUNT = 6
REMAINING_S_COUNT = 2
EXPECTED_ANGLES_PER_SN = 15
EXPECTED_ANGLES_PER_CASE = EXPECTED_SN * EXPECTED_ANGLES_PER_SN
EXPECTED_CIS_LOWER_ANGLES_PER_SN = 6
EXPECTED_CIS_UPPER_ANGLES_PER_SN = 6
EXPECTED_TRANS_ANGLES_PER_SN = 3
EXPECTED_CIS_ANGLES_PER_SN = (
    EXPECTED_CIS_LOWER_ANGLES_PER_SN + EXPECTED_CIS_UPPER_ANGLES_PER_SN
)
EXPECTED_CIS_LOWER_ANGLES_PER_CASE = (
    EXPECTED_SN * EXPECTED_CIS_LOWER_ANGLES_PER_SN
)
EXPECTED_CIS_UPPER_ANGLES_PER_CASE = (
    EXPECTED_SN * EXPECTED_CIS_UPPER_ANGLES_PER_SN
)
EXPECTED_TRANS_ANGLES_PER_CASE = EXPECTED_SN * EXPECTED_TRANS_ANGLES_PER_SN
IDEAL_CIS_ANGLE_DEGREES = 90.0

CASE_PATTERN = re.compile(r"^biaxial_(-?\d+)p(\d+)$")

MEASUREMENT_FIELDS = [
    "case_label",
    "strain_percent",
    "category",
    "measurement",
    "center_id",
    "atom1_id",
    "atom2_id",
    "rank",
    "distance_group",
    "angle_group",
    "value",
    "unit",
]

SUMMARY_FIELDS = [
    "case_label",
    "strain_percent",
    "category",
    "metric",
    "value",
    "unit",
]


def strain_from_case_label(case_label):
    match = CASE_PATTERN.fullmatch(case_label)
    if match is None:
        raise ValueError(f"invalid case label: {case_label}")
    return float(f"{match.group(1)}.{match.group(2)}")


def generated_case_labels():
    result = subprocess.run(
        [sys.executable, str(STRAIN_GENERATOR), "--case-labels"],
        check=True,
        capture_output=True,
        text=True,
    )
    labels = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if (
        len(labels) != EXPECTED_CASE_COUNT
        or len(set(labels)) != EXPECTED_CASE_COUNT
    ):
        raise ValueError(
            "strain generator did not return "
            f"{EXPECTED_CASE_COUNT} unique cases"
        )
    return labels


def case_paths(case_label):
    if case_label == "biaxial_0p0":
        return (
            ZERO_SCF_STAGE / "inputs" / f"{ZERO_RUN_NAME}.in",
            ZERO_SCF_STAGE / "outputs" / f"{ZERO_RUN_NAME}.out",
        )
    return (
        STAGE_DIR / "inputs" / case_label / "scf.in",
        STAGE_DIR / "outputs" / case_label / "scf.out",
    )


def validate_case_files(input_file, output_file):
    if not input_file.is_file():
        raise ValueError(f"SCF input not found: {input_file}")
    if not output_file.is_file():
        raise ValueError(f"SCF output not found: {output_file}")

    output_text = output_file.read_text(errors="replace")
    if "JOB DONE." not in output_text:
        raise ValueError(f"JOB DONE. not found: {output_file}")
    if "convergence NOT achieved" in output_text:
        raise ValueError(f"SCF convergence failure found: {output_file}")


def read_structure(input_file):
    atoms = read(input_file, format="espresso-in")
    symbols = atoms.get_chemical_symbols()
    sn_indices = [index for index, symbol in enumerate(symbols) if symbol == "Sn"]
    s_indices = [index for index, symbol in enumerate(symbols) if symbol == "S"]
    if len(sn_indices) != EXPECTED_SN or len(s_indices) != EXPECTED_S:
        raise ValueError(
            f"expected {EXPECTED_SN} Sn and {EXPECTED_S} S atoms, found "
            f"{len(sn_indices)} Sn and {len(s_indices)} S"
        )
    return atoms, sn_indices, s_indices


def ranked_distances(case_label, strain_percent, atoms, sn_indices, s_indices):
    rows = []
    for sn_index in sn_indices:
        distances = atoms.get_distances(sn_index, s_indices, mic=True)
        ranked_s = sorted(
            zip(s_indices, distances),
            key=lambda item: (float(item[1]), item[0]),
        )
        for rank, (s_index, distance) in enumerate(ranked_s, start=1):
            rows.append(
                {
                    "case_label": case_label,
                    "strain_percent": strain_percent,
                    "category": "distance",
                    "measurement": "sn_s_distance",
                    "center_id": sn_index + 1,
                    "atom1_id": s_index + 1,
                    "atom2_id": "",
                    "rank": rank,
                    "distance_group": (
                        "nearest_6"
                        if rank <= NEAREST_S_COUNT
                        else "remaining_2"
                    ),
                    "angle_group": "",
                    "value": float(distance),
                    "unit": "angstrom",
                }
            )
    return rows


def nearest_s_angles(case_label, strain_percent, atoms, distance_rows):
    rows = []
    sn_ids = sorted({row["center_id"] for row in distance_rows})

    for sn_id in sn_ids:
        sn_angle_rows = []
        nearest_rows = sorted(
            (
                row
                for row in distance_rows
                if row["center_id"] == sn_id
                and row["distance_group"] == "nearest_6"
            ),
            key=lambda row: row["rank"],
        )
        if len(nearest_rows) != NEAREST_S_COUNT:
            raise ValueError(
                f"Sn atom {sn_id} does not have "
                f"{NEAREST_S_COUNT} nearest S atoms"
            )

        s_ids = sorted(row["atom1_id"] for row in nearest_rows)
        if len(set(s_ids)) != NEAREST_S_COUNT:
            raise ValueError(
                f"Sn atom {sn_id} has duplicate nearest S atom IDs"
            )

        sn_angle_count = 0
        for atom1_id, atom2_id in combinations(s_ids, 2):
            angle = atoms.get_angle(
                atom1_id - 1,
                sn_id - 1,
                atom2_id - 1,
                mic=True,
            )
            sn_angle_rows.append(
                {
                    "case_label": case_label,
                    "strain_percent": strain_percent,
                    "category": "angle",
                    "measurement": "s_sn_s_angle",
                    "center_id": sn_id,
                    "atom1_id": atom1_id,
                    "atom2_id": atom2_id,
                    "rank": None,
                    "distance_group": "nearest_6",
                    "angle_group": None,
                    "value": float(angle),
                    "unit": "degree",
                }
            )
            sn_angle_count += 1

        if sn_angle_count != EXPECTED_ANGLES_PER_SN:
            raise ValueError(
                f"Sn atom {sn_id} has {sn_angle_count} angles; "
                f"expected {EXPECTED_ANGLES_PER_SN}"
            )

        sn_angle_rows.sort(
            key=lambda row: (
                row["value"],
                row["atom1_id"],
                row["atom2_id"],
            )
        )
        for rank, row in enumerate(sn_angle_rows, start=1):
            row["rank"] = rank
            if rank <= EXPECTED_CIS_LOWER_ANGLES_PER_SN:
                row["angle_group"] = "cis_lower"
            elif rank <= EXPECTED_CIS_ANGLES_PER_SN:
                row["angle_group"] = "cis_upper"
            else:
                row["angle_group"] = "trans"
        rows.extend(sn_angle_rows)

    if len(rows) != EXPECTED_ANGLES_PER_CASE:
        raise ValueError(
            f"case has {len(rows)} S-Sn-S angles; "
            f"expected {EXPECTED_ANGLES_PER_CASE}"
        )

    return rows


def summarize_distances(case_label, strain_percent, rows):
    nearest_distances = []
    rank_gaps = []
    sn_ids = sorted({row["center_id"] for row in rows})

    for sn_id in sn_ids:
        sn_rows = sorted(
            (row for row in rows if row["center_id"] == sn_id),
            key=lambda row: row["rank"],
        )
        expected_ranks = list(range(1, EXPECTED_S + 1))
        if [row["rank"] for row in sn_rows] != expected_ranks:
            raise ValueError(f"Sn atom {sn_id} does not have ranks 1-8")

        expected_groups = (
            ["nearest_6"] * NEAREST_S_COUNT
            + ["remaining_2"] * REMAINING_S_COUNT
        )
        if [row["distance_group"] for row in sn_rows] != expected_groups:
            raise ValueError(f"Sn atom {sn_id} does not have a 6+2 rank split")

        distances = [row["value"] for row in sn_rows]
        nearest = distances[:NEAREST_S_COUNT]
        remaining = distances[NEAREST_S_COUNT:]
        if (
            len(nearest) != NEAREST_S_COUNT
            or len(remaining) != REMAINING_S_COUNT
        ):
            raise ValueError(f"Sn atom {sn_id} does not have a 6+2 rank split")

        nearest_distances.extend(nearest)
        rank_gaps.append(remaining[0] - nearest[-1])

    expected_bond_count = EXPECTED_SN * NEAREST_S_COUNT
    if len(nearest_distances) != expected_bond_count:
        raise ValueError(
            f"expected {expected_bond_count} nearest_6 "
            "distances, "
            f"found {len(nearest_distances)}"
        )

    return {
        "case_label": case_label,
        "strain_percent": strain_percent,
        "mean_angstrom": fmean(nearest_distances),
        "std_angstrom": pstdev(nearest_distances),
        "minimum_gap_angstrom": min(rank_gaps),
    }


def summarize_angles(case_label, strain_percent, rows):
    sn_ids = sorted({row["center_id"] for row in rows})
    if len(sn_ids) != EXPECTED_SN:
        raise ValueError(
            f"case has angles for {len(sn_ids)} Sn atoms; "
            f"expected {EXPECTED_SN}"
        )

    sn_bond_angle_variances = []
    case_angles = {
        "cis_lower": [],
        "cis_upper": [],
        "trans": [],
    }
    expected_groups = (
        ["cis_lower"] * EXPECTED_CIS_LOWER_ANGLES_PER_SN
        + ["cis_upper"] * EXPECTED_CIS_UPPER_ANGLES_PER_SN
        + ["trans"] * EXPECTED_TRANS_ANGLES_PER_SN
    )

    for sn_id in sn_ids:
        sn_rows = sorted(
            (row for row in rows if row["center_id"] == sn_id),
            key=lambda row: row["rank"],
        )
        if [row["rank"] for row in sn_rows] != list(
            range(1, EXPECTED_ANGLES_PER_SN + 1)
        ):
            raise ValueError(f"Sn atom {sn_id} does not have angle ranks 1-15")
        if [row["angle_group"] for row in sn_rows] != expected_groups:
            raise ValueError(
                f"Sn atom {sn_id} does not have the expected "
                "6 lower-cis + 6 upper-cis + 3 trans rank grouping"
            )

        sn_angles = {
            group: [
                row["value"]
                for row in sn_rows
                if row["angle_group"] == group
            ]
            for group in case_angles
        }
        if (
            len(sn_angles["cis_lower"])
            != EXPECTED_CIS_LOWER_ANGLES_PER_SN
        ):
            raise ValueError(
                f"Sn atom {sn_id} has "
                f"{len(sn_angles['cis_lower'])} lower-cis angles; "
                f"expected {EXPECTED_CIS_LOWER_ANGLES_PER_SN}"
            )
        if (
            len(sn_angles["cis_upper"])
            != EXPECTED_CIS_UPPER_ANGLES_PER_SN
        ):
            raise ValueError(
                f"Sn atom {sn_id} has "
                f"{len(sn_angles['cis_upper'])} upper-cis angles; "
                f"expected {EXPECTED_CIS_UPPER_ANGLES_PER_SN}"
            )
        if len(sn_angles["trans"]) != EXPECTED_TRANS_ANGLES_PER_SN:
            raise ValueError(
                f"Sn atom {sn_id} has "
                f"{len(sn_angles['trans'])} trans angles; "
                f"expected {EXPECTED_TRANS_ANGLES_PER_SN}"
            )

        cis_angles = sn_angles["cis_lower"] + sn_angles["cis_upper"]
        bond_angle_variance = sum(
            (angle - IDEAL_CIS_ANGLE_DEGREES) ** 2
            for angle in cis_angles
        ) / (EXPECTED_CIS_ANGLES_PER_SN - 1)
        sn_bond_angle_variances.append(bond_angle_variance)
        for group, angles in sn_angles.items():
            case_angles[group].extend(angles)

    expected_case_counts = {
        "cis_lower": EXPECTED_CIS_LOWER_ANGLES_PER_CASE,
        "cis_upper": EXPECTED_CIS_UPPER_ANGLES_PER_CASE,
        "trans": EXPECTED_TRANS_ANGLES_PER_CASE,
    }
    for group, expected_count in expected_case_counts.items():
        actual_count = len(case_angles[group])
        if actual_count != expected_count:
            raise ValueError(
                f"case has {actual_count} {group} angles; "
                f"expected {expected_count}"
            )
    classified_count = sum(len(angles) for angles in case_angles.values())
    if classified_count != EXPECTED_ANGLES_PER_CASE:
        raise ValueError(
            f"case has {classified_count} classified "
            f"angles; expected {EXPECTED_ANGLES_PER_CASE}"
        )

    return {
        "case_label": case_label,
        "strain_percent": strain_percent,
        "cis_lower_mean_degree": fmean(case_angles["cis_lower"]),
        "cis_lower_std_degree": pstdev(case_angles["cis_lower"]),
        "cis_upper_mean_degree": fmean(case_angles["cis_upper"]),
        "cis_upper_std_degree": pstdev(case_angles["cis_upper"]),
        "trans_mean_degree": fmean(case_angles["trans"]),
        "trans_std_degree": pstdev(case_angles["trans"]),
        "bond_angle_variance_degree2": fmean(sn_bond_angle_variances),
    }


def distance_summary_rows(case_summary):
    metrics = [
        (
            "sn_s_nearest_6_mean",
            case_summary["mean_angstrom"],
        ),
        (
            "sn_s_nearest_6_std",
            case_summary["std_angstrom"],
        ),
        (
            "sn_s_rank_7_minus_6_min",
            case_summary["minimum_gap_angstrom"],
        ),
    ]
    return [
        {
            "case_label": case_summary["case_label"],
            "strain_percent": case_summary["strain_percent"],
            "category": "distance",
            "metric": metric,
            "value": value,
            "unit": "angstrom",
        }
        for metric, value in metrics
    ]


def angle_summary_rows(case_summary):
    metrics = [
        (
            "s_sn_s_cis_lower_mean",
            case_summary["cis_lower_mean_degree"],
            "degree",
        ),
        (
            "s_sn_s_cis_lower_std",
            case_summary["cis_lower_std_degree"],
            "degree",
        ),
        (
            "s_sn_s_cis_upper_mean",
            case_summary["cis_upper_mean_degree"],
            "degree",
        ),
        (
            "s_sn_s_cis_upper_std",
            case_summary["cis_upper_std_degree"],
            "degree",
        ),
        (
            "s_sn_s_trans_mean",
            case_summary["trans_mean_degree"],
            "degree",
        ),
        (
            "s_sn_s_trans_std",
            case_summary["trans_std_degree"],
            "degree",
        ),
        (
            "s_sn_s_octahedral_bond_angle_variance",
            case_summary["bond_angle_variance_degree2"],
            "degree^2",
        ),
    ]
    return [
        {
            "case_label": case_summary["case_label"],
            "strain_percent": case_summary["strain_percent"],
            "category": "angle",
            "metric": metric,
            "value": value,
            "unit": unit,
        }
        for metric, value, unit in metrics
    ]


def strain_text(strain_percent):
    if strain_percent > 0:
        return f"{strain_percent:+.1f}"
    return f"{strain_percent:.1f}"


def print_distance_summary(case_summaries):
    header = (
        f"{'Case':<18}"
        f"{'Strain':>8}"
        f"{'Mean (Å)':>13}"
        f"{'Std (Å)':>12}"
        f"{'Min d7-d6 (Å)':>21}"
    )

    print("Sn-S distances (nearest_6):")
    print(header)
    print("-" * len(header))

    for summary in case_summaries:
        print(
            f"{summary['case_label']:<18}"
            f"{strain_text(summary['strain_percent']):>8}"
            f"{summary['mean_angstrom']:>13.6f}"
            f"{summary['std_angstrom']:>12.6f}"
            f"{summary['minimum_gap_angstrom']:>21.6f}"
        )
    print()


def print_angle_summary(case_summaries):
    header = (
        f"{'Strain':>8}"
        f"{'Cis lower (°)':>17}"
        f"{'Std (°)':>12}"
        f"{'Cis upper (°)':>17}"
        f"{'Std (°)':>12}"
        f"{'Trans (°)':>14}"
        f"{'Std (°)':>12}"
    )

    print("Angle:")
    print(header)
    print("-" * len(header))
    for summary in case_summaries:
        print(
            f"{strain_text(summary['strain_percent']):>8}"
            f"{summary['cis_lower_mean_degree']:>17.6f}"
            f"{summary['cis_lower_std_degree']:>12.6f}"
            f"{summary['cis_upper_mean_degree']:>17.6f}"
            f"{summary['cis_upper_std_degree']:>12.6f}"
            f"{summary['trans_mean_degree']:>14.6f}"
            f"{summary['trans_std_degree']:>12.6f}"
        )
    print()


def write_measurements(rows):
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    with MEASUREMENTS_FILE.open("w", newline="") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=MEASUREMENT_FIELDS,
            lineterminator="\n",
        )
        writer.writeheader()
        previous_group = None
        for row in rows:
            group = (
                row["case_label"],
                row["measurement"],
                row["center_id"],
            )
            if previous_group is not None and group != previous_group:
                file.write("\n")
            output_row = dict(row)
            output_row["strain_percent"] = f"{row['strain_percent']:.10g}"
            output_row["value"] = f"{row['value']:.10f}"
            writer.writerow(output_row)
            previous_group = group


def write_summary(rows):
    with SUMMARY_FILE.open("w", newline="") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=SUMMARY_FIELDS,
            lineterminator="\n",
        )
        writer.writeheader()
        for row in rows:
            output_row = dict(row)
            output_row["strain_percent"] = f"{row['strain_percent']:.10g}"
            output_row["value"] = f"{row['value']:.10f}"
            writer.writerow(output_row)


def main():
    if sys.argv[1:]:
        raise SystemExit(f"Usage: {Path(sys.argv[0]).name}")

    all_distance_measurements = []
    all_angle_measurements = []
    all_distance_summary_rows = []
    all_angle_summary_rows = []
    distance_case_summaries = []
    angle_case_summaries = []
    complete_count = 0
    skipped_count = 0

    for case_label in generated_case_labels():
        strain_percent = strain_from_case_label(case_label)
        input_file, output_file = case_paths(case_label)
        try:
            validate_case_files(input_file, output_file)
            atoms, sn_indices, s_indices = read_structure(input_file)
            rows = ranked_distances(
                case_label,
                strain_percent,
                atoms,
                sn_indices,
                s_indices,
            )
            distance_case_summary = summarize_distances(
                case_label,
                strain_percent,
                rows,
            )
            angles = nearest_s_angles(
                case_label,
                strain_percent,
                atoms,
                rows,
            )
            angle_case_summary = summarize_angles(
                case_label,
                strain_percent,
                angles,
            )
            all_distance_measurements.extend(rows)
            all_angle_measurements.extend(angles)
            all_distance_summary_rows.extend(
                distance_summary_rows(distance_case_summary)
            )
            all_angle_summary_rows.extend(
                angle_summary_rows(angle_case_summary)
            )
            distance_case_summaries.append(distance_case_summary)
            angle_case_summaries.append(angle_case_summary)
            complete_count += 1
        except (OSError, ValueError) as error:
            skipped_count += 1
            print(f"[invalid] {case_label}: {error}")

    write_measurements(all_distance_measurements + all_angle_measurements)
    write_summary(all_distance_summary_rows + all_angle_summary_rows)

    print_distance_summary(distance_case_summaries)
    print_angle_summary(angle_case_summaries)

    print(f"[results] {MEASUREMENTS_FILE.relative_to(STAGE_DIR)}")
    print(f"[results] {SUMMARY_FILE.relative_to(STAGE_DIR)}")
    print(f"[complete] {complete_count} case(s)")
    print(f"[skipped] {skipped_count} case(s)")

    if skipped_count:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
