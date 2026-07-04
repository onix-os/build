#!/usr/bin/env bash
# vm/phase0/kill-qemu.sh — stop only the Onix forge QEMU process.
#
# This intentionally does NOT kill every qemu-system-x86_64 process. launch.sh
# starts the forge with `-name ...,process=onix-$VM_NAME`, so we match that exact
# process name and leave unrelated VMs alone.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

collect_pids() {
  if command -v pgrep >/dev/null 2>&1; then
    pgrep -x "$QEMU_PROCESS_NAME" || true
  else
    ps -eo pid=,comm= | awk -v name="$QEMU_PROCESS_NAME" '$2 == name { print $1 }'
  fi
}

mapfile -t pids < <(collect_pids)

if [[ "${#pids[@]}" -eq 0 ]]; then
  log "qemu      : no running Onix forge process ($QEMU_PROCESS_NAME)"
  exit 0
fi

log "qemu      : stopping $QEMU_PROCESS_NAME pid(s): ${pids[*]}"
kill -TERM "${pids[@]}" 2>/dev/null || true

deadline=$((SECONDS + 8))
while :; do
  mapfile -t alive < <(collect_pids)
  [[ "${#alive[@]}" -eq 0 ]] && { log "qemu      : stopped"; exit 0; }
  [[ "$SECONDS" -ge "$deadline" ]] && break
  sleep 1
done

warn "qemu      : still running after TERM; forcing pid(s): ${alive[*]}"
kill -KILL "${alive[@]}" 2>/dev/null || true
log "qemu      : killed"
