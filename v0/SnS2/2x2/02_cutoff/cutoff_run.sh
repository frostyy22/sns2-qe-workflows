#!/usr/bin/env bash

# ============================================================
# cutoff_run.sh
#
# Usage: ./cutoff_run.sh <ratio|fixed> <VALUE>
# Example: ./cutoff_run.sh ratio 6 ; ./cutoff_run.sh fixed 520
# ============================================================

PREFIX="SnS2.2x2"
ECUTWFC_VALUES=(20 30 40 50 60 70 80 90 100)
MPISIZE=5

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" # Dir containing this script
TEMPLATE="$STAGE_DIR/cutoff.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../.." && pwd)" # Parent dir containing pp (adjust ../ levels for stage location)
PSEUDO_DIR="$PROJECT_DIR/pp"

MODE="${1:?Usage: $0 <ratio|fixed> <value>}"
VALUE="${2:?Usage: $0 <ratio|fixed> <value>}"

case "$MODE" in
    ratio)
        MULT=$((10#$VALUE))
        MULT_LABEL=$(printf "%02d" "$MULT")
        CASE_DIR="$STAGE_DIR/mult_${MULT_LABEL}"
        ;;

    fixed)
        FIXED_RHO=$((10#$VALUE))
        CASE_DIR="$STAGE_DIR/rho_${FIXED_RHO}"
        ;;

    *)
        echo "ERROR: MODE must be either 'ratio' or 'fixed'" >&2
        echo "Usage: $0 <ratio|fixed> <value>" >&2
        exit 1
        ;;
esac

INPUT_DIR="$CASE_DIR/inputs"
OUTPUT_DIR="$CASE_DIR/outputs"
WORK_DIR="$CASE_DIR/work"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_DIR"

# ============================================================
# Run SCF calculations
# ============================================================

COUNTER=0
TOTAL_RUNS=${#ECUTWFC_VALUES[@]}

for ECUTWFC in "${ECUTWFC_VALUES[@]}"; do

    case "$MODE" in
        ratio)
            ECUTRHO=$((ECUTWFC * MULT))
            ;;
        fixed)
            ECUTRHO="$FIXED_RHO"
            ;;
    esac

    TAG="ecut_${ECUTWFC}_${ECUTRHO}"
    COUNTER=$((COUNTER + 1))

    INPUT="$INPUT_DIR/${PREFIX}.${TAG}.in"
    OUTPUT="$OUTPUT_DIR/${PREFIX}.${TAG}.out"
    TMP_DIR="$WORK_DIR/$TAG"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    sed \
        -e "s|__ECUTWFC__|${ECUTWFC}|g" \
        -e "s|__ECUTRHO__|${ECUTRHO}|g" \
        -e "s|__OUTDIR__|${TMP_DIR}|g" \
        -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
        "$TEMPLATE" > "$INPUT"

    echo "[run ${COUNTER}/${TOTAL_RUNS}]: ecutwfc = ${ECUTWFC} Ry, ecutrho = ${ECUTRHO} Ry"

    mpirun -np $MPISIZE pw.x -in "$INPUT" > "$OUTPUT" 2>&1

    if grep -q "JOB DONE" "$OUTPUT"; then
        echo "[done] ${TAG}"
    else
        echo "[incomplete] ${TAG}; inspect: $OUTPUT"
    fi

done

echo
echo "========================================"
echo "[Job done] Path: $CASE_DIR"
echo "========================================"
