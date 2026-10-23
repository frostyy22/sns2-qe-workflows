#!/usr/bin/env bash

# ============================================================
# vac_collect.sh
#
# Usage: ./vac_collect.sh <CASE_NAME>
# Example: ./vac_collect.sh ecut_80_400_k6x6x1
# ============================================================

set -e

PREFIX="SnS2.2x2.paw"

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CASE_NAME="${1:?Usage: $0 <case_name: ecut_80_400_k6x6x1>}"
CASE_DIR="$STAGE_DIR/$CASE_NAME"

INPUT_DIR="$CASE_DIR/inputs"
OUTPUT_DIR="$CASE_DIR/outputs"
RESULTS_DIR="$CASE_DIR/results"

mkdir -p "$RESULTS_DIR"

DATA_FILE="$RESULTS_DIR/vac_results.dat"
PLOT_FILE="$RESULTS_DIR/energy_vs_c.pdf"

shopt -s nullglob
UNSORTED_OUTPUT_FILES=("$OUTPUT_DIR"/${PREFIX}.c*.out)
mapfile -t OUTPUT_FILES < <(printf '%s\n' "${UNSORTED_OUTPUT_FILES[@]}" | sort -V)

echo "run,status,c_angstrom,total_energy_ev,delta_total_energy_ev" \
    > "$DATA_FILE"

# 1 Ry = 13.6057039763 eV
EV=13.6057039763

COUNTER=0
TOTAL_RUNS=${#OUTPUT_FILES[@]}
PREVIOUS_ENERGY_EV=""

for OUTPUT in "${OUTPUT_FILES[@]}"; do

    COUNTER=$((COUNTER + 1))

    BASENAME="$(basename "$OUTPUT" .out)"
    INPUT="$INPUT_DIR/${BASENAME}.in"

    C=$(awk -F ' *= *|, *' '/^[[:space:]]*C[[:space:]]*=/ {print $2; exit}' "$INPUT")

    if grep -q "JOB DONE." "$OUTPUT"; then
        STATUS="complete"

        ENERGY_RY=$(grep "!    total energy" "$OUTPUT" | tail -n 1 | awk '{print $5}')

        ENERGY_EV=$(awk -v e="$ENERGY_RY" -v ev="$EV" \
            'BEGIN {printf "%.10f", e * ev}')

        DELTA_EV=$(awk -v current="$ENERGY_EV" -v previous="$PREVIOUS_ENERGY_EV" '
            BEGIN {
                if (previous != "")
                    printf "%.8f", current - previous
            }
        ')

        echo "${BASENAME},${STATUS},${C},${ENERGY_EV},${DELTA_EV}" \
            >> "$DATA_FILE"

        echo "[${COUNTER}/${TOTAL_RUNS}] complete: ${BASENAME}"

        PREVIOUS_ENERGY_EV="$ENERGY_EV"

    else
        STATUS="incomplete"

        echo "${BASENAME},${STATUS},${C},," >> "$DATA_FILE"

        echo "[${COUNTER}/${TOTAL_RUNS}] incomplete: ${BASENAME}"
    fi

done

# ============================================================
# Gnuplot: total energy vs C
# ============================================================

gnuplot <<EOF
set datafile separator comma
set terminal pdfcairo noenhanced color size 15cm,10cm font "Arial,14"
set output "$PLOT_FILE"
set title "$PREFIX vacuum convergence - $CASE_NAME"
set xlabel "C (angstrom)"
set ylabel "Total energy (eV)"

plot "$DATA_FILE" using (strcol(2) eq "complete" ? column(3) : 1/0):4 with linespoints linewidth 2 pointsize 1.2 pointtype 7 title "$PREFIX"
EOF

echo
echo "========================================"
echo "Collection complete: $CASE_NAME."
echo "========================================"
