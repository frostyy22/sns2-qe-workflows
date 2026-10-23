#!/usr/bin/env bash

# ============================================================
# scf_collect.sh
#
# Usage: ./scf_collect.sh
# ============================================================

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RUN_NAME="SnS2.2x2.hex.paw.scf"

OUTPUT_FILE="$STAGE_DIR/outputs/${RUN_NAME}.out"
RESULTS_DIR="$STAGE_DIR/results"
DATA_FILE="$RESULTS_DIR/results.dat"

mkdir -p "$RESULTS_DIR"

if ! grep -q "JOB DONE." "$OUTPUT_FILE" 2>/dev/null; then
    echo "[incomplete] JOB DONE not found in: $OUTPUT_FILE" >&2
    exit 1
fi

if ! grep -q "convergence has been achieved in" "$OUTPUT_FILE"; then
    echo "[incomplete] SCF convergence marker not found: $OUTPUT_FILE" >&2
    exit 1
fi

FINAL_ENERGY=$(tac "$OUTPUT_FILE" | \
    grep -m 1 "! *total energy" | awk '{print $5}')

FINAL_STRESS_AND_PRESSURE=$(tac "$OUTPUT_FILE" | \
    grep -F -m 1 -B 3 "total   stress  (Ry/bohr**3)" | tac)

FINAL_TOTAL_FORCE=$(tac "$OUTPUT_FILE" | \
    grep -m 1 "Total force =" | \
    awk -F '=' '{print $2}' | awk '{print $1}')

FERMI_ENERGY=$(tac "$OUTPUT_FILE" | \
    grep -m 1 "the Fermi energy is" | awk '{print $(NF - 1)}')

{
    echo "Run: $RUN_NAME"
    echo "Status: complete"

    echo
    echo "Final total energy (Ry):"
    echo "$FINAL_ENERGY"

    echo
    echo "Fermi energy (eV):"
    echo "$FERMI_ENERGY"

    echo
    echo "Final stress and pressure:"
    echo "$FINAL_STRESS_AND_PRESSURE"

    echo
    echo "Final total force (Ry/bohr):"
    echo "$FINAL_TOTAL_FORCE"
} > "$DATA_FILE"

echo "[collected] $RUN_NAME"
echo "[results] $DATA_FILE"
