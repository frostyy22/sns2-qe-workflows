#!/usr/bin/env bash

# ============================================================
# dos_case_run.sh
#
# Usage: ./dos_case_run.sh <CASE_LABEL> <SCF_INPUT> <SCF_OUTPUT> <SCF_WORK_DIR>
# ============================================================

set -e

MPI_PROCESSES=5

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <CASE_LABEL> <SCF_INPUT> <SCF_OUTPUT> <SCF_WORK_DIR>" >&2
    exit 1
fi

CASE_LABEL="$1"
SCF_INPUT="$2"
SCF_OUTPUT="$3"
SCF_WORK_DIR="$4"

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NSCF_TEMPLATE="$STAGE_DIR/nscf.template"
DOS_TEMPLATE="$STAGE_DIR/dos.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

if [ ! -f "$SCF_INPUT" ]; then
    echo "[missing] SCF input: $SCF_INPUT" >&2
    exit 1
fi

if ! grep -q "JOB DONE." "$SCF_OUTPUT" 2>/dev/null; then
    echo "[incomplete] SCF is not complete: $SCF_OUTPUT" >&2
    exit 1
fi

if [ ! -d "$SCF_WORK_DIR" ]; then
    echo "[missing] SCF work directory: $SCF_WORK_DIR" >&2
    exit 1
fi

SCF_WORK_DIR="$(cd "$SCF_WORK_DIR" && pwd)"

shopt -s nullglob
save_dirs=("$SCF_WORK_DIR"/*.save)
shopt -u nullglob

if [ "${#save_dirs[@]}" -ne 1 ]; then
    echo "[invalid] expected one SCF .save directory under: $SCF_WORK_DIR" >&2
    exit 1
fi

SOURCE_SAVE_DIR="${save_dirs[0]}"
PREFIX="$(basename "$SOURCE_SAVE_DIR" .save)"
INPUT_PREFIX="$(awk -F= '
    /^[[:space:]]*prefix[[:space:]]*=/ {
        value = $2
        gsub(/[[:space:]\047\042,]/, "", value)
        print value
        exit
    }
' "$SCF_INPUT")"

if [ -z "$INPUT_PREFIX" ] || [ "$INPUT_PREFIX" != "$PREFIX" ]; then
    echo "[invalid] SCF input prefix does not match its .save directory: $SCF_INPUT" >&2
    exit 1
fi

INPUT_DIR="$STAGE_DIR/inputs/$CASE_LABEL"
OUTPUT_DIR="$STAGE_DIR/outputs/$CASE_LABEL"
RESULTS_DIR="$STAGE_DIR/results/$CASE_LABEL"
NSCF_WORK_DIR="$STAGE_DIR/work/$CASE_LABEL/nscf"
NSCF_SAVE_DIR="$NSCF_WORK_DIR/${PREFIX}.save"

STRUCTURE_FILE="$INPUT_DIR/structure.dat"
NSCF_INPUT="$INPUT_DIR/nscf.in"
NSCF_OUTPUT="$OUTPUT_DIR/nscf.out"
DOS_INPUT="$INPUT_DIR/dos.in"
DOS_OUTPUT="$OUTPUT_DIR/dos.out"
DOS_DATA_FILE="$RESULTS_DIR/dos.dat"

mkdir -p \
    "$INPUT_DIR" \
    "$OUTPUT_DIR" \
    "$RESULTS_DIR" \
    "$NSCF_WORK_DIR"

COPY_SAVE_DIR="${NSCF_SAVE_DIR}.copying"

if [ -e "$COPY_SAVE_DIR" ]; then
    rm -rf -- "$COPY_SAVE_DIR"
fi

cp -a "$SOURCE_SAVE_DIR" "$COPY_SAVE_DIR"

if [ -e "$NSCF_SAVE_DIR" ]; then
    rm -rf -- "$NSCF_SAVE_DIR"
fi

mv "$COPY_SAVE_DIR" "$NSCF_SAVE_DIR"
echo "[copy] $CASE_LABEL fresh isolated SCF dataset"

sed -n '
    /^[[:space:]]*CELL_PARAMETERS/,/^[[:space:]]*K_POINTS/ {
        /^[[:space:]]*K_POINTS/q
        p
    }
' "$SCF_INPUT" > "$STRUCTURE_FILE"

if ! grep -qi "^CELL_PARAMETERS.*angstrom" "$STRUCTURE_FILE" ||
    ! grep -qi "^ATOMIC_POSITIONS.*angstrom" "$STRUCTURE_FILE"; then
    echo "[invalid] Cartesian structure not found in: $SCF_INPUT" >&2
    exit 1
fi

atom_count="$(awk '
    /^ATOMIC_POSITIONS/ {
        positions = 1
        next
    }
    positions && NF >= 4 {
        count++
    }
    END {
        print count + 0
    }
' "$STRUCTURE_FILE")"

if [ "$atom_count" -ne 12 ]; then
    echo "[invalid] expected 12 Cartesian positions in: $SCF_INPUT" >&2
    exit 1
fi

sed \
    -e "s|__PREFIX__|${PREFIX}|g" \
    -e "s|__OUTDIR__|${NSCF_WORK_DIR}|g" \
    -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
    "$NSCF_TEMPLATE" | \
sed "/^__STRUCTURE__$/ {
    r $STRUCTURE_FILE
    d
}" > "$NSCF_INPUT"

sed \
    -e "s|__PREFIX__|${PREFIX}|g" \
    -e "s|__OUTDIR__|${NSCF_WORK_DIR}|g" \
    -e "s|__DOS_DATA_FILE__|${DOS_DATA_FILE}|g" \
    "$DOS_TEMPLATE" > "$DOS_INPUT"

if grep -q "__" "$NSCF_INPUT" "$DOS_INPUT"; then
    echo "[invalid] unresolved template marker for: $CASE_LABEL" >&2
    exit 1
fi

echo "[run] $CASE_LABEL nscf"

mpirun -np "$MPI_PROCESSES" pw.x -in "$NSCF_INPUT" \
    > "$NSCF_OUTPUT" 2>&1

if ! grep -q "JOB DONE." "$NSCF_OUTPUT"; then
    echo "[incomplete] $CASE_LABEL nscf; inspect: $NSCF_OUTPUT" >&2
    exit 1
fi

echo "[done] $CASE_LABEL nscf"
echo "[run] $CASE_LABEL dos"

mpirun -np 1 dos.x -in "$DOS_INPUT" > "$DOS_OUTPUT" 2>&1

if ! grep -q "JOB DONE." "$DOS_OUTPUT"; then
    echo "[incomplete] $CASE_LABEL dos; inspect: $DOS_OUTPUT" >&2
    exit 1
fi

if [ ! -s "$DOS_DATA_FILE" ]; then
    echo "[missing] $CASE_LABEL DOS data: $DOS_DATA_FILE" >&2
    exit 1
fi

echo "[done] $CASE_LABEL dos"
echo "[results] $DOS_DATA_FILE"
