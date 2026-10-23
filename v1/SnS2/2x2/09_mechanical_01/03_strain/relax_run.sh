#!/usr/bin/env bash

# ============================================================
# relax_run.sh
#
# Usage: ./relax_run.sh
# ============================================================

# For this workflow, use ./scf_run.sh to run relaxation and SCF for all nonzero cases.
# Use ./relax_run.sh to run the relaxations separately.

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MPI_PROCESSES=5

if [ ! -d "$STAGE_DIR/inputs" ]; then
    echo "[missing] generate the strain inputs first: python3 $STAGE_DIR/generate_strain.py" >&2
    exit 1
fi

cd "$STAGE_DIR"

case_labels="$(
    python3 "$STAGE_DIR/generate_strain.py" --case-labels-by-magnitude
)" || exit 1

input_files=()
for run_label in $case_labels; do
    if [ "$run_label" = "biaxial_0p0" ]; then
        continue
    fi

    input_file="$STAGE_DIR/inputs/$run_label/relax.in"
    if [ ! -f "$input_file" ]; then
        echo "[missing] strain input not found: $input_file" >&2
        exit 1
    fi

    input_files+=("$input_file")
done

for input_file in "${input_files[@]}"; do
    run_label="$(basename "$(dirname "$input_file")")"
    output_dir="$STAGE_DIR/outputs/$run_label"
    output_file="$output_dir/relax.out"
    work_dir="$STAGE_DIR/work/$run_label/relax"

    mkdir -p "$output_dir" "$work_dir"

    if grep -q "JOB DONE." "$output_file" 2>/dev/null; then
        echo "[skip] $run_label"
    else
        echo "[run] $run_label"

        mpirun -np "$MPI_PROCESSES" pw.x -in "$input_file" \
            > "$output_file" 2>&1
    fi

    if ! grep -q "JOB DONE." "$output_file"; then
        echo "[incomplete] $run_label; inspect: $output_file" >&2
        exit 1
    fi

    if ! grep -qi -E "bfgs converged|End of BFGS" "$output_file"; then
        echo "[incomplete] BFGS convergence not found: $output_file" >&2
        exit 1
    fi

    echo "[done] $run_label"
done
