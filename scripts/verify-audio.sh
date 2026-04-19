#!/usr/bin/env bash
# =============================================================================
# bt2iap verify-audio.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Pi 하드웨어에서 T2 오디오 경로(BlueALSA → ALSA loopback → g_ipod_audio)의
#   각 레이어를 점검한다. 페어링된 폰 없이도 실행 가능하며, 실제 BT 연결이
#   필요한 항목은 Skip/WARN으로 처리하지 않고 서비스 활성 여부만 확인한다.
#
# Usage:
#   sudo /opt/bt2iap/scripts/verify-audio.sh [--verbose]
#
# Output:
#   [PASS|FAIL] check-name — reason/details
#   N/M checks passed
#   Exit 0 if all pass, 1 otherwise.
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

VERBOSE=0

for arg in "$@"; do
  case "${arg}" in
    --verbose|-v)
      VERBOSE=1
      ;;
    -h|--help)
      printf 'Usage: %s [--verbose]\n' "$0" >&2
      exit 0
      ;;
    *)
      log "ERROR: unknown argument: ${arg}"
      exit 2
      ;;
  esac
done

## === State tracking ===

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  local name="$1"
  local reason="$2"
  printf '[PASS] %s — %s\n' "${name}" "${reason}"
  PASS_COUNT=$(( PASS_COUNT + 1 ))
}

fail() {
  local name="$1"
  local reason="$2"
  printf '[FAIL] %s — %s\n' "${name}" "${reason}"
  FAIL_COUNT=$(( FAIL_COUNT + 1 ))
}

## === Entry ===

require_root

## =============================================================================
## Check 1: snd_aloop module loaded
## =============================================================================

if lsmod | grep -q 'snd_aloop'; then
  pass "snd_aloop-loaded" "module present in lsmod"
else
  fail "snd_aloop-loaded" "snd_aloop not in lsmod; run: sudo modprobe snd-aloop"
fi

## =============================================================================
## Check 2: Loopback card exists in /proc/asound/cards
## =============================================================================

if grep -qi 'Loopback' /proc/asound/cards 2>/dev/null; then
  pass "loopback-card-procfs" "Loopback card found in /proc/asound/cards"
else
  fail "loopback-card-procfs" "Loopback absent from /proc/asound/cards; snd_aloop loaded?"
fi

## =============================================================================
## Check 3: iPodUSB card exists in /proc/asound/cards
## =============================================================================

if grep -qi 'iPodUSB' /proc/asound/cards 2>/dev/null; then
  pass "ipodusb-card-procfs" "iPodUSB card found in /proc/asound/cards"
else
  fail "ipodusb-card-procfs" "iPodUSB absent; g_ipod_audio.ko must be loaded first (T1 load-gadget.sh)"
fi

## =============================================================================
## Check 4: aplay -l lists both Loopback and iPodUSB
## =============================================================================

aplay_out="$(aplay -l 2>&1 || true)"
loopback_in_aplay=0
ipodusb_in_aplay=0

if printf '%s\n' "${aplay_out}" | grep -qi 'Loopback'; then
  loopback_in_aplay=1
fi
if printf '%s\n' "${aplay_out}" | grep -qi 'iPodUSB'; then
  ipodusb_in_aplay=1
fi

if [[ ${loopback_in_aplay} -eq 1 && ${ipodusb_in_aplay} -eq 1 ]]; then
  pass "aplay-lists-both-cards" "aplay -l shows Loopback and iPodUSB"
elif [[ ${loopback_in_aplay} -eq 0 && ${ipodusb_in_aplay} -eq 0 ]]; then
  fail "aplay-lists-both-cards" "aplay -l shows neither Loopback nor iPodUSB"
elif [[ ${loopback_in_aplay} -eq 0 ]]; then
  fail "aplay-lists-both-cards" "aplay -l missing Loopback (iPodUSB present)"
else
  fail "aplay-lists-both-cards" "aplay -l missing iPodUSB (Loopback present)"
fi

## =============================================================================
## Check 5: /etc/asound.conf exists and is non-empty
## =============================================================================

if [[ -s /etc/asound.conf ]]; then
  pass "asound-conf-exists" "/etc/asound.conf is present and non-empty"
else
  fail "asound-conf-exists" "/etc/asound.conf missing or empty; deploy alsa/asound.conf"
fi

## =============================================================================
## Check 6: bluealsa.service is active
## =============================================================================

bluealsa_state="$(systemctl is-active bluealsa.service 2>/dev/null || true)"
if [[ "${bluealsa_state}" == "active" ]]; then
  pass "bluealsa-service-active" "bluealsa.service is active"
else
  fail "bluealsa-service-active" "bluealsa.service state=${bluealsa_state}; check: journalctl -u bluealsa.service"
fi

## =============================================================================
## Check 7: bluetooth.service is active
## =============================================================================

bt_state="$(systemctl is-active bluetooth.service 2>/dev/null || true)"
if [[ "${bt_state}" == "active" ]]; then
  pass "bluetooth-service-active" "bluetooth.service is active"
else
  fail "bluetooth-service-active" "bluetooth.service state=${bt_state}; check: journalctl -u bluetooth.service"
fi

## =============================================================================
## Check 8: audio-bridge.service is active
## =============================================================================

bridge_state="$(systemctl is-active audio-bridge.service 2>/dev/null || true)"
if [[ "${bridge_state}" == "active" ]]; then
  pass "audio-bridge-service-active" "audio-bridge.service is active"
else
  fail "audio-bridge-service-active" "audio-bridge.service state=${bridge_state}; check: journalctl -u audio-bridge.service"
fi

## =============================================================================
## Check 9: Bluetooth controller is powered
## =============================================================================

bt_show="$(bluetoothctl show 2>/dev/null || true)"
if printf '%s\n' "${bt_show}" | grep -qE 'Powered: yes'; then
  pass "bt-controller-powered" "bluetoothctl show confirms Powered: yes"
else
  fail "bt-controller-powered" "controller not powered; run: bluetoothctl power on"
fi

## =============================================================================
## Check 10: Optional probe — silence through ALSA default device
## =============================================================================

silence_result="$(timeout 3 bash -c \
  'dd if=/dev/zero bs=1024 count=16 2>/dev/null | aplay -D default -f S16_LE -r 48000 -c 2 - 2>&1' \
  | head -5 || true)"

if printf '%s\n' "${silence_result}" | grep -qiE 'ALSA.*error|cannot open|error opening|No such file'; then
  fail "silence-probe" "ALSA error during silence probe — chain not plumbed: ${silence_result}"
else
  pass "silence-probe" "silence routed through default ALSA device without ALSA errors"
fi

## =============================================================================
## Verbose dumps
## =============================================================================

if [[ ${VERBOSE} -eq 1 ]]; then
  printf '\n--- aplay -L (first 20 lines) ---\n'
  aplay -L 2>/dev/null | head -20 || true
  printf '\n--- bluetoothctl show ---\n'
  bluetoothctl show 2>/dev/null || true
  printf '\n--- /proc/asound/cards ---\n'
  cat /proc/asound/cards 2>/dev/null || true
  printf '\n--- systemctl status bluealsa.service (brief) ---\n'
  systemctl status bluealsa.service --no-pager -l 2>/dev/null | head -20 || true
  printf '\n--- systemctl status audio-bridge.service (brief) ---\n'
  systemctl status audio-bridge.service --no-pager -l 2>/dev/null | head -20 || true
fi

## =============================================================================
## Summary
## =============================================================================

TOTAL=$(( PASS_COUNT + FAIL_COUNT ))
printf '\n%d/%d checks passed\n' "${PASS_COUNT}" "${TOTAL}"

if [[ ${FAIL_COUNT} -eq 0 ]]; then
  exit 0
else
  exit 1
fi
