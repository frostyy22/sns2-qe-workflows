#!/usr/bin/env bash

# ============================================================
# vcrelax_collect.sh
#
# Usage: ./vcrelax_collect.sh
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PREFIX="SnS2.2x2.paw"
RUN_NAME="$PREFIX"

OUTPUT_FILE="$STAGE_DIR/outputs/${RUN_NAME}.out"
RESULTS_DIR="$STAGE_DIR/results"
DATA_FILE="$RESULTS_DIR/results.dat"

mkdir -p "$RESULTS_DIR"

if ! grep -q "JOB DONE." "$OUTPUT_FILE"; then
    echo "[incomplete] JOB DONE not found in: $OUTPUT_FILE" >&2
    exit 1
fi

FINAL_ENERGY=$(grep "! *total energy" "$OUTPUT_FILE" | tail -n 1 | awk '{print $5}')

FINAL_TOTAL_FORCE=$(grep "Total force =" "$OUTPUT_FILE" | tail -n 1 | \
    awk -F '=' '{print $2}' | awk '{print $1}')

RELAX_STATUS=$(grep -i -E \
    "bfgs converged|End of BFGS|convergence NOT achieved|maximum number of steps" \
    "$OUTPUT_FILE" | tail -n 1)

FINAL_STRESS_AND_PRESSURE=$(tac "$OUTPUT_FILE" | \
    grep -F -m 1 -B 3 "total   stress  (Ry/bohr**3)" | tac)

FINAL_GEOMETRY=$(tac "$OUTPUT_FILE" | \
    sed -n '/End final coordinates/,/Begin final coordinates/ {
        /Begin final coordinates/q
        /final coordinates/!p
    }' | tac)

{
    echo "Run: $RUN_NAME"
    echo "Status: complete"

    echo
    echo "Final total energy (Ry):"
    echo "$FINAL_ENERGY"

    echo
    echo "Final total force (Ry/bohr):"
    echo "$FINAL_TOTAL_FORCE"

    echo
    echo "Final stress and pressure:"
    echo "$FINAL_STRESS_AND_PRESSURE"

    echo
    echo "Relaxation status:"
    echo "$RELAX_STATUS"

    echo
    echo "Final geometry:"
    echo "$FINAL_GEOMETRY"
} > "$DATA_FILE"

echo "[collected] $RUN_NAME"
echo "[results] $DATA_FILE"
