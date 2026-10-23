#!/usr/bin/env bash

# ============================================================
# scf_run.sh
#
# Usage: ./scf_run.sh
# ============================================================

# Generate inputs with python3 generate_strain.py first.
# For this workflow, use ./scf_run.sh to run relaxation and SCF for all nonzero cases.
# Use ./relax_run.sh to run the relaxations separately.

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCF_TEMPLATE="$STAGE_DIR/scf.template"
MPI_PROCESSES=5

NAT="$(awk -F '=' '
    /^[[:space:]]*nat[[:space:]]*=/ {
        gsub(/[[:space:],]/, "", $2)
        print $2
        exit
    }
' "$SCF_TEMPLATE")"

if [ -z "$NAT" ]; then
    echo "[invalid] nat not found in: $SCF_TEMPLATE" >&2
    exit 1
fi

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
    input_dir="$(dirname "$input_file")"
    output_dir="$STAGE_DIR/outputs/$run_label"
    work_dir="$STAGE_DIR/work/$run_label"

    relax_output="$output_dir/relax.out"
    scf_input="$input_dir/scf.in"
    scf_output="$output_dir/scf.out"

    cell_file="$work_dir/cell_parameters.dat"
    geometry_file="$work_dir/final_geometry.dat"
    positions_file="$work_dir/atomic_positions.dat"

    mkdir -p "$output_dir" "$work_dir/relax" "$work_dir/scf"

    if grep -q "JOB DONE." "$relax_output" 2>/dev/null; then
        echo "[skip] $run_label relaxation"
    else
        echo "[run] $run_label relaxation"

        mpirun -np "$MPI_PROCESSES" pw.x -in "$input_file" \
            > "$relax_output" 2>&1
    fi

    if ! grep -q "JOB DONE." "$relax_output"; then
        echo "[incomplete] $run_label; inspect: $relax_output" >&2
        exit 1
    fi

    if ! grep -qi -E "bfgs converged|End of BFGS" "$relax_output"; then
        echo "[incomplete] BFGS convergence not found: $relax_output" >&2
        exit 1
    fi

    echo "[done] $run_label relaxation"

    awk '
        /^CELL_PARAMETERS/ {
            getline
            print
            getline
            print
            getline
            print
            exit
        }
    ' "$input_file" > "$cell_file"

    tac "$relax_output" | \
        sed -n '/End final coordinates/,/Begin final coordinates/ {
            /Begin final coordinates/q
            /final coordinates/!p
        }' | tac > "$geometry_file"

    awk -v nat="$NAT" '
        /^ATOMIC_POSITIONS/ {
            positions = 1
            next
        }
        positions && NF >= 4 {
            print
            count++
            if (count == nat) {
                exit
            }
        }
    ' "$geometry_file" > "$positions_file"

    position_count="$(wc -l < "$positions_file")"
    if [ "$position_count" -ne "$NAT" ]; then
        echo "[invalid] expected $NAT atomic positions, found $position_count: $positions_file" >&2
        exit 1
    fi

    scf_prefix="SnS2.2x2.hex.${run_label}.scf"

    sed \
        -e "s|__PREFIX__|${scf_prefix}|g" \
        -e "s|__OUTDIR__|./work/${run_label}/scf|g" \
        -e "s|__PSEUDO_DIR__|../../../../../pp|g" \
        "$SCF_TEMPLATE" | \
    awk -v cell_file="$cell_file" -v positions_file="$positions_file" '
        $0 == "__CELL_PARAMETERS__" {
            while ((getline line < cell_file) > 0) {
                print line
            }
            close(cell_file)
            next
        }
        $0 == "__ATOMIC_POSITIONS__" {
            while ((getline line < positions_file) > 0) {
                print line
            }
            close(positions_file)
            next
        }
        { print }
    ' > "$scf_input"

    if grep -q "JOB DONE." "$scf_output" 2>/dev/null; then
        echo "[skip] $run_label SCF"
    else
        echo "[run] $run_label SCF"

        mpirun -np "$MPI_PROCESSES" pw.x -in "$scf_input" \
            > "$scf_output" 2>&1
    fi

    if ! grep -q "JOB DONE." "$scf_output"; then
        echo "[incomplete] $run_label; inspect: $scf_output" >&2
        exit 1
    fi

    if ! grep -q "convergence has been achieved in" "$scf_output"; then
        echo "[incomplete] SCF convergence marker not found: $scf_output" >&2
        exit 1
    fi

    echo "[done] $run_label SCF"
done
