#!/usr/bin/env bash
# =============================================================================
# bt2iap bootstrap.sh
# -----------------------------------------------------------------------------
# Purpose:
#   One-time setup on a Raspberry Pi Zero 2 W for the bt2iap project.
#   Installs apt dependencies, fetches and builds oandrew/ipod-gadget
#   (kernel modules) plus oandrew/ipod (Go client), applies /boot patches,
#   and installs the ipod-gadget systemd unit.
#
# Usage:
#   sudo /opt/bt2iap/scripts/bootstrap.sh
#
# Idempotent: safe to re-run. Existing checkouts are git-pulled; the .ko
# modules and Go binary are rebuilt only if missing; /boot patches and
# systemd units are sentinel-guarded.
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

BT2IAP_ROOT="/opt/bt2iap"
VENDOR_DIR="${BT2IAP_ROOT}/vendor"
IPOD_GADGET_DIR="${VENDOR_DIR}/ipod-gadget"
IPOD_CLIENT_DIR="${VENDOR_DIR}/ipod"
IPOD_GADGET_REPO="https://github.com/oandrew/ipod-gadget"
IPOD_CLIENT_REPO="https://github.com/oandrew/ipod"

BOOT_CONFIG="/boot/config.txt"
BOOT_CMDLINE="/boot/cmdline.txt"
BOOT_CONFIG_PATCH="${BT2IAP_ROOT}/boot/config.txt.patch"

SYSTEMD_UNIT_SRC="${BT2IAP_ROOT}/systemd/ipod-gadget.service"
SYSTEMD_UNIT_DST="/etc/systemd/system/ipod-gadget.service"

SENTINEL_BEGIN="# --- begin bt2iap ---"
SENTINEL_END="# --- end bt2iap ---"

REQUIRED_KOS=(
  "${IPOD_GADGET_DIR}/gadget/g_ipod_audio.ko"
  "${IPOD_GADGET_DIR}/gadget/g_ipod_hid.ko"
  "${IPOD_GADGET_DIR}/gadget/g_ipod_gadget.ko"
)

IPOD_CLIENT_BIN="${IPOD_CLIENT_DIR}/ipod"

## === Entry ===

require_root

## === apt dependencies ===

log "apt update"
apt update

log "apt install build deps"
apt install -y \
  build-essential \
  raspberrypi-kernel-headers \
  golang \
  bluez \
  bluez-tools \
  bluealsa \
  git

## === vendor directory ===

log "ensure ${VENDOR_DIR}"
install -d -m 0755 "${VENDOR_DIR}"

## === ipod-gadget: clone or pull ===

if [[ -d "${IPOD_GADGET_DIR}/.git" ]]; then
  log "ipod-gadget: git pull (existing checkout)"
  git -C "${IPOD_GADGET_DIR}" pull --ff-only
else
  log "ipod-gadget: cloning"
  git clone "${IPOD_GADGET_REPO}" "${IPOD_GADGET_DIR}"
fi

## === ipod-gadget: build kernel modules if any .ko missing ===

need_build=0
for ko in "${REQUIRED_KOS[@]}"; do
  if [[ ! -f "${ko}" ]]; then
    need_build=1
    break
  fi
done

if [[ ${need_build} -eq 1 ]]; then
  log "ipod-gadget: building kernel modules"
  make -C "${IPOD_GADGET_DIR}/gadget"
else
  log "ipod-gadget: all .ko present, skip make"
fi

## === ipod (Go client): clone or pull ===

if [[ -d "${IPOD_CLIENT_DIR}/.git" ]]; then
  log "ipod client: git pull (existing checkout)"
  git -C "${IPOD_CLIENT_DIR}" pull --ff-only
else
  log "ipod client: cloning"
  git clone "${IPOD_CLIENT_REPO}" "${IPOD_CLIENT_DIR}"
fi

## === ipod (Go client): build binary if missing or stale ===
# "stale" = older than any .go source under the repo.

build_ipod=0
if [[ ! -x "${IPOD_CLIENT_BIN}" ]]; then
  build_ipod=1
else
  # shellcheck disable=SC2012
  newest_src=$(find "${IPOD_CLIENT_DIR}" -type f -name '*.go' -newer "${IPOD_CLIENT_BIN}" -print -quit)
  if [[ -n "${newest_src}" ]]; then
    build_ipod=1
  fi
fi

if [[ ${build_ipod} -eq 1 ]]; then
  log "ipod client: go build"
  (
    cd "${IPOD_CLIENT_DIR}"
    go build -o ./ipod ./cmd/ipod
  )
else
  log "ipod client: binary up-to-date, skip build"
fi

## === /boot/config.txt patch ===

if [[ -f "${BOOT_CONFIG_PATCH}" ]]; then
  if grep -qF "${SENTINEL_BEGIN}" "${BOOT_CONFIG}" 2>/dev/null; then
    log "${BOOT_CONFIG}: bt2iap block already present, skip"
  else
    log "${BOOT_CONFIG}: appending bt2iap block"
    {
      printf '\n%s\n' "${SENTINEL_BEGIN}"
      cat "${BOOT_CONFIG_PATCH}"
      printf '%s\n' "${SENTINEL_END}"
    } >> "${BOOT_CONFIG}"
  fi
else
  log "WARN: ${BOOT_CONFIG_PATCH} not found, skipping config.txt patch"
fi

## === /boot/cmdline.txt patch ===

if [[ -f "${BOOT_CMDLINE}" ]]; then
  if grep -qE '(^|[[:space:]])modules-load=([^[:space:]]*,)?dwc2' "${BOOT_CMDLINE}"; then
    log "${BOOT_CMDLINE}: modules-load=dwc2 already present, skip"
  else
    log "${BOOT_CMDLINE}: inserting modules-load=dwc2 after rootwait"
    # Preserve original as backup; insert once after the first 'rootwait '.
    cp -a "${BOOT_CMDLINE}" "${BOOT_CMDLINE}.bt2iap.bak"
    sed -i 's/\brootwait\b/rootwait modules-load=dwc2/' "${BOOT_CMDLINE}"
  fi
else
  log "WARN: ${BOOT_CMDLINE} not found, skipping cmdline.txt patch"
fi

## === systemd unit ===

if [[ -f "${SYSTEMD_UNIT_SRC}" ]]; then
  log "installing ${SYSTEMD_UNIT_DST}"
  install -m 0644 "${SYSTEMD_UNIT_SRC}" "${SYSTEMD_UNIT_DST}"
  log "systemctl daemon-reload"
  systemctl daemon-reload
  log "systemctl enable ipod-gadget.service"
  systemctl enable ipod-gadget.service
else
  log "WARN: ${SYSTEMD_UNIT_SRC} not found, skipping systemd install"
fi

## === Summary ===

log "----------------------------------------"
log "bootstrap complete."
log "  ipod-gadget:    ${IPOD_GADGET_DIR}"
log "  ipod client:    ${IPOD_CLIENT_BIN}"
log "  boot config:    ${BOOT_CONFIG}"
log "  boot cmdline:   ${BOOT_CMDLINE}"
log "  systemd unit:   ${SYSTEMD_UNIT_DST}"
log ""
log "REBOOT REQUIRED for dwc2 overlay and modules-load to take effect."
log "  sudo reboot"
