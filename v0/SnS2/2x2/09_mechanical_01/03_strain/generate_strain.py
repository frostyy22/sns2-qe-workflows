#!/usr/bin/env python3

# ============================================================
# generate_strain.py
#
# Usage: 
#   python3 generate_strain.py                            # Generate strain inputs
#   python3 generate_strain.py --case-labels              # List labels from -5% to +5%
# Example case labels:
#   biaxial_-5p0  (-5% strain)
#   biaxial_0p0   (0% strain)
#   biaxial_3p0   (+3% strain)
# ============================================================

import sys
from pathlib import Path


STAGE_DIR = Path(__file__).resolve().parent
REFERENCE_INPUT = STAGE_DIR.parent / "02_scf" / "scf.template"
TEMPLATE = STAGE_DIR / "relax.template"

BIAXIAL_STRAIN_PERCENT = [-5, -3, -1, 0, 1, 3, 5]


def value_label(value):
    return f"{value:.1f}".replace(".", "p")


if sys.argv[1:] in (["--case-labels"], ["--case-labels-by-magnitude"]):
    strain_values = BIAXIAL_STRAIN_PERCENT
    if sys.argv[1:] == ["--case-labels-by-magnitude"]:
        strain_values = sorted(
            strain_values,
            key=lambda strain: (-abs(strain), strain),
        )

    for strain_percent in strain_values:
        print(f"biaxial_{value_label(strain_percent)}")
    raise SystemExit

if sys.argv[1:]:
    raise SystemExit(
        f"Usage: {Path(sys.argv[0]).name} "
        "[--case-labels|--case-labels-by-magnitude]"
    )


def read_cell(lines):
    for index, line in enumerate(lines):
        if line.strip().upper().startswith("CELL_PARAMETERS"):
            if "ANGSTROM" not in line.upper():
                raise ValueError("reference CELL_PARAMETERS must be in angstrom")
            return [
                tuple(float(value) for value in lines[index + offset].split()[:3])
                for offset in range(1, 4)
            ]
    raise ValueError("CELL_PARAMETERS not found in reference input")


def format_cell(cell):
    return "\n".join(
        f"    {x: .10f}    {y: .10f}    {z: .10f}" for x, y, z in cell
    )


reference_lines = REFERENCE_INPUT.read_text().splitlines()
reference_cell = read_cell(reference_lines)
template = TEMPLATE.read_text()

inputs_dir = STAGE_DIR / "inputs"
outputs_dir = STAGE_DIR / "outputs"
work_dir = STAGE_DIR / "work"

case_count = 0

for strain_percent in BIAXIAL_STRAIN_PERCENT:
    if strain_percent == 0:
        continue

    factor = 1.0 + strain_percent / 100.0

    strained_cell = [
        tuple(component * factor for component in reference_cell[0]),
        tuple(component * factor for component in reference_cell[1]),
        reference_cell[2],
    ]

    run_label = f"biaxial_{value_label(strain_percent)}"
    prefix = f"SnS2.2x2.hex.{run_label}.relax"
    input_file = inputs_dir / run_label / "relax.in"

    input_file.parent.mkdir(parents=True, exist_ok=True)
    (outputs_dir / run_label).mkdir(parents=True, exist_ok=True)
    (work_dir / run_label / "relax").mkdir(parents=True, exist_ok=True)

    rendered = (
        template
        .replace("__PREFIX__", prefix)
        .replace("__OUTDIR__", f"./work/{run_label}/relax")
        .replace("__PSEUDO_DIR__", "../../../../../pp")
        .replace("__CELL_PARAMETERS__", format_cell(strained_cell))
    )
    input_file.write_text(rendered)

    case_count += 1
    print(f"[generated] {run_label}: strain={strain_percent:+.1f}%")

print(f"[total] {case_count} nonzero strain cases")
