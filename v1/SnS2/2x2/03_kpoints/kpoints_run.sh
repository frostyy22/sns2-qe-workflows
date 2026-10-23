#!/usr/bin/env bash

# ============================================================
# kpoints_run.sh
#
# Usage: ./kpoints_run.sh
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="$STAGE_DIR/kpoints.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

PREFIX="SnS2.2x2.paw"

ECUTWFC=80
ECUTRHO=400

MPISIZE=5

# K_GRIDS takes "K1 K2 K3 S1 S2 S3"
# S1 = S2 = S3 = 0 by default
# Example "2 2 1 1 0 0" 
K_GRIDS=(
	"3 3 1"
	"4 4 1"
	"5 5 1"
	"6 6 1"
	"7 7 1"
	"8 8 1"
	)


CASE_DIR="$STAGE_DIR/ecut_${ECUTWFC}_${ECUTRHO}"
INPUT_DIR="$CASE_DIR/inputs"
OUTPUT_DIR="$CASE_DIR/outputs"
WORK_DIR="$CASE_DIR/work"

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$WORK_DIR"

# ============================================================
# Run SCF calculations
# ============================================================
COUNTER=0 
TOTAL_RUNS=${#K_GRIDS[@]}

for K_GRID in "${K_GRIDS[@]}"; do

    read -r K1 K2 K3 S1 S2 S3 <<< "$K_GRID"
    
    S1="${S1:-0}"
    S2="${S2:-0}"
    S3="${S3:-0}"

	
    K_GRID_LINE="${K1} ${K2} ${K3} ${S1} ${S2} ${S3}"

    TAG="k${K1}x${K2}x${K3}_s${S1}${S2}${S3}"
    COUNTER=$((COUNTER + 1))

    INPUT="$INPUT_DIR/${PREFIX}.${TAG}.in"
    OUTPUT="$OUTPUT_DIR/${PREFIX}.${TAG}.out"
    TMP_DIR="$WORK_DIR/${PREFIX}.$TAG"

    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"

    sed \
        -e "s|__ECUTWFC__|${ECUTWFC}|g" \
        -e "s|__ECUTRHO__|${ECUTRHO}|g" \
        -e "s|__OUTDIR__|${TMP_DIR}|g" \
        -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
        -e "s|__K_GRID__|${K_GRID_LINE}|g" \
        "$TEMPLATE" > "$INPUT"

    echo "[run ${COUNTER}/${TOTAL_RUNS}]: K-points: [${K_GRID_LINE}]"

    mpirun -np $MPISIZE pw.x -in "$INPUT" > "$OUTPUT" 2>&1

    if grep -q "JOB DONE." "$OUTPUT"; then
        echo "[done]"
    else
        echo "[incomplete] ${TAG}; inspect: $OUTPUT"
    fi

done

echo
echo "========================================"
echo "[Job done] Path:$CASE_DIR"
echo "========================================"
