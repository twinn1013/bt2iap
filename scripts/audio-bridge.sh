#!/usr/bin/env bash
# =============================================================================
# bt2iap audio-bridge.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Pump audio from any connected Bluetooth A2DP source (via BlueALSA) into
#   the ALSA "default" PCM — which /etc/asound.conf wires to the snd-aloop
#   playback side, from which the loopback capture side is forwarded into
#   the iPodUSB gadget card exposed by g_ipod_audio.ko.
#
#   Audio chain reminder:
#       [Phone] --A2DP BT--> [BlueALSA]
#                         --> `bluealsa-aplay` (this script)
#                         --> hw:Loopback,0,0 (via pcm.!default)
#                         --> hw:Loopback,1,0 capture consumer
#                         --> hw:iPodUSB,0
#                         --> USB-A to Outlander MMCS
#
# Usage:
#   sudo /opt/bt2iap/scripts/audio-bridge.sh           # run under systemd
#   sudo /opt/bt2iap/scripts/audio-bridge.sh --dry-run # print and exit 0
#
# Notes:
#   - systemd (audio-bridge.service) supervises one instance; we do not
#     self-detach.
#   - Stdout/stderr are journaled when run as a service.
#   - `bluealsa-aplay 00:00:00:00:00:00` is the documented "any device"
#     wildcard (man bluealsa-aplay).
# =============================================================================

set -euo pipefail
IFS=$'\n\t'

## === Helpers ===

log() { printf '[%s] %s\n' "$(date +%Y-%m-%dT%H:%M:%S)" "$*" >&2; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    log "ERROR: must run as root (try: sudo $0)"
    exit 1
  fi
}

usage() {
  printf 'Usage: %s [--dry-run]\n' "$0" >&2
  printf '  --dry-run   print the command line that would run and exit 0\n' >&2
}

## === Constants ===

# "any device" wildcard — bluealsa-aplay streams from whichever A2DP source
# is currently connected. Matches the "zero MAC" convention documented in
# `man bluealsa-aplay` and in upstream arkq/bluez-alsa docs.
BLUEALSA_MAC="00:00:00:00:00:00"

# Target PCM: pcm.!default from /etc/asound.conf (which routes to loopback
# playback and on to iPodUSB). Using "default" keeps the asound.conf the
# single source of truth for topology.
ALSA_PCM="default"

# Verbose output so journald has something useful to show when debugging
# missing audio.
BLUEALSA_APLAY_BIN="/usr/bin/bluealsa-aplay"

## === Argument parsing ===

DRY_RUN=0

for arg in "$@"; do
  case "${arg}" in
    --dry-run)
      DRY_RUN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      log "ERROR: unknown argument: ${arg}"
      usage
      exit 2
      ;;
  esac
done

## === Build command ===

# bluealsa-aplay flags:
#   --pcm=<pcm>          output ALSA PCM (our loopback chain via default)
#   --profile-a2dp       only stream A2DP (ignore HFP/HSP)
#   -v                   verbose; each connect/disconnect logged
#   <MAC>                positional: source MAC, 00:..:00 = any
CMD=(
  "${BLUEALSA_APLAY_BIN}"
  "--pcm=${ALSA_PCM}"
  "--profile-a2dp"
  "-v"
  "${BLUEALSA_MAC}"
)

## === Dry-run short-circuit ===

if [[ ${DRY_RUN} -eq 1 ]]; then
  # Quote each argv element so the output is copy/paste safe.
  printf 'DRY RUN: would exec:'
  for tok in "${CMD[@]}"; do
    printf ' %q' "${tok}"
  done
  printf '\n'
  exit 0
fi

## === Entry (real run) ===

require_root

## === Ensure snd-aloop is loaded ===
# Idempotent: modprobe is a no-op if the module is already loaded.

if ! lsmod | awk '{print $1}' | grep -qx 'snd_aloop'; then
  log "modprobe snd-aloop"
  modprobe snd-aloop
else
  log "snd-aloop already loaded"
fi

## === Sanity: bluealsa-aplay must exist ===

if [[ ! -x "${BLUEALSA_APLAY_BIN}" ]]; then
  log "ERROR: ${BLUEALSA_APLAY_BIN} missing — install 'bluealsa' package"
  exit 1
fi

## === Signal handling ===
# systemd sends SIGTERM on stop; we forward to bluealsa-aplay via PGID kill.
# `exec`'d child inherits PID = $$ of subshell; we capture it instead.

CHILD_PID=""

on_term() {
  log "received signal, terminating bluealsa-aplay"
  if [[ -n "${CHILD_PID}" ]] && kill -0 "${CHILD_PID}" 2>/dev/null; then
    kill -TERM "${CHILD_PID}" 2>/dev/null || true
    # Give it 5s to shut down cleanly, then SIGKILL.
    for _ in 1 2 3 4 5; do
      if ! kill -0 "${CHILD_PID}" 2>/dev/null; then
        break
      fi
      sleep 1
    done
    if kill -0 "${CHILD_PID}" 2>/dev/null; then
      log "bluealsa-aplay did not exit on SIGTERM, sending SIGKILL"
      kill -KILL "${CHILD_PID}" 2>/dev/null || true
    fi
  fi
  exit 0
}

trap on_term TERM INT

## === Launch ===

log "launching: ${CMD[*]}"
"${CMD[@]}" &
CHILD_PID=$!

# `wait` returns the exit status of the child. With `set -e`, a non-zero
# exit from bluealsa-aplay would fail the script (good: systemd will
# Restart=on-failure it). We use `wait "${CHILD_PID}"` so signals delivered
# to this script wake the wait.
wait "${CHILD_PID}"
