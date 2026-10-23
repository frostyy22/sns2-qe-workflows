#!/usr/bin/env bash

# ============================================================
# dos_run.sh
#
# Usage: ./dos_run.sh [SCF_WORK_DIR]
# ============================================================

set -e

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

MPISIZE=5

PREFIX="SnS2.2x2"
RUN_NAME="$PREFIX"

NSCF_TEMPLATE="$STAGE_DIR/nscf.template"
DOS_TEMPLATE="$STAGE_DIR/dos.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

SCF_WORK_DIR="${1:-$STAGE_DIR/../06_scf/work/$RUN_NAME}"

if [ ! -d "$SCF_WORK_DIR/${RUN_NAME}.save" ]; then
    echo "[missing] SCF save directory: $SCF_WORK_DIR/${RUN_NAME}.save" >&2
    exit 1
fi

SCF_WORK_DIR="$(cd "$SCF_WORK_DIR" && pwd)"
SOURCE_SAVE_DIR="$SCF_WORK_DIR/${RUN_NAME}.save"

INPUT_DIR="$STAGE_DIR/inputs"
OUTPUT_DIR="$STAGE_DIR/outputs"
RESULTS_DIR="$STAGE_DIR/results"
NSCF_WORK_DIR="$STAGE_DIR/work/$RUN_NAME/nscf"
NSCF_SAVE_DIR="$NSCF_WORK_DIR/${RUN_NAME}.save"

NSCF_INPUT="$INPUT_DIR/${RUN_NAME}.nscf.in"
NSCF_OUTPUT="$OUTPUT_DIR/${RUN_NAME}.nscf.out"
DOS_INPUT="$INPUT_DIR/${RUN_NAME}.dos.in"
DOS_OUTPUT="$OUTPUT_DIR/${RUN_NAME}.dos.out"
DOS_DATA_FILE="$RESULTS_DIR/${RUN_NAME}.dos.dat"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$RESULTS_DIR" "$NSCF_WORK_DIR"

COPY_SAVE_DIR="${NSCF_SAVE_DIR}.copying"

if [ -e "$COPY_SAVE_DIR" ]; then
    rm -rf -- "$COPY_SAVE_DIR"
fi

# Start every NSCF run from a fresh copy of the completed SCF dataset.
cp -a "$SOURCE_SAVE_DIR" "$COPY_SAVE_DIR"

if [ -e "$NSCF_SAVE_DIR" ]; then
    rm -rf -- "$NSCF_SAVE_DIR"
fi

mv "$COPY_SAVE_DIR" "$NSCF_SAVE_DIR"
echo "[copy] fresh isolated SCF dataset"

sed \
    -e "s|__PREFIX__|${RUN_NAME}|g" \
    -e "s|__OUTDIR__|${NSCF_WORK_DIR}|g" \
    -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
    "$NSCF_TEMPLATE" > "$NSCF_INPUT"

sed \
    -e "s|__PREFIX__|${RUN_NAME}|g" \
    -e "s|__OUTDIR__|${NSCF_WORK_DIR}|g" \
    -e "s|__DOS_DATA_FILE__|${DOS_DATA_FILE}|g" \
    "$DOS_TEMPLATE" > "$DOS_INPUT"

echo "[run] ${RUN_NAME}.nscf"

mpirun -np "$MPISIZE" pw.x -in "$NSCF_INPUT" > "$NSCF_OUTPUT" 2>&1

if grep -q "JOB DONE." "$NSCF_OUTPUT"; then
    echo "[done] ${RUN_NAME}.nscf"
else
    echo "[incomplete] inspect: $NSCF_OUTPUT" >&2
    exit 1
fi

echo "[run] ${RUN_NAME}.dos"

mpirun -np 1 dos.x -in "$DOS_INPUT" > "$DOS_OUTPUT" 2>&1

if grep -q "JOB DONE." "$DOS_OUTPUT"; then
    echo "[done] ${RUN_NAME}.dos"
    echo "[results] $DOS_DATA_FILE"
else
    echo "[incomplete] inspect: $DOS_OUTPUT" >&2
    exit 1
fi
