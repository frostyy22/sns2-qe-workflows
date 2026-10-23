#!/usr/bin/env bash

# ============================================================
# bands_run_all.sh
#
# Usage: ./bands_run_all.sh [CASE_LABEL ...]
# Example: ./bands_run_all.sh biaxial_0p0 biaxial_3p0
# ============================================================

# With no arguments, uses: -5, +5, -3, +3, -1, +1, 0%.

set -u

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_RUNNER="$STAGE_DIR/bands_case_run.sh"
STRAIN_STAGE="$STAGE_DIR/../03_strain"
STRAIN_GENERATOR="$STRAIN_STAGE/generate_strain.py"
PYTHON="/home/frost/python_venvs/dft/bin/python"

shopt -s nullglob
zero_scf_inputs=("$STAGE_DIR"/../02_scf/inputs/*.in)
shopt -u nullglob

if [ "${#zero_scf_inputs[@]}" -ne 1 ]; then
    echo "[invalid] expected one zero-strain SCF input under: $STAGE_DIR/../02_scf/inputs" >&2
    exit 1
fi

zero_scf_input="${zero_scf_inputs[0]}"
zero_scf_name="$(basename "$zero_scf_input" .in)"

if [ "$#" -gt 0 ]; then
    known_cases="$("$PYTHON" "$STRAIN_GENERATOR" --case-labels)" || exit 1
    case_labels=""

    for case_label in "$@"; do
        if ! grep -Fxq "$case_label" <<< "$known_cases"; then
            echo "[invalid] unknown strain case: $case_label" >&2
            exit 1
        fi
        case_labels+="${case_label}"$'\n'
    done
else
    case_labels="$(
        "$PYTHON" "$STRAIN_GENERATOR" --case-labels-by-magnitude
    )" || exit 1
fi

while IFS= read -r case_label; do
    [ -n "$case_label" ] || continue

    if [ "$case_label" = "biaxial_0p0" ]; then
        scf_input="$zero_scf_input"
        scf_output="$STAGE_DIR/../02_scf/outputs/${zero_scf_name}.out"
        scf_work_dir="$STAGE_DIR/../02_scf/work/${zero_scf_name}"
    else
        scf_input="$STRAIN_STAGE/inputs/${case_label}/scf.in"
        scf_output="$STRAIN_STAGE/outputs/${case_label}/scf.out"
        scf_work_dir="$STRAIN_STAGE/work/${case_label}/scf"
    fi

    # Keep mpirun from consuming the outer loop's label stream.
    if ! "$CASE_RUNNER" \
        "$case_label" \
        "$scf_input" \
        "$scf_output" \
        "$scf_work_dir" </dev/null; then
        exit 1
    fi
done <<< "$case_labels"

echo "[done] band calculations completed"
