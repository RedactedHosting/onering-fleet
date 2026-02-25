#!/usr/bin/env bash

# OneRing Fleet runner for generated *_ssh.sh helpers. Supports quick diagnostics via flags.
optstring=":dmcusk:h"
remote_cmd=""
stop_on_failure=false

set -uo pipefail

script_dir="$(dirname "$0")"
log_dir="${script_dir}/logs"
mkdir -p "$log_dir"
timestamp="$(date +'%Y%m%d-%H%M%S')"
log_file="${log_dir}/fleet-${timestamp}-$$.log"

printf '[INFO] OneRing Fleet run started at %s\n' "$(date)" | tee -a "$log_file"

while getopts "$optstring" opt; do
  case "$opt" in
    d) remote_cmd="df -h" ;;
    m) remote_cmd="free -h" ;;
    c) remote_cmd="top -bn1 | head -n5" ;;
    u) remote_cmd="uptime" ;;
    k) remote_cmd="$OPTARG" ;;
    s) stop_on_failure=true ;;
    h)
cat <<'EOF'
Usage: fleet_runner.sh [-d|-m|-c|-u|-k <cmd>] [-s]
  -d  Run disk usage (df -h) on each host
  -m  Run memory snapshot (free -h)
  -c  Run CPU summary (top -bn1 | head -n5)
  -u  Run uptime
  -k  Run custom command (quote it), e.g. -k "whoami"
  -s  Stop on first failure instead of continuing
  -h  Show this help
Default: run each helper with --update ("one script to rule them all").
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

# Only run generated host helpers (numeric prefix + _ssh suffix) to avoid accidental execution.
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

failures=0
for helper in "${helper_scripts[@]}"; do
  [[ "$helper" == "$0" ]] && continue

  if [[ -n "$remote_cmd" ]]; then
    cmd=( "$helper" "$remote_cmd" )
    label="$remote_cmd"
  else
    cmd=( "$helper" --update )
    label="--update"
  fi

  echo "[INFO] Running ${helper} ${label}" | tee -a "$log_file"
  if "${cmd[@]}" | tee -a "$log_file"; then
    echo "[OK] ${helper} succeeded." | tee -a "$log_file"
  else
    ((failures++))
    if $stop_on_failure; then
      echo "[WARN] ${helper} failed. Stopping early." | tee -a "$log_file"
    else
      echo "[WARN] ${helper} failed." | tee -a "$log_file"
    fi
    if $stop_on_failure; then
      break
    fi
  fi
  echo '---' | tee -a "$log_file"
done

printf '[INFO] OneRing Fleet run finished at %s\n' "$(date)" | tee -a "$log_file"

if (( failures > 0 )); then
  echo "[WARN] ${failures} host(s) reported failures. See ${log_file}."
  exit 1
fi

echo "[INFO] All hosts completed successfully. Log at ${log_file}."
