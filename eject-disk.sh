#!/bin/bash
# DiskFree — Eject stubborn macOS disks without logging out.
# https://github.com/getdiskfree/diskfree
# License: MIT

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Header ──────────────────────────────────────────────────────────
print_header() {
  echo ""
  echo -e "${CYAN}╔══════════════════════════════════════════╗${RESET}"
  echo -e "${CYAN}║${RESET}  ${GREEN}${BOLD}DiskFree${RESET}  ${DIM}— eject stubborn disks${RESET}       ${CYAN}║${RESET}"
  echo -e "${CYAN}╚══════════════════════════════════════════╝${RESET}"
  echo ""
}

# ── Helpers ─────────────────────────────────────────────────────────
info()    { echo -e "${GREEN}✓${RESET} $1"; }
warn()    { echo -e "${YELLOW}⚠${RESET} $1"; }
error()   { echo -e "${RED}✗${RESET} $1"; }
step()    { echo -e "${CYAN}→${RESET} $1"; }

# Known system processes that auto-release on unmount
SYSTEM_PROCS="mds|mds_stores|mdworker|mdworker_shared|fseventsd|bird|cloudd|diskarbitrationd|fsck|revisiond"

is_system_process() {
  local proc_name="$1"
  echo "$proc_name" | grep -qE "^(${SYSTEM_PROCS})$"
}

# ── List external volumes ───────────────────────────────────────────
list_volumes() {
  local volumes=()
  while IFS= read -r vol; do
    # Skip system volumes
    case "$vol" in
      "Macintosh HD"|"Macintosh HD - Data"|"Recovery"|"Preboot"|"VM"|"Update") continue ;;
    esac
    volumes+=("$vol")
  done < <(ls /Volumes 2>/dev/null)
  printf '%s\n' "${volumes[@]}"
}

# ── Find blockers ───────────────────────────────────────────────────
find_blockers() {
  local volume_path="$1"
  # Use lsof to find all processes with open handles on the volume
  lsof +D "$volume_path" 2>/dev/null | tail -n +2 || true
}

# ── Parse blocker details ──────────────────────────────────────────
parse_blockers() {
  local lsof_output="$1"
  local seen_pids=""

  while IFS= read -r line; do
    [ -z "$line" ] && continue

    local proc_name pid fd_info
    proc_name=$(echo "$line" | awk '{print $1}')
    pid=$(echo "$line" | awk '{print $2}')
    fd_info=$(echo "$line" | awk '{print $4}')

    # Skip duplicate PIDs
    if echo "$seen_pids" | grep -q ":${pid}:"; then
      continue
    fi
    seen_pids="${seen_pids}:${pid}:"

    # Determine read/write status from file descriptor flags
    local rw_status="read"
    if echo "$fd_info" | grep -qE '[uw]'; then
      rw_status="write"
    fi

    # Categorize as system or user process
    local proc_type="user"
    if is_system_process "$proc_name"; then
      proc_type="system"
    fi

    echo "${proc_name}|${pid}|${rw_status}|${proc_type}"
  done <<< "$lsof_output"
}

# ── Analyze blockers (sets global vars, no output) ─────────────────
analyze_blockers() {
  local blockers="$1"
  HAS_WRITERS=false
  USER_COUNT=0
  SYSTEM_COUNT=0

  while IFS='|' read -r name pid rw type; do
    [ -z "$name" ] && continue
    if [ "$type" = "system" ]; then
      SYSTEM_COUNT=$((SYSTEM_COUNT + 1))
    else
      USER_COUNT=$((USER_COUNT + 1))
    fi
    if [ "$rw" = "write" ]; then
      HAS_WRITERS=true
    fi
  done <<< "$blockers"
}

# ── Display blockers ───────────────────────────────────────────────
display_blockers() {
  local blockers="$1"

  echo ""
  echo -e "${BOLD}Blocking processes:${RESET}"
  echo ""

  while IFS='|' read -r name pid rw type; do
    [ -z "$name" ] && continue

    local type_label rw_label rw_color
    if [ "$type" = "system" ]; then
      type_label="${DIM}system${RESET}"
    else
      type_label="${BOLD}user app${RESET}"
    fi

    if [ "$rw" = "write" ]; then
      rw_label="${RED}${BOLD}WRITING${RESET}"
      rw_color="${RED}"
    else
      rw_label="${DIM}reading${RESET}"
      rw_color="${DIM}"
    fi

    echo -e "  ${rw_color}●${RESET} ${BOLD}${name}${RESET} (PID ${pid}) — ${rw_label} — ${type_label}"
  done <<< "$blockers"

  echo ""
  info "${USER_COUNT} user app(s), ${SYSTEM_COUNT} system process(es)"

  if [ "$SYSTEM_COUNT" -gt 0 ]; then
    echo -e "  ${DIM}System processes (Spotlight, iCloud, etc.) release automatically on unmount${RESET}"
  fi

  if $HAS_WRITERS; then
    echo ""
    warn "${RED}${BOLD}WARNING: One or more processes are actively WRITING to this disk!${RESET}"
    warn "Ejecting now could cause data corruption or file loss."
  fi
}

# ── Close user apps ────────────────────────────────────────────────
close_user_apps() {
  local blockers="$1"
  local closed=0

  while IFS='|' read -r name pid rw type; do
    [ -z "$name" ] && continue
    [ "$type" = "system" ] && continue

    step "Closing ${BOLD}${name}${RESET} (PID ${pid})..."

    # Try graceful kill first (SIGTERM)
    if kill "$pid" 2>/dev/null; then
      # Wait up to 5 seconds for process to exit
      local waited=0
      while kill -0 "$pid" 2>/dev/null && [ $waited -lt 5 ]; do
        sleep 1
        waited=$((waited + 1))
      done

      if kill -0 "$pid" 2>/dev/null; then
        warn "${name} didn't close gracefully, sending SIGKILL..."
        kill -9 "$pid" 2>/dev/null || true
        sleep 1
      fi

      if ! kill -0 "$pid" 2>/dev/null; then
        info "${name} closed"
        closed=$((closed + 1))
      else
        error "Could not close ${name} (PID ${pid})"
      fi
    else
      error "Could not signal ${name} (PID ${pid}) — permission denied?"
    fi
  done <<< "$blockers"

  echo "$closed"
}

# ── Eject disk ─────────────────────────────────────────────────────
eject_disk() {
  local volume_name="$1"
  local volume_path="/Volumes/${volume_name}"

  step "Attempting to eject ${BOLD}${volume_name}${RESET}..."

  # Try normal unmount first
  if diskutil unmountDisk "$volume_path" 2>/dev/null; then
    echo ""
    info "${GREEN}${BOLD}${volume_name} ejected successfully!${RESET}"
    echo -e "  ${DIM}Safe to remove the disk.${RESET}"
    return 0
  fi

  # Normal unmount failed — try force
  warn "Normal eject failed. Trying force unmount..."

  if diskutil unmountDisk force "$volume_path" 2>/dev/null; then
    echo ""
    info "${GREEN}${BOLD}${volume_name} force-ejected successfully!${RESET}"
    echo -e "  ${DIM}Safe to remove the disk.${RESET}"
    return 0
  fi

  echo ""
  error "Could not eject ${volume_name}. Try closing all apps manually or restart Finder."
  return 1
}

# ── Main ────────────────────────────────────────────────────────────
main() {
  print_header

  local target_volume=""

  # If volume name passed as argument, use it directly
  if [ $# -gt 0 ]; then
    target_volume="$1"
    if [ ! -d "/Volumes/${target_volume}" ]; then
      error "Volume '${target_volume}' not found in /Volumes"
      echo ""
      echo "Available volumes:"
      list_volumes | while read -r v; do
        echo "  • $v"
      done
      exit 1
    fi
  else
    # List volumes and let user pick
    step "Scanning for external volumes..."
    echo ""

    local volumes=()
    while IFS= read -r v; do
      [ -z "$v" ] && continue
      volumes+=("$v")
    done < <(list_volumes)

    if [ ${#volumes[@]} -eq 0 ]; then
      warn "No external volumes found."
      exit 0
    fi

    echo -e "${BOLD}Found ${#volumes[@]} volume(s):${RESET}"
    echo ""
    for i in "${!volumes[@]}"; do
      echo -e "  ${GREEN}$((i + 1))${RESET}) ${volumes[$i]}"
    done
    echo ""

    local choice
    read -rp "$(echo -e "${CYAN}→${RESET} Select volume to eject [1-${#volumes[@]}]: ")" choice

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt "${#volumes[@]}" ]; then
      error "Invalid selection."
      exit 1
    fi

    target_volume="${volumes[$((choice - 1))]}"
  fi

  local volume_path="/Volumes/${target_volume}"
  echo ""
  step "Checking what's using ${BOLD}${target_volume}${RESET}..."

  # Find blocking processes
  local lsof_output
  lsof_output=$(find_blockers "$volume_path")

  if [ -z "$lsof_output" ]; then
    info "No blocking processes found."
    echo ""
    eject_disk "$target_volume"
    exit $?
  fi

  # Parse, analyze, and display blockers
  local blockers
  blockers=$(parse_blockers "$lsof_output")

  # Analyze sets HAS_WRITERS, USER_COUNT, SYSTEM_COUNT globals
  analyze_blockers "$blockers"
  display_blockers "$blockers"

  echo ""

  if [ "$USER_COUNT" -eq 0 ]; then
    info "Only system processes are blocking — these release on unmount."
    echo ""
    eject_disk "$target_volume"
    exit $?
  fi

  # Confirm before closing apps
  if [ "$HAS_WRITERS" = "true" ]; then
    echo ""
    echo -e "${RED}${BOLD}⚠  ACTIVE WRITES DETECTED${RESET}"
    echo -e "${RED}Closing writing processes may cause data loss.${RESET}"
    read -rp "$(echo -e "${YELLOW}→${RESET} Continue anyway? (y/N): ")" confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
      echo ""
      warn "Aborted. Wait for writes to complete, then try again."
      exit 0
    fi
  else
    read -rp "$(echo -e "${CYAN}→${RESET} Close blocking apps and eject? (Y/n): ")" confirm
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
      echo ""
      warn "Aborted."
      exit 0
    fi
  fi

  echo ""

  # Close user apps
  close_user_apps "$blockers" > /dev/null

  # Brief pause for processes to release handles
  sleep 1

  # Eject
  eject_disk "$target_volume"
}

main "$@"
