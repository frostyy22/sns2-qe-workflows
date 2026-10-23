#!/usr/bin/env bash

# ============================================================
# cutoff_collect.sh
#
# Usage: ./cutoff_collect.sh <CASE_NAME>
# Example: ./cutoff_collect.sh mult_08 ; ./cutoff_collect.sh rho_600
# ============================================================

set -e

PREFIX="SnS2.2x2.paw"

# SnS2/2x2/02_cutoff/
STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CASE_NAME="${1:?Usage: $0 <case_name>}"
CASE_DIR="$STAGE_DIR/$CASE_NAME"

case "$CASE_NAME" in
    mult_*)
        MULT_LABEL="${CASE_NAME#mult_}"
        SUBTITLE="ecutrho = ${MULT_LABEL} x ecutwfc"
        ;;

    rho_*)
        FIXED_RHO="${CASE_NAME#rho_}"
        SUBTITLE="ecutrho = ${FIXED_RHO} Ry"
        ;;

    *)
        SUBTITLE="$CASE_NAME"
        ;;
esac

INPUT_DIR="$CASE_DIR/inputs"
OUTPUT_DIR="$CASE_DIR/outputs"
RESULTS_DIR="$CASE_DIR/results"

mkdir -p "$RESULTS_DIR"

DATA_FILE="$RESULTS_DIR/cutoff_results.dat"
PLOT_FILE="$RESULTS_DIR/energy_vs_ecutwfc.pdf"

# Find all generated QE outputs for this multiplier case.
shopt -s nullglob
UNSORTED_OUTPUT_FILES=("$OUTPUT_DIR"/${PREFIX}.ecut_*_*.out)
mapfile -t OUTPUT_FILES < <(printf '%s\n' "${UNSORTED_OUTPUT_FILES[@]}" | sort -V)

# Data header
echo "run,status,ecutwfc_ry,ecutrho_ry,total_energy_ev,delta_total_energy_ev" \
    > "$DATA_FILE"

# 1 Ry = 13.6057039763 eV
EV=13.6057039763

# ============================================================
# Collect from each calculation
# ============================================================
COUNTER=0
TOTAL_RUNS=${#OUTPUT_FILES[@]}
PREVIOUS_ENERGY_EV=""

for OUTPUT in "${OUTPUT_FILES[@]}"; do

    COUNTER=$((COUNTER + 1))

    # Example:
    # SnS2.ecut_50_400.out
    BASENAME="$(basename "$OUTPUT" .out)"
    INPUT="$INPUT_DIR/${BASENAME}.in"

    ECUTWFC=$(awk -F ' *= *|, *' '/ecutwfc/ {print $2; exit}' "$INPUT")
    ECUTRHO=$(awk -F ' *= *|, *' '/ecutrho/ {print $2; exit}' "$INPUT")

    if grep -q "JOB DONE." "$OUTPUT"; then
        STATUS="complete"

        # Save the last total energy printed in the QE output.
        ENERGY_RY=$(grep "!    total energy" "$OUTPUT" | tail -n 1 | awk '{print $5}')

        ENERGY_EV=$(awk -v e="$ENERGY_RY" -v ev="$EV" \
            'BEGIN {printf "%.10f", e * ev}')

        DELTA_EV=$(awk -v current="$ENERGY_EV" -v previous="$PREVIOUS_ENERGY_EV" '
            BEGIN {
                if (previous != "")
                    printf "%.8f", (current - previous)
            }
        ')

        echo "${BASENAME},${STATUS},${ECUTWFC},${ECUTRHO},${ENERGY_EV},${DELTA_EV}" \
            >> "$DATA_FILE"

        echo "[${COUNTER}/${TOTAL_RUNS}] complete: ${BASENAME}"

        PREVIOUS_ENERGY_EV="$ENERGY_EV"

    else
        STATUS="incomplete"

        echo "${BASENAME},${STATUS},${ECUTWFC},${ECUTRHO},," \
            >> "$DATA_FILE"

        echo "[${COUNTER}/${TOTAL_RUNS}] incomplete: ${BASENAME}"
    fi

done

# ============================================================
# Gnuplot: total energy vs ecutwfc
# ============================================================

gnuplot <<EOF
set datafile separator comma
set terminal pdfcairo noenhanced color size 15cm,10cm font "Arial,14"
set output "$PLOT_FILE"
set title "$PREFIX cutoff convergence - $SUBTITLE"
set xlabel "ecutwfc (Ry)"
set ylabel "Total energy (eV)"

plot "$DATA_FILE" using (strcol(2) eq "complete" ? column(3) : 1/0):5 with linespoints linewidth 2 pointsize 1.2 pointtype 7 title "$PREFIX"
EOF


echo
echo "========================================"
echo "Collection complete: $CASE_NAME."
echo "========================================"
