#!/usr/bin/env bash

# ============================================================
# bands_case_run.sh
#
# Usage: ./bands_case_run.sh <CASE_LABEL> <SCF_INPUT> <SCF_OUTPUT> <SCF_WORK_DIR>
# ============================================================

set -u

METHOD="fixed"
PW_MPI_PROCESSES=5
BANDS_MPI_PROCESSES=1

if [ "$#" -ne 4 ]; then
    echo "Usage: $0 <CASE_LABEL> <SCF_INPUT> <SCF_OUTPUT> <SCF_WORK_DIR>" >&2
    exit 1
fi

CASE_LABEL="$1"
SCF_INPUT="$2"
SCF_OUTPUT="$3"
SCF_WORK_DIR="$4"

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BANDS_TEMPLATE="$STAGE_DIR/bands.template"
BANDSX_TEMPLATE="$STAGE_DIR/bandsx.template"

PROJECT_DIR="$(cd "$STAGE_DIR/../../../../.." && pwd)"
PSEUDO_DIR="$PROJECT_DIR/pp"

if [ ! -f "$SCF_INPUT" ]; then
    echo "[missing] SCF input: $SCF_INPUT" >&2
    exit 1
fi
if ! grep -q "JOB DONE." "$SCF_OUTPUT" 2>/dev/null; then
    echo "[incomplete] SCF is not complete: $SCF_OUTPUT" >&2
    exit 1
fi
if [ ! -d "$SCF_WORK_DIR" ]; then
    echo "[missing] SCF work directory: $SCF_WORK_DIR" >&2
    exit 1
fi

SCF_WORK_DIR="$(cd "$SCF_WORK_DIR" && pwd)"
save_dirs=("$SCF_WORK_DIR"/*.save)

if [ ! -d "${save_dirs[0]}" ] || [ "${#save_dirs[@]}" -ne 1 ]; then
    echo "[invalid] expected one SCF .save directory under: $SCF_WORK_DIR" >&2
    exit 1
fi

PREFIX="$(basename "${save_dirs[0]}" .save)"
SCF_SAVE_DIR="${save_dirs[0]}"
SCF_PREFIX="$(awk -F= '
    tolower($1) ~ /^[[:space:]]*prefix[[:space:]]*$/ {
        value = $2
        gsub(/[[:space:],\047\042]/, "", value)
        print value
        exit
    }
' "$SCF_INPUT")"

if [ -z "$SCF_PREFIX" ] || [ "$SCF_PREFIX" != "$PREFIX" ]; then
    echo "[invalid] SCF input prefix does not match its .save directory: $CASE_LABEL" >&2
    exit 1
fi

RUN_NAME="${PREFIX%.scf}.${METHOD}"

INPUT_DIR="$STAGE_DIR/inputs/$CASE_LABEL"
OUTPUT_DIR="$STAGE_DIR/outputs/$CASE_LABEL"
RESULTS_DIR="$STAGE_DIR/results/$CASE_LABEL"
BANDS_WORK_DIR="$STAGE_DIR/work/$CASE_LABEL/$METHOD/bands"
BANDS_SAVE_DIR="$BANDS_WORK_DIR/${PREFIX}.save"

STRUCTURE_FILE="$INPUT_DIR/${RUN_NAME}.structure.dat"
BANDS_INPUT="$INPUT_DIR/${RUN_NAME}.bands.in"
BANDS_OUTPUT="$OUTPUT_DIR/${RUN_NAME}.bands.out"
BANDSX_INPUT="$INPUT_DIR/${RUN_NAME}.bandsx.in"
BANDSX_OUTPUT="$OUTPUT_DIR/${RUN_NAME}.bandsx.out"
BANDS_DATA_FILE="$RESULTS_DIR/${RUN_NAME}.bands.dat"
BANDS_GNU_FILE="${BANDS_DATA_FILE}.gnu"
FERMI_FILE="$RESULTS_DIR/${RUN_NAME}.fermi_energy.dat"

if grep -q "JOB DONE." "$BANDS_OUTPUT" 2>/dev/null &&
    grep -q "JOB DONE." "$BANDSX_OUTPUT" 2>/dev/null &&
    [ -s "$BANDS_GNU_FILE" ] &&
    [ -s "$FERMI_FILE" ]; then
    echo "[skip] $CASE_LABEL complete $METHOD band result already exists"
    exit 0
fi

for target in \
    "$STRUCTURE_FILE" \
    "$BANDS_INPUT" \
    "$BANDS_OUTPUT" \
    "$BANDSX_INPUT" \
    "$BANDSX_OUTPUT" \
    "$BANDS_DATA_FILE" \
    "$BANDS_GNU_FILE" \
    "$FERMI_FILE" \
    "$BANDS_WORK_DIR"; do
    if [ -e "$target" ]; then
        echo "[exists] refusing to overwrite $METHOD band data: $target" >&2
        exit 1
    fi
done

mkdir -p "$INPUT_DIR" "$OUTPUT_DIR" "$RESULTS_DIR" "$BANDS_WORK_DIR"

sed -n '
    /^[[:space:]]*CELL_PARAMETERS/,/^[[:space:]]*K_POINTS/ {
        /^[[:space:]]*K_POINTS/q
        p
    }
' "$SCF_INPUT" > "$STRUCTURE_FILE"

if ! grep -qi "^CELL_PARAMETERS.*angstrom" "$STRUCTURE_FILE" ||
    ! grep -qi "^ATOMIC_POSITIONS.*angstrom" "$STRUCTURE_FILE"; then
    echo "[invalid] Cartesian structure not found in: $SCF_INPUT" >&2
    exit 1
fi

atom_count="$(awk '
    /^[[:space:]]*ATOMIC_POSITIONS/ { in_positions = 1; next }
    in_positions && NF >= 4 { count++ }
    END { print count + 0 }
' "$STRUCTURE_FILE")"

if [ "$atom_count" -ne 12 ]; then
    echo "[invalid] expected 12 atomic positions in: $SCF_INPUT" >&2
    exit 1
fi

vacuum_length="$(awk '
    /^[[:space:]]*CELL_PARAMETERS/ { in_cell = 1; next }
    in_cell && NF >= 3 {
        row++
        if (row == 3) {
            print sqrt($1 * $1 + $2 * $2 + $3 * $3)
            exit
        }
    }
' "$STRUCTURE_FILE")"

if ! awk -v vacuum="$vacuum_length" 'BEGIN {
    difference = vacuum - 18.0
    if (difference < 0) difference = -difference
    exit(difference <= 1.0e-6 ? 0 : 1)
}'; then
    echo "[invalid] expected an 18 angstrom out-of-plane cell in: $SCF_INPUT" >&2
    exit 1
fi

fermi_energy="$(awk '
    /the Fermi energy is/ { value = $(NF - 1) }
    END { if (value != "") print value }
' "$SCF_OUTPUT")"

if [ -z "$fermi_energy" ]; then
    echo "[invalid] Fermi energy not found in: $SCF_OUTPUT" >&2
    exit 1
fi

echo "[copy] $CASE_LABEL matching SCF save -> isolated $METHOD band work"
if ! cp -a "$SCF_SAVE_DIR" "$BANDS_SAVE_DIR"; then
    echo "[failed] could not copy SCF save directory: $SCF_SAVE_DIR" >&2
    exit 1
fi

sed \
    -e "s|__PREFIX__|${PREFIX}|g" \
    -e "s|__OUTDIR__|${BANDS_WORK_DIR}|g" \
    -e "s|__PSEUDO_DIR__|${PSEUDO_DIR}|g" \
    "$BANDS_TEMPLATE" | \
sed "/^__STRUCTURE__$/ {
    r $STRUCTURE_FILE
    d
}" > "$BANDS_INPUT"

sed \
    -e "s|__PREFIX__|${PREFIX}|g" \
    -e "s|__OUTDIR__|${BANDS_WORK_DIR}|g" \
    -e "s|__BANDS_DATA_FILE__|${BANDS_DATA_FILE}|g" \
    "$BANDSX_TEMPLATE" > "$BANDSX_INPUT"

if grep -q "__" "$BANDS_INPUT" "$BANDSX_INPUT"; then
    echo "[invalid] unresolved template marker for: $CASE_LABEL" >&2
    exit 1
fi

printf '%s\n' "$fermi_energy" > "$FERMI_FILE"

echo "[run] $CASE_LABEL $METHOD bands ($PW_MPI_PROCESSES MPI ranks)"

mpirun -np "$PW_MPI_PROCESSES" pw.x -in "$BANDS_INPUT" > "$BANDS_OUTPUT" 2>&1

if ! grep -q "JOB DONE." "$BANDS_OUTPUT"; then
    echo "[incomplete] $CASE_LABEL bands; inspect: $BANDS_OUTPUT" >&2
    exit 1
fi

echo "[done] $CASE_LABEL bands"
echo "[run] $CASE_LABEL bandsx ($BANDS_MPI_PROCESSES MPI rank)"

mpirun -np "$BANDS_MPI_PROCESSES" bands.x -in "$BANDSX_INPUT" > "$BANDSX_OUTPUT" 2>&1

if ! grep -q "JOB DONE." "$BANDSX_OUTPUT"; then
    echo "[incomplete] $CASE_LABEL bandsx; inspect: $BANDSX_OUTPUT" >&2
    exit 1
fi

if [ ! -s "$BANDS_GNU_FILE" ]; then
    echo "[missing] $CASE_LABEL GNU band data: $BANDS_GNU_FILE" >&2
    exit 1
fi

echo "[done] $CASE_LABEL bandsx"
echo "[results] $BANDS_DATA_FILE"
echo "[results] $BANDS_GNU_FILE"
