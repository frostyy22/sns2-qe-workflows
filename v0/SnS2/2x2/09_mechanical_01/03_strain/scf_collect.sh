#!/usr/bin/env bash

# ============================================================
# scf_collect.sh
#
# Usage: ./scf_collect.sh
# ============================================================

# Collect zero strain from 02_scf and nonzero strains from this stage.

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZERO_STAGE="$STAGE_DIR/../02_scf"
STRAIN_GENERATOR="$STAGE_DIR/generate_strain.py"

RESULTS_DIR="$STAGE_DIR/results"
CSV_FILE="$RESULTS_DIR/scf_results.csv"
REPORT_FILE="$RESULTS_DIR/scf_results.dat"

ZERO_RUN_NAME="SnS2.2x2.hex.scf"
# Fixed Ry-to-eV conversion used for collected total and relative energies.
EV_PER_RY=13.605693122994

mkdir -p "$RESULTS_DIR"

resolve_case_paths() {
    local case_label="$1"

    if [ "$case_label" = "biaxial_0p0" ]; then
        INPUT_FILE="$ZERO_STAGE/inputs/${ZERO_RUN_NAME}.in"
        OUTPUT_FILE="$ZERO_STAGE/outputs/${ZERO_RUN_NAME}.out"
    else
        INPUT_FILE="$STAGE_DIR/inputs/$case_label/scf.in"
        OUTPUT_FILE="$STAGE_DIR/outputs/$case_label/scf.out"
    fi
}

input_value() {
    local input_file="$1"
    local key="$2"

    awk -F '=' -v key="$key" '
        {
            name = $1
            gsub(/[[:space:]]/, "", name)

            if (tolower(name) == tolower(key)) {
                value = $2
                sub(/!.*/, "", value)
                gsub(/[[:space:]]/, "", value)
                gsub(/\047/, "", value)
                print value
                exit
            }
        }
    ' "$input_file"
}

output_is_complete() {
    local output_file="$1"

    [ -f "$output_file" ] &&
        grep -q "JOB DONE." "$output_file" &&
        grep -q "convergence has been achieved in" "$output_file"
}

ZERO_OUTPUT="$ZERO_STAGE/outputs/${ZERO_RUN_NAME}.out"
ZERO_ENERGY_RY=""

if output_is_complete "$ZERO_OUTPUT"; then
    ZERO_ENERGY_RY=$(tac "$ZERO_OUTPUT" |
        grep -m 1 "! *total energy" |
        awk '{print $5}')
fi

echo "strain_percent,case_label,status,occupations,smearing,degauss_ry,total_energy_ry,total_energy_ev,delta_energy_ev,fermi_energy_ev,total_force_ry_bohr,pressure_kbar,sigma_xx_kbar,sigma_yy_kbar,sigma_zz_kbar,sigma_xy_kbar,sigma_xz_kbar,sigma_yz_kbar" \
    > "$CSV_FILE"

{
    echo "Biaxial-strain SCF results"
    echo "=========================="
} > "$REPORT_FILE"

case_labels="$(python3 "$STRAIN_GENERATOR" --case-labels)" || exit 1

complete_count=0
skipped_count=0

while IFS= read -r case_label; do
    [ -n "$case_label" ] || continue

    resolve_case_paths "$case_label"

    strain_label="${case_label#biaxial_}"
    strain_percent="${strain_label/p/.}"

    status=""
    note=""

    occupations=""
    smearing=""
    degauss_ry=""
    total_energy_ry=""
    total_energy_ev=""
    delta_energy_ev=""
    fermi_energy_ev=""
    total_force_ry_bohr=""
    pressure_kbar=""
    sigma_xx_kbar=""
    sigma_yy_kbar=""
    sigma_zz_kbar=""
    sigma_xy_kbar=""
    sigma_xz_kbar=""
    sigma_yz_kbar=""
    final_stress_and_pressure=""

    if [ ! -f "$OUTPUT_FILE" ]; then
        status="missing"
        note="SCF output not found"
    elif ! grep -q "JOB DONE." "$OUTPUT_FILE"; then
        status="incomplete"
        note="JOB DONE. not found"
    elif ! grep -q "convergence has been achieved in" "$OUTPUT_FILE"; then
        status="incomplete"
        note="SCF convergence marker not found"
    elif [ ! -f "$INPUT_FILE" ]; then
        status="invalid"
        note="SCF input not found"
    else
        occupations="$(input_value "$INPUT_FILE" "occupations")"
        smearing="$(input_value "$INPUT_FILE" "smearing")"
        degauss_raw="$(input_value "$INPUT_FILE" "degauss")"

        if [ -n "$degauss_raw" ]; then
            degauss_ry=$(awk -v value="$degauss_raw" '
                BEGIN {
                    gsub(/[dD]/, "e", value)
                    printf "%.8g", value + 0
                }
            ')
        fi

        total_energy_ry=$(tac "$OUTPUT_FILE" |
            grep -m 1 "! *total energy" |
            awk '{print $5}')

        fermi_energy_ev=$(tac "$OUTPUT_FILE" |
            grep -m 1 "the Fermi energy is" |
            awk '{print $(NF - 1)}')

        total_force_ry_bohr=$(tac "$OUTPUT_FILE" |
            grep -m 1 "Total force =" |
            awk -F '=' '{print $2}' |
            awk '{print $1}')

        final_stress_and_pressure=$(tac "$OUTPUT_FILE" |
            grep -F -m 1 -B 3 "total   stress  (Ry/bohr**3)" |
            tac)

        stress_values=$(printf '%s\n' "$final_stress_and_pressure" |
            awk '
                NR == 1 {
                    split($0, fields, "P=")
                    pressure = fields[2] + 0
                }
                NR == 2 {
                    sigma_xx = $4
                    sigma_xy = $5
                    sigma_xz = $6
                }
                NR == 3 {
                    sigma_yy = $5
                    sigma_yz = $6
                }
                NR == 4 {
                    sigma_zz = $6
                }
                END {
                    print pressure, sigma_xx, sigma_yy, sigma_zz,
                        sigma_xy, sigma_xz, sigma_yz
                }
            ')

        read -r \
            pressure_kbar \
            sigma_xx_kbar \
            sigma_yy_kbar \
            sigma_zz_kbar \
            sigma_xy_kbar \
            sigma_xz_kbar \
            sigma_yz_kbar <<< "$stress_values"

        if [ -z "$occupations" ] ||
            [ -z "$total_energy_ry" ] ||
            [ -z "$fermi_energy_ev" ] ||
            [ -z "$total_force_ry_bohr" ] ||
            [ -z "$final_stress_and_pressure" ] ||
            [ -z "$sigma_xx_kbar" ] ||
            [ -z "$sigma_yy_kbar" ] ||
            [ -z "$sigma_zz_kbar" ]; then
            status="invalid"
            note="one or more required SCF fields could not be extracted"
        else
            status="complete"

            total_energy_ev=$(awk \
                -v energy="$total_energy_ry" \
                -v conversion="$EV_PER_RY" '
                BEGIN {
                    printf "%.10f", energy * conversion
                }
            ')

            if [ -n "$ZERO_ENERGY_RY" ]; then
                delta_energy_ev=$(awk \
                    -v energy="$total_energy_ry" \
                    -v reference="$ZERO_ENERGY_RY" \
                    -v conversion="$EV_PER_RY" '
                    BEGIN {
                        printf "%.10f", (energy - reference) * conversion
                    }
                ')
            fi
        fi
    fi

    echo "${strain_percent},${case_label},${status},${occupations},${smearing},${degauss_ry},${total_energy_ry},${total_energy_ev},${delta_energy_ev},${fermi_energy_ev},${total_force_ry_bohr},${pressure_kbar},${sigma_xx_kbar},${sigma_yy_kbar},${sigma_zz_kbar},${sigma_xy_kbar},${sigma_xz_kbar},${sigma_yz_kbar}" \
        >> "$CSV_FILE"

    {
        echo
        echo "Case: $case_label"
        echo "Strain: ${strain_percent}%"
        echo "Status: $status"
        echo "Input: $INPUT_FILE"
        echo "Output: $OUTPUT_FILE"

        if [ "$status" = "complete" ]; then
            echo "Occupations: $occupations"
            echo "Smearing: $smearing"
            echo "degauss (Ry): $degauss_ry"
            echo "Final total energy (Ry): $total_energy_ry"
            echo "Final total energy (eV): $total_energy_ev"
            echo "Relative energy (eV): $delta_energy_ev"
            echo "Fermi energy (eV): $fermi_energy_ev"
            echo "Final total force (Ry/bohr): $total_force_ry_bohr"
            echo
            echo "Final stress and pressure:"
            echo "$final_stress_and_pressure"
        else
            echo "Note: $note"
        fi
    } >> "$REPORT_FILE"

    if [ "$status" = "complete" ]; then
        complete_count=$((complete_count + 1))
        echo "[collected] $case_label"
    else
        skipped_count=$((skipped_count + 1))
        echo "[$status] $case_label: $note"
    fi
done <<< "$case_labels"

echo
echo "[results] $CSV_FILE"
echo "[report] $REPORT_FILE"
echo "[complete] $complete_count case(s)"
echo "[skipped] $skipped_count case(s)"
