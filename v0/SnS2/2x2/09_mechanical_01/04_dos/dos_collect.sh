#!/usr/bin/env bash

# ============================================================
# dos_collect.sh
#
# Usage: ./dos_collect.sh
# ============================================================

set -e

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRAIN_GENERATOR="$STAGE_DIR/../03_strain/generate_strain.py"
PLOTTER="$STAGE_DIR/dos_plot.py"
PYTHON="/home/frost/python_venvs/dft/bin/python"

RESULTS_DIR="$STAGE_DIR/results"
SUMMARY_FILE="$RESULTS_DIR/dos_results.csv"

mkdir -p "$RESULTS_DIR"

echo "strain_percent,case_label,status,fermi_energy_ev,dos_data_file,plot_file" \
    > "$SUMMARY_FILE"

case_labels="$(python3 "$STRAIN_GENERATOR" --case-labels)" || exit 1

completed_cases=()
completed_count=0
skipped_count=0

while IFS= read -r case_label; do
    [ -n "$case_label" ] || continue

    strain_label="${case_label#biaxial_}"
    strain_percent="${strain_label/p/.}"

    nscf_output="$STAGE_DIR/outputs/$case_label/nscf.out"
    dos_output="$STAGE_DIR/outputs/$case_label/dos.out"
    dos_data="$RESULTS_DIR/$case_label/dos.dat"

    relative_dos_data="results/$case_label/dos.dat"
    relative_plot_file="results/$case_label/dos.pdf"

    if [ ! -f "$nscf_output" ] &&
        [ ! -f "$dos_output" ] &&
        [ ! -f "$dos_data" ]; then
        echo "${strain_percent},${case_label},missing,,${relative_dos_data}," \
            >> "$SUMMARY_FILE"
        echo "[skip] $case_label: no NSCF output, DOS output, or DOS data"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    if ! grep -q "JOB DONE." "$nscf_output" 2>/dev/null; then
        echo "${strain_percent},${case_label},incomplete_nscf,,${relative_dos_data}," \
            >> "$SUMMARY_FILE"
        echo "[skip] $case_label: NSCF output is incomplete"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    if ! grep -q "JOB DONE." "$dos_output" 2>/dev/null; then
        echo "${strain_percent},${case_label},incomplete_dos,,${relative_dos_data}," \
            >> "$SUMMARY_FILE"
        echo "[skip] $case_label: DOS output is incomplete"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    if [ ! -s "$dos_data" ]; then
        echo "${strain_percent},${case_label},missing_data,,${relative_dos_data}," \
            >> "$SUMMARY_FILE"
        echo "[skip] $case_label: DOS data is missing or empty"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    fermi_energy="$(awk -F 'EFermi =' '
        /EFermi =/ {
            value = $2
            sub(/^[[:space:]]*/, "", value)
            split(value, fields, /[[:space:]]+/)
            print fields[1]
            exit
        }
    ' "$dos_data")"

    if [ -z "$fermi_energy" ]; then
        echo "${strain_percent},${case_label},invalid_data,,${relative_dos_data}," \
            >> "$SUMMARY_FILE"
        echo "[skip] $case_label: EFermi not found in DOS data"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    # Individual plots use energy, total DOS, and integrated DOS. Any
    # additional columns are allowed but ignored.
    if ! awk '
        $1 !~ /^#/ && NF >= 3 {
            found = 1
            exit
        }
        END {
            exit(found ? 0 : 1)
        }
    ' "$dos_data"; then
        echo "${strain_percent},${case_label},invalid_data,,${relative_dos_data}," \
            >> "$SUMMARY_FILE"
        echo "[skip] $case_label: expected at least three-column DOS data"
        skipped_count=$((skipped_count + 1))
        continue
    fi

    echo "${strain_percent},${case_label},complete,${fermi_energy},${relative_dos_data},${relative_plot_file}" \
        >> "$SUMMARY_FILE"

    completed_cases+=("$case_label")
    completed_count=$((completed_count + 1))
    echo "[collect] $case_label"
done <<< "$case_labels"

if [ "$completed_count" -gt 0 ]; then
    "$PYTHON" "$PLOTTER" "${completed_cases[@]}" || exit 1
else
    echo "[plot] no completed DOS cases"
fi

echo "[summary] $SUMMARY_FILE"
echo "[complete] $completed_count case(s)"
echo "[skipped] $skipped_count case(s)"
