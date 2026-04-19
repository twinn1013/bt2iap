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

# Locate the boot configuration directory.
# Bookworm (current Pi OS) uses /boot/firmware/{config,cmdline}.txt;
# pre-Bookworm uses /boot/{config,cmdline}.txt. Fail loudly if neither
# exists so bootstrap does not silently skip the overlay/cmdline patch.
detect_boot_dir() {
  if [[ -f /boot/firmware/config.txt ]]; then
    printf '/boot/firmware'
  elif [[ -f /boot/config.txt ]]; then
    printf '/boot'
  else
    log "ERROR: cannot locate boot config (neither /boot/firmware/config.txt nor /boot/config.txt exists)"
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

BOOT_DIR="$(detect_boot_dir)"
BOOT_CONFIG="${BOOT_DIR}/config.txt"
BOOT_CMDLINE="${BOOT_DIR}/cmdline.txt"
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
    # Verify the patch landed — e.g. if the file has no 'rootwait' token the
    # sed above is a silent no-op and the module would never load at boot.
    if ! grep -q 'modules-load=dwc2' "${BOOT_CMDLINE}"; then
      log "ERROR: cmdline.txt patch did not apply — manual intervention required"
      exit 1
    fi
  fi
else
  log "WARN: ${BOOT_CMDLINE} not found, skipping cmdline.txt patch"
fi

## === systemd unit (T1 gadget loader) ===

if [[ -f "${SYSTEMD_UNIT_SRC}" ]]; then
  log "installing ${SYSTEMD_UNIT_DST}"
  install -m 0644 "${SYSTEMD_UNIT_SRC}" "${SYSTEMD_UNIT_DST}"
else
  log "WARN: ${SYSTEMD_UNIT_SRC} not found, skipping systemd install"
fi

## === /etc/default/bt2iap (optional PRODUCT_ID persistence) ===
# Only install the example if a live config is not already in place; we must
# not overwrite operator-tuned /etc/default/bt2iap on re-runs.

BT2IAP_DEFAULTS_SRC="${BT2IAP_ROOT}/etc/default/bt2iap.example"
BT2IAP_DEFAULTS_DST="/etc/default/bt2iap"
if [[ -f "${BT2IAP_DEFAULTS_SRC}" ]]; then
  if [[ -f "${BT2IAP_DEFAULTS_DST}" ]]; then
    log "${BT2IAP_DEFAULTS_DST}: already present, skip (preserves operator PRODUCT_ID)"
  else
    log "installing ${BT2IAP_DEFAULTS_DST}"
    install -D -m 0644 "${BT2IAP_DEFAULTS_SRC}" "${BT2IAP_DEFAULTS_DST}"
  fi
else
  log "WARN: ${BT2IAP_DEFAULTS_SRC} not found, skipping /etc/default/bt2iap"
fi

## === modules-load.d (boot-time kernel module hint) ===
# snd-aloop must be available before audio-bridge.service runs; libcomposite
# must be present before the ipod-gadget modules insmod. Listing both here
# avoids a race between service-manager startup and module availability.

MODULES_LOAD_SRC="${BT2IAP_ROOT}/modules-load.d/bt2iap.conf"
MODULES_LOAD_DST="/etc/modules-load.d/bt2iap.conf"
if [[ -f "${MODULES_LOAD_SRC}" ]]; then
  log "installing ${MODULES_LOAD_DST}"
  install -D -m 0644 "${MODULES_LOAD_SRC}" "${MODULES_LOAD_DST}"
else
  log "WARN: ${MODULES_LOAD_SRC} not found, skipping modules-load.d"
fi

## === T2 artifacts install ===
# Idempotent: all operations are install(1) with mode bits, sentinel-guarded
# appends, and short-circuits when files already exist. Missing source files
# emit WARN and skip — bootstrap.sh never aborts the whole run for a missing
# T2 file because T1 on its own is still useful as a standalone gadget boot.

## --- BlueZ main.conf patch (sentinel-guarded append) ---
BLUEZ_CONF="/etc/bluetooth/main.conf"
BLUEZ_BLOCK_SRC="${BT2IAP_ROOT}/bluetooth/main.conf.patch.block"
if [[ -f "${BLUEZ_BLOCK_SRC}" ]]; then
  if [[ -f "${BLUEZ_CONF}" ]]; then
    if grep -qF "${SENTINEL_BEGIN}" "${BLUEZ_CONF}" 2>/dev/null; then
      log "${BLUEZ_CONF}: bt2iap block already present, skip"
    else
      log "${BLUEZ_CONF}: appending bt2iap block"
      cat "${BLUEZ_BLOCK_SRC}" >> "${BLUEZ_CONF}"
    fi
  else
    log "WARN: ${BLUEZ_CONF} not found (bluez not installed?), skipping"
  fi
else
  log "WARN: ${BLUEZ_BLOCK_SRC} not found, skipping BlueZ patch"
fi

## --- BlueALSA drop-in override ---
BLUEALSA_OVERRIDE_SRC="${BT2IAP_ROOT}/systemd/bluealsa.service.d/override.conf"
BLUEALSA_OVERRIDE_DST="/etc/systemd/system/bluealsa.service.d/override.conf"
if [[ -f "${BLUEALSA_OVERRIDE_SRC}" ]]; then
  log "installing ${BLUEALSA_OVERRIDE_DST}"
  install -D -m 0644 "${BLUEALSA_OVERRIDE_SRC}" "${BLUEALSA_OVERRIDE_DST}"
else
  log "WARN: ${BLUEALSA_OVERRIDE_SRC} not found, skipping bluealsa override"
fi

## --- ALSA routing config ---
ASOUND_SRC="${BT2IAP_ROOT}/alsa/asound.conf"
ASOUND_DST="/etc/asound.conf"
if [[ -f "${ASOUND_SRC}" ]]; then
  log "installing ${ASOUND_DST}"
  install -D -m 0644 "${ASOUND_SRC}" "${ASOUND_DST}"
else
  log "WARN: ${ASOUND_SRC} not found, skipping asound.conf"
fi

## --- T2 scripts into /opt/bt2iap/scripts (installed here for consistency) ---
for script_name in audio-bridge.sh verify-audio.sh collect-diagnostics.sh; do
  src="${BT2IAP_ROOT}/scripts/${script_name}"
  dst="${BT2IAP_ROOT}/scripts/${script_name}"
  if [[ -f "${src}" ]]; then
    if [[ "${src}" != "${dst}" ]]; then
      log "installing ${dst}"
      install -m 0755 "${src}" "${dst}"
    else
      # Source == destination (repo lives at /opt/bt2iap); just ensure mode.
      chmod 0755 "${dst}"
    fi
  fi
done

## --- pair-agent.sh into /opt/bt2iap/bluetooth ---
PAIR_AGENT_SRC="${BT2IAP_ROOT}/bluetooth/pair-agent.sh"
PAIR_AGENT_DST="${BT2IAP_ROOT}/bluetooth/pair-agent.sh"
if [[ -f "${PAIR_AGENT_SRC}" ]]; then
  chmod 0755 "${PAIR_AGENT_DST}"
fi

## --- T2 systemd units ---
for unit_name in audio-bridge.service pair-agent.service audio-loopback.service ipod-session.service; do
  src="${BT2IAP_ROOT}/systemd/${unit_name}"
  dst="/etc/systemd/system/${unit_name}"
  if [[ -f "${src}" ]]; then
    log "installing ${dst}"
    install -m 0644 "${src}" "${dst}"
  else
    log "WARN: ${src} not found, skipping ${unit_name}"
  fi
done

## === systemd reload + enable ===

log "systemctl daemon-reload"
systemctl daemon-reload

# Enable services idempotently. Services not installed above are skipped
# gracefully by listing them conditionally.
ENABLE_UNITS=()
ENABLE_UNITS+=("ipod-gadget.service")
if [[ -f "/etc/systemd/system/ipod-session.service" ]]; then
  ENABLE_UNITS+=("ipod-session.service")
fi
if [[ -f "${BLUEALSA_OVERRIDE_DST}" ]]; then
  ENABLE_UNITS+=("bluealsa.service")
fi
for unit_name in audio-bridge.service audio-loopback.service pair-agent.service; do
  if [[ -f "/etc/systemd/system/${unit_name}" ]]; then
    ENABLE_UNITS+=("${unit_name}")
  fi
done

if [[ ${#ENABLE_UNITS[@]} -gt 0 ]]; then
  log "systemctl enable --now ${ENABLE_UNITS[*]}"
  systemctl enable --now "${ENABLE_UNITS[@]}" || \
    log "WARN: one or more services failed to start (check: systemctl --failed)"
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
