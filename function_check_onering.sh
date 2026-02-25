#!/usr/bin/env bash

# OneRing Fleet preflight SSH reachability check for generated host helpers.
optstring=":h"

set -uo pipefail

script_dir="$(dirname "$0")"
log_dir="${script_dir}/logs"
mkdir -p "$log_dir"
timestamp="$(date +'%Y%m%d-%H%M%S')"
log_file="${log_dir}/ssh-check-${timestamp}-$$.log"

while getopts "$optstring" opt; do
  case "$opt" in
    h)
cat <<'EOF'
Usage: function_check_onering.sh
  Preflight check that runs a non-interactive SSH command ("true") against each
  generated host helper (e.g. 123_web_ssh.sh) before running fleet_runner.sh.

Purpose:
  Confirms SSH auth/path works using the same helper logic and SSH options.

Notes:
  - Uses each helper script directly, so custom SSH options in those helpers are honored.
  - Requires the target host to accept non-interactive SSH command execution.
  - This is often a better precheck than ICMP ping in environments that block ping.
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

printf '[INFO] OneRing Fleet SSH check started at %s\n' "$(date)" | tee -a "$log_file"

# Only inspect generated host helpers (numeric prefix + _ssh suffix) to avoid unrelated scripts.
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

for helper in "${helper_scripts[@]}"; do
  helper_name="$(basename "$helper")"

  host_line="$(grep -E '^HOST=\"[^\"]+\"$' "$helper" | head -n1 || true)"
  user_line="$(grep -E '^USER=\"[^\"]+\"$' "$helper" | head -n1 || true)"
  host="unknown-host"
  user="unknown-user"
  [[ -n "$host_line" ]] && host="${host_line#HOST=\"}" && host="${host%\"}"
  [[ -n "$user_line" ]] && user="${user_line#USER=\"}" && user="${user%\"}"

  echo "[INFO] Checking SSH to ${user}@${host} via ${helper_name} ..." | tee -a "$log_file"
  if "$helper" true >/dev/null 2>&1; then
    ((reachable++))
    echo "[OK] SSH reachable: ${user}@${host}" | tee -a "$log_file"
  else
    ((unreachable++))
    echo "[WARN] SSH precheck failed: ${user}@${host}" | tee -a "$log_file"
  fi
  echo '---' | tee -a "$log_file"
done

printf '[INFO] OneRing Fleet SSH check finished at %s\n' "$(date)" | tee -a "$log_file"
echo "[INFO] Summary: ssh_ok=${reachable}, ssh_fail=${unreachable}" | tee -a "$log_file"
echo "[INFO] Log: ${log_file}" | tee -a "$log_file"

if (( unreachable > 0 )); then
  exit 1
fi

exit 0
