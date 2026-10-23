#!/usr/bin/env bash

# ============================================================
# vac_run.sh
#
# Usage: ./vac_run.sh
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$STAGE_DIR/vac.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

PREFIX="SnS2.2x2.paw"

ECUTWFC=80
ECUTRHO=400
C_VALUES=(9 12 15 18 21 24)

MPISIZE=5

CASE_DIR="$STAGE_DIR/ecut_${ECUTWFC}_${ECUTRHO}_k6x6x1"
INPUT_DIR="$CASE_DIR/inputs"
OUTPUT_DIR="$CASE_DIR/outputs"
WORK_DIR="$CASE_DIR/work"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_DIR"

# ============================================================
# Run SCF calculations
# ============================================================
COUNTER=0
TOTAL_RUNS=${#C_VALUES[@]}

for C in "${C_VALUES[@]}"; do

    TAG="c${C}"
    COUNTER=$((COUNTER + 1))

    INPUT="$INPUT_DIR/${PREFIX}.${TAG}.in"
    OUTPUT="$OUTPUT_DIR/${PREFIX}.${TAG}.out"
    TMP_DIR="$WORK_DIR/${PREFIX}.${TAG}"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    sed \
        -e "s|__C__|${C}|g" \
        -e "s|__ECUTWFC__|${ECUTWFC}|g" \
        -e "s|__ECUTRHO__|${ECUTRHO}|g" \
        -e "s|__OUTDIR__|${TMP_DIR}|g" \
        -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
        "$TEMPLATE" > "$INPUT"

    echo "[run ${COUNTER}/${TOTAL_RUNS}]: C = ${C} angstrom"

    mpirun -np $MPISIZE pw.x -in "$INPUT" > "$OUTPUT" 2>&1

    if grep -q "JOB DONE." "$OUTPUT"; then
        echo "[done] ${TAG}"
    else
        echo "[incomplete] ${TAG}; inspect: $OUTPUT"
    fi

done

echo
echo "========================================"
echo "[Job done] Path: $CASE_DIR"
echo "========================================"
