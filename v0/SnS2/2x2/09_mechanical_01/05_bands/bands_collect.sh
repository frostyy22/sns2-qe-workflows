#!/usr/bin/env bash

# ============================================================
# bands_collect.sh
#
# Usage: ./bands_collect.sh [cold|fixed]
# ============================================================

set -e

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STRAIN_GENERATOR="$STAGE_DIR/../03_strain/generate_strain.py"
PLOTTER="$STAGE_DIR/bands_plot.py"
PYTHON="/home/frost/python_venvs/dft/bin/python"
METHOD="${1:-fixed}"
if [ "$#" -gt 1 ] || { [ "$METHOD" != "cold" ] && [ "$METHOD" != "fixed" ]; }; then
    echo "Usage: $0 [cold|fixed]" >&2
    exit 1
fi

RESULTS_DIR="$STAGE_DIR/results"
SUMMARY_FILE="$RESULTS_DIR/${METHOD}.bands_results.csv"

mkdir -p "$RESULTS_DIR"

printf '%s\n' \
    "strain_percent,case_label,status,fermi_energy_ev,vbm_relative_to_fermi_ev,cbm_relative_to_fermi_ev,band_gap_ev,gap_character,vbm_k_distance,cbm_k_distance,bands_data_file,plot_file" \
    > "$SUMMARY_FILE"

write_summary_row() {
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' "$@" \
        >> "$SUMMARY_FILE"
}

case_labels="$("$PYTHON" "$STRAIN_GENERATOR" --case-labels)" || exit 1
ready_cases=()
shopt -s nullglob

while IFS= read -r case_label; do
    [ -n "$case_label" ] || continue

    strain_label="${case_label#biaxial_}"
    strain_percent="${strain_label/p/.}"

    bands_outputs=("$STAGE_DIR/outputs/$case_label/"*."$METHOD".bands.out)
    bandsx_outputs=("$STAGE_DIR/outputs/$case_label/"*."$METHOD".bandsx.out)
    bands_data_files=("$RESULTS_DIR/$case_label/"*."$METHOD".bands.dat.gnu)
    fermi_files=("$RESULTS_DIR/$case_label/"*."$METHOD".fermi_energy.dat)

    relative_bands_data="results/$case_label/*.${METHOD}.bands.dat.gnu"
    relative_plot_file="results/$case_label/${METHOD}.bands.pdf"

    if [ "${#bands_outputs[@]}" -eq 0 ] &&
        [ "${#bandsx_outputs[@]}" -eq 0 ] &&
        [ "${#bands_data_files[@]}" -eq 0 ]; then
        write_summary_row "$strain_percent" "$case_label" "missing" "" "" "" "" "" "" "" "$relative_bands_data" ""
        echo "[skip] $case_label: no band outputs or data"
        continue
    fi

    if [ "${#bands_outputs[@]}" -ne 1 ] ||
        [ "${#bandsx_outputs[@]}" -ne 1 ] ||
        [ "${#bands_data_files[@]}" -ne 1 ] ||
        [ "${#fermi_files[@]}" -ne 1 ]; then
        write_summary_row "$strain_percent" "$case_label" "invalid_layout" "" "" "" "" "" "" "" "$relative_bands_data" ""
        echo "[skip] $case_label: expected one complete set of $METHOD artifacts"
        continue
    fi

    bands_output="${bands_outputs[0]}"
    bandsx_output="${bandsx_outputs[0]}"
    bands_data="${bands_data_files[0]}"
    fermi_file="${fermi_files[0]}"
    relative_bands_data="${bands_data#"$STAGE_DIR/"}"

    if ! grep -q "JOB DONE." "$bands_output" 2>/dev/null ||
        ! grep -q "JOB DONE." "$bandsx_output" 2>/dev/null; then
        write_summary_row "$strain_percent" "$case_label" "incomplete" "" "" "" "" "" "" "" "$relative_bands_data" ""
        echo "[skip] $case_label: bands or bands.x output is incomplete"
        continue
    fi

    if [ ! -s "$bands_data" ]; then
        write_summary_row "$strain_percent" "$case_label" "missing_data" "" "" "" "" "" "" "" "$relative_bands_data" ""
        echo "[skip] $case_label: GNU band data is missing or empty"
        continue
    fi

    fermi_energy="$(awk 'NF { print $1; exit }' "$fermi_file" 2>/dev/null || true)"
    if ! awk -v value="$fermi_energy" 'BEGIN {
        exit(value ~ /^[-+]?[0-9]*\.?[0-9]+([Ee][-+]?[0-9]+)?$/ ? 0 : 1)
    }'; then
        write_summary_row "$strain_percent" "$case_label" "invalid_data" "" "" "" "" "" "" "" "$relative_bands_data" ""
        echo "[skip] $case_label: saved SCF Fermi energy is missing or invalid"
        continue
    fi

    write_summary_row "$strain_percent" "$case_label" "ready" "$fermi_energy" "" "" "" "" "" "" "$relative_bands_data" "$relative_plot_file"
    ready_cases+=("$case_label")
    echo "[collect] $case_label"
done <<< "$case_labels"

if [ "${#ready_cases[@]}" -gt 0 ]; then
    BANDS_METHOD="$METHOD" "$PYTHON" "$PLOTTER" "${ready_cases[@]}" || exit 1
else
    echo "[plot] no completed band cases"
fi

complete_count="$(awk -F, '$3 == "complete" { count++ } END { print count + 0 }' "$SUMMARY_FILE")"
skipped_count="$(awk -F, 'NR > 1 && $3 != "complete" { count++ } END { print count + 0 }' "$SUMMARY_FILE")"

echo "[summary] $SUMMARY_FILE"
echo "[complete] $complete_count case(s)"
echo "[skipped] $skipped_count case(s)"
