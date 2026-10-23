#!/usr/bin/env bash

# ============================================================
# scf_run.sh
#
# Usage: ./scf_run.sh
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RELAX_STAGE="$STAGE_DIR/../01_relax"

RELAX_RUN_NAME="SnS2.2x2.hex.paw.relax"
RUN_NAME="SnS2.2x2.hex.paw.scf"
MPI_PROCESSES=5

TEMPLATE="$STAGE_DIR/scf.template"
RELAX_OUTPUT="$RELAX_STAGE/outputs/${RELAX_RUN_NAME}.out"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

INPUT_DIR="$STAGE_DIR/inputs"
OUTPUT_DIR="$STAGE_DIR/outputs"
WORK_DIR="$STAGE_DIR/work/$RUN_NAME"

INPUT_FILE="$INPUT_DIR/${RUN_NAME}.in"
OUTPUT_FILE="$OUTPUT_DIR/${RUN_NAME}.out"
POSITIONS_FILE="$WORK_DIR/final_atomic_positions.dat"

if ! grep -q "JOB DONE." "$RELAX_OUTPUT" 2>/dev/null; then
    echo "[incomplete] relaxation is not complete: $RELAX_OUTPUT" >&2
    exit 1
fi

if ! grep -qi -E "bfgs converged|End of BFGS" "$RELAX_OUTPUT"; then
    echo "[incomplete] BFGS convergence not found: $RELAX_OUTPUT" >&2
    exit 1
fi

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_DIR"

tac "$RELAX_OUTPUT" | \
    sed -n '/End final coordinates/,/Begin final coordinates/ {
        /Begin final coordinates/q
        /final coordinates/!p
    }' | tac | \
    awk '
        /^ATOMIC_POSITIONS/ {
            if (toupper($0) !~ /ANGSTROM/) {
                exit 2
            }
            positions = 1
            next
        }
        positions && NF >= 4 {
            print
            count++
            if (count == 12) {
                exit
            }
        }
    ' > "$POSITIONS_FILE"

sed \
    -e "s|__PREFIX__|${RUN_NAME}|g" \
    -e "s|__OUTDIR__|${WORK_DIR}|g" \
    -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
    "$TEMPLATE" | \
awk -v positions_file="$POSITIONS_FILE" '
    $0 == "__ATOMIC_POSITIONS__" {
        while ((getline line < positions_file) > 0) {
            print line
        }
        close(positions_file)
        next
    }
    { print }
' > "$INPUT_FILE"

echo "[run] $RUN_NAME"

mpirun -np "$MPI_PROCESSES" pw.x -in "$INPUT_FILE" > "$OUTPUT_FILE" 2>&1

if ! grep -q "JOB DONE." "$OUTPUT_FILE"; then
    echo "[incomplete] $RUN_NAME; inspect: $OUTPUT_FILE" >&2
    exit 1
fi

if ! grep -q "convergence has been achieved in" "$OUTPUT_FILE"; then
    echo "[incomplete] SCF convergence marker not found: $OUTPUT_FILE" >&2
    exit 1
fi

echo "[done] $RUN_NAME"
