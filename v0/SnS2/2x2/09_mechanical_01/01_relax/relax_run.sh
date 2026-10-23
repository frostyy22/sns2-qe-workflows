#!/usr/bin/env bash

# ============================================================
# relax_run.sh
#
# Usage: ./relax_run.sh
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_NAME="SnS2.2x2.hex.relax"
MPI_PROCESSES=5

TEMPLATE="$STAGE_DIR/relax.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

INPUT_DIR="$STAGE_DIR/inputs"
OUTPUT_DIR="$STAGE_DIR/outputs"
WORK_DIR="$STAGE_DIR/work/$RUN_NAME"

INPUT_FILE="$INPUT_DIR/${RUN_NAME}.in"
OUTPUT_FILE="$OUTPUT_DIR/${RUN_NAME}.out"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_DIR"

sed \
    -e "s|__PREFIX__|${RUN_NAME}|g" \
    -e "s|__OUTDIR__|${WORK_DIR}|g" \
    -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
    "$TEMPLATE" > "$INPUT_FILE"

echo "[run] $RUN_NAME"

mpirun -np "$MPI_PROCESSES" pw.x -in "$INPUT_FILE" > "$OUTPUT_FILE" 2>&1

if ! grep -q "JOB DONE." "$OUTPUT_FILE"; then
    echo "[incomplete] $RUN_NAME; inspect: $OUTPUT_FILE" >&2
    exit 1
fi

if ! grep -qi -E "bfgs converged|End of BFGS" "$OUTPUT_FILE"; then
    echo "[incomplete] BFGS convergence not found: $OUTPUT_FILE" >&2
    exit 1
fi

echo "[done] $RUN_NAME"
