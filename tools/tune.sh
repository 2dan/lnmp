#!/usr/bin/env bash
set -u

if [ "$(id -u)" -ne 0 ]; then
    echo "Error: root privileges are required." >&2
    exit 1
fi

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "${script_dir}/include/main.sh"
. "${script_dir}/include/tuning.sh"
. "${script_dir}/include/mysql.sh"

Apply_Runtime_Tuning
echo "Hardware-aware kernel, Nginx and PHP-FPM tuning applied."
