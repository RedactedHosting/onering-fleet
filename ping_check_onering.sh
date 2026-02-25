#!/usr/bin/env bash

# OneRing Fleet preflight reachability check for generated host helpers.
optstring=":c:t:h"
ping_count=1
ping_timeout=2

set -uo pipefail

script_dir="$(dirname "$0")"
log_dir="${script_dir}/logs"
mkdir -p "$log_dir"
timestamp="$(date +'%Y%m%d-%H%M%S')"
log_file="${log_dir}/ping-check-${timestamp}-$$.log"

while getopts "$optstring" opt; do
  case "$opt" in
    c) ping_count="$OPTARG" ;;
    t) ping_timeout="$OPTARG" ;;
    h)
cat <<'EOF'
Usage: ping_check_onering.sh [-c count] [-t timeout_seconds]
  -c  Number of ICMP echo requests per host (default: 1)
  -t  Ping timeout in seconds per request (default: 2)
  -h  Show this help

Purpose:
  Preflight check to confirm hosts from generated *_ssh.sh helpers respond to ping
  before running fleet_runner.sh.

Notes:
  - Some environments block ICMP; a host may still be SSH-reachable even if ping fails.
  - This script extracts HOST="..." from generated OneRing Fleet helper scripts.
EOF
      exit 0
      ;;
    :)
      echo "[ERROR] Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    \?)
      echo "[ERROR] Unknown option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

shift $((OPTIND - 1))

[[ "$ping_count" =~ ^[0-9]+$ ]] && (( ping_count >= 1 )) || { echo "[ERROR] -c must be a positive integer."; exit 1; }
[[ "$ping_timeout" =~ ^[0-9]+$ ]] && (( ping_timeout >= 1 )) || { echo "[ERROR] -t must be a positive integer."; exit 1; }

if ! command -v ping >/dev/null 2>&1; then
  echo "[ERROR] 'ping' command not found. Install iputils-ping (Linux)." | tee -a "$log_file"
  exit 1
fi

printf '[INFO] OneRing Fleet ping check started at %s\n' "$(date)" | tee -a "$log_file"

# Only inspect generated host helpers (numeric prefix + _ssh suffix) to avoid parsing unrelated scripts.
mapfile -t helper_scripts < <(find "$script_dir" -maxdepth 1 -type f -name '*_ssh.sh' -executable | sort)
filtered_helpers=()
for helper in "${helper_scripts[@]}"; do
  helper_name="$(basename "$helper")"
  [[ "$helper_name" =~ ^[0-9]+_[A-Za-z0-9._-]+_ssh\.sh$ ]] || continue
  filtered_helpers+=( "$helper" )
done
helper_scripts=( "${filtered_helpers[@]}" )

if [[ ${#helper_scripts[@]} -eq 0 ]]; then
  echo "[ERROR] No generated host helpers (e.g. 123_web_ssh.sh) found in ${script_dir}." | tee -a "$log_file"
  exit 1
fi

reachable=0
unreachable=0
parse_fail=0

for helper in "${helper_scripts[@]}"; do
  helper_name="$(basename "$helper")"
  host_line="$(grep -E '^HOST=\"[^\"]+\"$' "$helper" | head -n1 || true)"
  if [[ -z "$host_line" ]]; then
    ((parse_fail++))
    echo "[WARN] ${helper_name}: could not parse HOST=\"...\" line. Skipping." | tee -a "$log_file"
    echo '---' | tee -a "$log_file"
    continue
  fi

  host="${host_line#HOST=\"}"
  host="${host%\"}"

  echo "[INFO] Pinging ${host} (from ${helper_name}) ..." | tee -a "$log_file"
  if ping -c "$ping_count" -W "$ping_timeout" "$host" >/dev/null 2>&1; then
    ((reachable++))
    echo "[OK] ${host} reachable" | tee -a "$log_file"
  else
    ((unreachable++))
    echo "[WARN] ${host} unreachable by ICMP ping" | tee -a "$log_file"
  fi
  echo '---' | tee -a "$log_file"
done

printf '[INFO] OneRing Fleet ping check finished at %s\n' "$(date)" | tee -a "$log_file"
echo "[INFO] Summary: reachable=${reachable}, unreachable=${unreachable}, parse_fail=${parse_fail}" | tee -a "$log_file"
echo "[INFO] Log: ${log_file}" | tee -a "$log_file"

if (( unreachable > 0 || parse_fail > 0 )); then
  exit 1
fi

exit 0
