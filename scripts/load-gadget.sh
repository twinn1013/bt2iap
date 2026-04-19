#!/usr/bin/env bash
# =============================================================================
# bt2iap load-gadget.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Load the 3 ipod-gadget kernel modules in the correct order so the Pi
#   enumerates as an iPod over USB. Safe to re-run (reloads cleanly).
#
# Usage:
#   sudo /opt/bt2iap/scripts/load-gadget.sh
#   sudo /opt/bt2iap/scripts/load-gadget.sh --product-id=0x1297
#
# Module order:
#   modprobe libcomposite
#   insmod g_ipod_audio.ko
#   insmod g_ipod_hid.ko
#   insmod g_ipod_gadget.ko [product_id=<hex>]
#
# Verification:
#   After success, /dev/iap0 should exist.
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
  printf 'Usage: %s [--product-id=<hex>]\n' "$0" >&2
  printf '  --product-id=<hex>   optional USB product_id passed to g_ipod_gadget (e.g. 0x1297)\n' >&2
}

## === Constants ===

GADGET_DIR="/opt/bt2iap/vendor/ipod-gadget/gadget"
KO_AUDIO="${GADGET_DIR}/g_ipod_audio.ko"
KO_HID="${GADGET_DIR}/g_ipod_hid.ko"
KO_GADGET="${GADGET_DIR}/g_ipod_gadget.ko"

## === Argument parsing ===

PRODUCT_ID=""

for arg in "$@"; do
  case "${arg}" in
    --product-id=*)
      PRODUCT_ID="${arg#--product-id=}"
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

## === Entry ===

require_root

## === Sanity: verify .ko files exist ===

for ko in "${KO_AUDIO}" "${KO_HID}" "${KO_GADGET}"; do
  if [[ ! -f "${ko}" ]]; then
    log "ERROR: missing kernel module: ${ko}"
    log "Run bootstrap.sh first to build ipod-gadget."
    exit 1
  fi
done

## === libcomposite (idempotent via modprobe) ===

log "modprobe libcomposite"
modprobe libcomposite

## === Unload previous gadget if any (reverse order) ===

if lsmod | awk '{print $1}' | grep -qx 'g_ipod_audio'; then
  log "unloading previously loaded ipod-gadget modules (reverse order)"
  # rmmod reverse-order: gadget -> hid -> audio.
  for mod in g_ipod_gadget g_ipod_hid g_ipod_audio; do
    if lsmod | awk '{print $1}' | grep -qx "${mod}"; then
      log "  rmmod ${mod}"
      rmmod "${mod}"
    fi
  done
fi

## === Load in correct order ===

log "insmod g_ipod_audio.ko"
insmod "${KO_AUDIO}"

log "insmod g_ipod_hid.ko"
insmod "${KO_HID}"

if [[ -n "${PRODUCT_ID}" ]]; then
  log "insmod g_ipod_gadget.ko product_id=${PRODUCT_ID}"
  insmod "${KO_GADGET}" "product_id=${PRODUCT_ID}"
else
  log "insmod g_ipod_gadget.ko (default product_id)"
  insmod "${KO_GADGET}"
fi

## === Verify /dev/iap0 ===

sleep 1

if [[ -e /dev/iap0 ]]; then
  log "OK: /dev/iap0 present — gadget loaded."
  exit 0
else
  log "FAIL: /dev/iap0 not found after load."
  log "Check: dmesg | tail -n 40"
  exit 1
fi
