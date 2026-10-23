#!/usr/bin/env bash

# ============================================================
# scf_run.sh
#
# Usage: ./scf_run.sh <TEMPLATE>
# Example: ./scf_run.sh scf.template
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX="SnS2.2x2"
RUN_NAME="$PREFIX"

MPISIZE=5

TEMPLATE="${1:?Usage: $0 <template>}"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../.." && pwd)"
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

mpirun -np $MPISIZE pw.x -in "$INPUT_FILE" > "$OUTPUT_FILE" 2>&1

if grep -q "JOB DONE." "$OUTPUT_FILE"; then
    echo "[done] $RUN_NAME"
else
    echo "[incomplete] $RUN_NAME; inspect: $OUTPUT_FILE"
fi
