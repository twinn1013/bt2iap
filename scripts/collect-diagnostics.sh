#!/usr/bin/env bash
# =============================================================================
# bt2iap collect-diagnostics.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Bundle diagnostic output (dmesg, lsmod, lsusb, journalctl, service status,
#   ALSA/Bluetooth state) into a single tarball for support or offline analysis.
#   Run on the Pi when filing a bug or escalating a failure.
#
# Usage:
#   sudo /opt/bt2iap/scripts/collect-diagnostics.sh [--no-tar]
#
# Options:
#   --no-tar   Leave the tempdir unpacked (skip tar creation; useful for local
#              inspection without creating an archive).
#
# Output:
#   /tmp/bt2iap-diagnostics-<hostname>-<YYYYMMDD-HHMMSS>.tar.gz
#   The path is printed to stdout on completion.
#
# Privacy:
#   Bluetooth MAC addresses are partially masked (OUI kept, last 6 hex chars
#   replaced with XXXXXX).  Wi-Fi SSIDs may appear in journalctl output — a
#   reminder is printed.  Review the bundle before sharing.
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

## === Argument parsing ===

NO_TAR=0

for arg in "$@"; do
  case "${arg}" in
    --no-tar)
      NO_TAR=1
      ;;
    -h|--help)
      printf 'Usage: %s [--no-tar]\n' "$0" >&2
      printf '  --no-tar   Skip tar creation; leave tempdir for local inspection.\n' >&2
      exit 0
      ;;
    *)
      log "ERROR: unknown argument: ${arg}"
      exit 2
      ;;
  esac
done

## === Entry ===

require_root

## === Tempdir setup ===

TMPDIR_ROOT="$(mktemp -d /tmp/bt2iap-diag-XXXXXX)"
log "collecting diagnostics into ${TMPDIR_ROOT}"

## === Helper: run a command, write output to a file; never abort on failure ===

# run_into FILE CMD [ARGS...]
#   Runs CMD with ARGS.  On success writes stdout to FILE.
#   On failure writes the error message to FILE (prefixed with ERROR:) and
#   continues — the overall script does not exit.
run_into() {
  local dest="$1"
  shift
  if output="$("$@" 2>&1)"; then
    printf '%s\n' "${output}" > "${dest}"
  else
    printf 'ERROR: command failed (exit %s): %s\n' "$?" "$*" > "${dest}"
    printf '%s\n' "${output}" >> "${dest}"
  fi
}

## === Helper: mask Bluetooth MAC addresses in a file ===

# Replaces the last two octets of Bluetooth MAC addresses (XX:XX:XX:YY:YY:YY)
# with XXXXXX, keeping the vendor OUI (first three octets) for identification.
# Pattern targets colon-separated 6-byte hex addresses.
mask_bt_macs() {
  local file="$1"
  # Matches: AA:BB:CC:DD:EE:FF   (case-insensitive hex pairs, colon-separated)
  # Replaces DD:EE:FF with XX:XX:XX, keeping AA:BB:CC (OUI).
  sed -i -E \
    's/([0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}):[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}/\1:XX:XX:XX/g' \
    "${file}"
}

## =============================================================================
## 01-system
## =============================================================================

DIR01="${TMPDIR_ROOT}/01-system"
mkdir -p "${DIR01}"
log "01-system"

run_into "${DIR01}/uname-a.txt"       uname -a
run_into "${DIR01}/os-release.txt"    cat /etc/os-release
run_into "${DIR01}/proc-cmdline.txt"  cat /proc/cmdline
run_into "${DIR01}/lsmod.txt"         lsmod
run_into "${DIR01}/lscpu.txt"         lscpu
run_into "${DIR01}/free-h.txt"        free -h

if [[ -f /boot/config.txt ]]; then
  run_into "${DIR01}/boot-config.txt" cat /boot/config.txt
else
  printf 'INFO: /boot/config.txt not present on this system\n' \
    > "${DIR01}/boot-config.txt"
fi

if [[ -f /boot/cmdline.txt ]]; then
  run_into "${DIR01}/boot-cmdline.txt" cat /boot/cmdline.txt
else
  printf 'INFO: /boot/cmdline.txt not present on this system\n' \
    > "${DIR01}/boot-cmdline.txt"
fi

## =============================================================================
## 02-usb
## =============================================================================

DIR02="${TMPDIR_ROOT}/02-usb"
mkdir -p "${DIR02}"
log "02-usb"

run_into "${DIR02}/lsusb.txt"         lsusb
run_into "${DIR02}/lsusb-v.txt"       bash -c 'lsusb -v 2>/dev/null || true'

# configfs gadget UDC — only meaningful if gadget is loaded
if output="$(cat /sys/kernel/config/usb_gadget/*/UDC 2>/dev/null)"; then
  printf '%s\n' "${output}" > "${DIR02}/gadget-udc.txt"
else
  printf 'INFO: no configfs gadget UDC found (gadget not loaded or not using configfs)\n' \
    > "${DIR02}/gadget-udc.txt"
fi

# /dev/iap* presence
if output="$(ls /dev/iap* 2>/dev/null)"; then
  printf '%s\n' "${output}" > "${DIR02}/dev-iap.txt"
else
  printf 'INFO: no /dev/iap* devices found\n' > "${DIR02}/dev-iap.txt"
fi

## =============================================================================
## 03-bluetooth
## =============================================================================

DIR03="${TMPDIR_ROOT}/03-bluetooth"
mkdir -p "${DIR03}"
log "03-bluetooth"

run_into "${DIR03}/bluetoothctl-show.txt"    bluetoothctl show
run_into "${DIR03}/bluetoothctl-devices.txt" bluetoothctl devices
run_into "${DIR03}/bluetooth-service.txt"    \
  systemctl status bluetooth.service --no-pager
run_into "${DIR03}/bluealsa-service.txt"     \
  systemctl status bluealsa.service --no-pager

# Mask MAC addresses in bluetoothctl output
mask_bt_macs "${DIR03}/bluetoothctl-show.txt"
mask_bt_macs "${DIR03}/bluetoothctl-devices.txt"

## =============================================================================
## 04-alsa
## =============================================================================

DIR04="${TMPDIR_ROOT}/04-alsa"
mkdir -p "${DIR04}"
log "04-alsa"

run_into "${DIR04}/aplay-l.txt"          aplay -l
run_into "${DIR04}/aplay-L.txt"          aplay -L
run_into "${DIR04}/proc-asound-cards.txt" cat /proc/asound/cards
run_into "${DIR04}/proc-asound-modules.txt" cat /proc/asound/modules

if [[ -f /etc/asound.conf ]]; then
  run_into "${DIR04}/asound-conf.txt" cat /etc/asound.conf
else
  printf 'INFO: /etc/asound.conf not present\n' > "${DIR04}/asound-conf.txt"
fi

## =============================================================================
## 05-bt2iap-services
## =============================================================================

DIR05="${TMPDIR_ROOT}/05-bt2iap-services"
mkdir -p "${DIR05}"
log "05-bt2iap-services"

for svc in ipod-gadget.service audio-bridge.service pair-agent.service; do
  safe="${svc//./-}"  # e.g. ipod-gadget-service
  run_into "${DIR05}/${safe}-status.txt" \
    systemctl status "${svc}" --no-pager
  run_into "${DIR05}/${safe}-journal.txt" \
    bash -c "journalctl -u ${svc} --no-pager | tail -200"
done

## =============================================================================
## 06-dmesg
## =============================================================================

DIR06="${TMPDIR_ROOT}/06-dmesg"
mkdir -p "${DIR06}"
log "06-dmesg"

run_into "${DIR06}/dmesg-tail-500.txt" \
  bash -c 'dmesg | tail -500'
run_into "${DIR06}/dmesg-bt2iap-keywords.txt" \
  bash -c "dmesg | grep -iE 'iap|ipod|dwc2|bluealsa|apple|iphone' || true"

## =============================================================================
## 07-logs
## =============================================================================

DIR07="${TMPDIR_ROOT}/07-logs"
mkdir -p "${DIR07}"
log "07-logs"

run_into "${DIR07}/journalctl-1h.txt" \
  bash -c 'journalctl --since "1 hour ago" --no-pager | tail -500'

## =============================================================================
## Write collection manifest
## =============================================================================

{
  printf 'bt2iap diagnostic bundle\n'
  printf 'Collected: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'Host:      %s\n' "$(hostname)"
  printf 'Kernel:    %s\n' "$(uname -r)"
  printf '\nFiles collected:\n'
  find "${TMPDIR_ROOT}" -type f | sort | sed "s|${TMPDIR_ROOT}/||"
} > "${TMPDIR_ROOT}/MANIFEST.txt"

## =============================================================================
## Privacy reminder
## =============================================================================

log "NOTICE: Bluetooth MAC OUIs are retained (last 3 octets masked)."
log "NOTICE: Wi-Fi SSIDs may appear in 07-logs/journalctl-1h.txt — review before sharing."

## =============================================================================
## Pack or leave unpacked
## =============================================================================

if [[ ${NO_TAR} -eq 1 ]]; then
  log "--no-tar: leaving bundle unpacked at ${TMPDIR_ROOT}"
  printf '\nDiagnostic directory: %s\n' "${TMPDIR_ROOT}"
else
  TARBALL="/tmp/bt2iap-diagnostics-$(hostname)-$(date +%Y%m%d-%H%M%S).tar.gz"
  log "creating tarball ${TARBALL}"
  tar -czf "${TARBALL}" -C "$(dirname "${TMPDIR_ROOT}")" \
    "$(basename "${TMPDIR_ROOT}")"
  rm -rf "${TMPDIR_ROOT}"
  printf '\nDiagnostic bundle: %s\n' "${TARBALL}"
  printf 'REMINDER: Review the bundle for PII (Wi-Fi SSIDs, unmasked IDs) before sharing.\n'
fi
