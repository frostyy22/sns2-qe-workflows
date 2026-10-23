#!/usr/bin/env bash

# ============================================================
# bands_run.sh
#
# Usage: ./bands_run.sh [SCF_WORK_DIR]
# ============================================================

set -e

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MPISIZE=5

QE_PREFIX="SnS2.2x2"
METHOD="fixed"
RUN_NAME="${QE_PREFIX}.${METHOD}"

BANDS_TEMPLATE="$STAGE_DIR/bands.template"
BANDSX_TEMPLATE="$STAGE_DIR/bandsx.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

SCF_WORK_DIR="${1:-$STAGE_DIR/../06_scf/work/$QE_PREFIX}"

if [[ ! -d "$SCF_WORK_DIR/${QE_PREFIX}.save" ]]; then
    echo "[missing] SCF save directory: $SCF_WORK_DIR/${QE_PREFIX}.save" >&2
    exit 1
fi

SCF_WORK_DIR="$(cd "$SCF_WORK_DIR" && pwd)"
SOURCE_SAVE_DIR="$SCF_WORK_DIR/${QE_PREFIX}.save"

INPUT_DIR="$STAGE_DIR/inputs/$METHOD"
OUTPUT_DIR="$STAGE_DIR/outputs/$METHOD"
RESULTS_DIR="$STAGE_DIR/results/$METHOD"
BANDS_WORK_DIR="$STAGE_DIR/work/$METHOD/bands"
BANDS_SAVE_DIR="$BANDS_WORK_DIR/${QE_PREFIX}.save"

BANDS_INPUT="$INPUT_DIR/${RUN_NAME}.bands.in"
BANDS_OUTPUT="$OUTPUT_DIR/${RUN_NAME}.bands.out"
BANDSX_INPUT="$INPUT_DIR/${RUN_NAME}.bandsx.in"
BANDSX_OUTPUT="$OUTPUT_DIR/${RUN_NAME}.bandsx.out"
BANDS_DATA_FILE="$RESULTS_DIR/${RUN_NAME}.bands.dat"
BANDS_GNU_FILE="${BANDS_DATA_FILE}.gnu"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$RESULTS_DIR" "$BANDS_WORK_DIR"

# Start every bands run from a fresh copy of the completed SCF dataset.
rm -rf -- "$BANDS_SAVE_DIR"
cp -a "$SOURCE_SAVE_DIR" "$BANDS_SAVE_DIR"
echo "[copy] fresh isolated SCF dataset"

sed \
    -e "s|__PREFIX__|${QE_PREFIX}|g" \
    -e "s|__OUTDIR__|${BANDS_WORK_DIR}|g" \
    -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
    "$BANDS_TEMPLATE" > "$BANDS_INPUT"

sed \
    -e "s|__PREFIX__|${QE_PREFIX}|g" \
    -e "s|__OUTDIR__|${BANDS_WORK_DIR}|g" \
    -e "s|__BANDS_DATA_FILE__|${BANDS_DATA_FILE}|g" \
    "$BANDSX_TEMPLATE" > "$BANDSX_INPUT"

echo "[run] ${RUN_NAME}.bands"

mpirun -np $MPISIZE pw.x -in "$BANDS_INPUT" > "$BANDS_OUTPUT" 2>&1

if grep -q "JOB DONE." "$BANDS_OUTPUT"; then
    echo "[done] ${RUN_NAME}.bands"
else
    echo "[incomplete] inspect: $BANDS_OUTPUT" >&2
    exit 1
fi

echo "[run] ${RUN_NAME}.bandsx"

mpirun -np 1 bands.x -in "$BANDSX_INPUT" > "$BANDSX_OUTPUT" 2>&1

if grep -q "JOB DONE." "$BANDSX_OUTPUT"; then
    echo "[done] ${RUN_NAME}.bandsx"
    echo "[results] $BANDS_DATA_FILE"
    echo "[results] $BANDS_GNU_FILE"
else
    echo "[incomplete] inspect: $BANDSX_OUTPUT" >&2
    exit 1
fi
