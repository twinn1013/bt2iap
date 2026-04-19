#!/usr/bin/env bash
# =============================================================================
# bt2iap pair-agent.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Run a headless BlueZ pairing agent on the Raspberry Pi Zero 2 W so that a
#   phone can pair without any on-device confirmation (the Pi has no display
#   and no input). Combined with the bluetooth/main.conf.patch overrides
#   (DiscoverableTimeout=0, PairableTimeout=0, JustWorksRepairing=always)
#   this gives us a car-stereo-like "always open, auto-accept" Bluetooth
#   endpoint.
#
# Usage:
#   sudo /opt/bt2iap/bluetooth/pair-agent.sh
#
# Strategy:
#   Preferred: `bt-agent` from the `bluez-tools` apt package (installed by
#   scripts/bootstrap.sh in T1). It is a long-running daemon that registers a
#   BlueZ agent over D-Bus with a chosen I/O capability and auto-accepts.
#
#   Fallback: `bluetoothctl` fed a heredoc that enables the NoInputNoOutput
#   agent and then keeps stdin open. This path is documented inline below but
#   is NOT the default — bt-agent is more robust (handles D-Bus reconnects).
#
# Trap behavior:
#   SIGTERM / SIGINT cleanly stop the background agent and tear down
#   discoverable / pairable state so the controller does not stay wide open if
#   the service is disabled.
#
# Lint target: shellcheck 0.11.0 (zero warnings).
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

## === Constants ===

# bt-agent from bluez-tools. Capability matches JustWorks pairing: we advertise
# no input and no output, so BlueZ will use Just-Works / auto-accept.
BT_AGENT_BIN="/usr/bin/bt-agent"
BT_AGENT_CAPABILITY="NoInputNoOutput"

# bluetoothctl fallback path.
BLUETOOTHCTL_BIN="/usr/bin/bluetoothctl"

# PID of the background agent, set once we fork it.
AGENT_PID=""

## === Cleanup on exit ===

cleanup() {
  local rc=$?
  log "cleanup: tearing down agent (rc=${rc})"

  if [[ -n "${AGENT_PID}" ]] && kill -0 "${AGENT_PID}" 2>/dev/null; then
    log "  kill ${AGENT_PID}"
    kill "${AGENT_PID}" 2>/dev/null || true
    wait "${AGENT_PID}" 2>/dev/null || true
  fi

  # Close the pairing window so the controller is not left wide open if the
  # service is intentionally stopped. main.conf keeps defaults persistent, so
  # next boot re-opens via AutoEnable.
  if [[ -x "${BLUETOOTHCTL_BIN}" ]]; then
    "${BLUETOOTHCTL_BIN}" <<-'CTL' >/dev/null 2>&1 || true
		discoverable off
		pairable off
		quit
	CTL
  fi

  exit "${rc}"
}

trap cleanup EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

## === Entry ===

require_root

## === Power/discoverable/pairable bring-up via bluetoothctl ===
# bluetoothctl is interactive. Feeding it a heredoc is the documented idiom
# (see bluez-tools docs + `man bluetoothctl`). Each command terminates with a
# newline; `quit` closes the session cleanly.

if [[ ! -x "${BLUETOOTHCTL_BIN}" ]]; then
  log "ERROR: ${BLUETOOTHCTL_BIN} not found (install bluez)"
  exit 1
fi

log "bluetoothctl: power on / discoverable on / pairable on"
"${BLUETOOTHCTL_BIN}" <<-'CTL'
	power on
	discoverable on
	pairable on
	quit
CTL

## === Register the pairing agent ===

if [[ -x "${BT_AGENT_BIN}" ]]; then
  # Preferred: bt-agent from bluez-tools. Auto-accepts incoming pairings.
  log "bt-agent: capability=${BT_AGENT_CAPABILITY} (foreground mode)"
  "${BT_AGENT_BIN}" --capability="${BT_AGENT_CAPABILITY}" &
  AGENT_PID=$!
else
  # Fallback: bluetoothctl agent loop. Not as robust — bluetoothctl exits if
  # the D-Bus connection blips, so this path has no auto-reconnect. Documented
  # for hosts where bluez-tools is not installed.
  log "WARN: bt-agent not found; falling back to bluetoothctl agent loop"
  (
    "${BLUETOOTHCTL_BIN}" <<-'CTL'
		agent NoInputNoOutput
		default-agent
	CTL
    # Keep bluetoothctl resident so the agent stays registered.
    tail -f /dev/null
  ) &
  AGENT_PID=$!
fi

log "agent running (pid=${AGENT_PID}); waiting for exit signal"

# Block until the background agent terminates or we get SIGTERM / SIGINT.
# `wait` is interrupted by signals, which lets our traps fire.
wait "${AGENT_PID}"
