#!/usr/bin/env bash

# ============================================================
# dos_plot.sh
#
# Usage: ./dos_plot.sh
# ============================================================

set -e

STAGE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="/home/frost/python_venvs/dft/bin/python"

exec "$PYTHON" "$STAGE_DIR/dos_plot.py"
