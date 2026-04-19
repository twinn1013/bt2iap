#!/usr/bin/env bash
# =============================================================================
# bt2iap product-id-loop.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Cycle through candidate USB product_ids when the default product_id is
#   rejected by the MMCS head unit. For each id: unload the ipod-gadget
#   stack, reload with product_id=<id>, wait, verify /dev/iap0, emit a
#   diagnostic line.
#
# Candidate sources (in order):
#   1. /opt/bt2iap/docs/research-ipod-gadget.md — parse the first column
#      of any markdown table cell matching ^\s*\|?\s*0x[0-9A-Fa-f]{4}\s*\|
#   2. Fallback hard-coded list:
#      0x1297 0x1267 0x129a 0x129c 0x1261 0x126a 0x1260
#
# Modes:
#   Default: dry-run — prints "[DRY-RUN] Tried $id — manual inspection
#   required" and moves on. Real MMCS recognition cannot be detected
#   without the head unit.
#
#   BT2IAP_INTERACTIVE=1: after each iteration, prompt "Did MMCS recognize
#   the device? (y/n/quit)". 'y' exits success with the winning id,
#   'n' continues, 'quit' aborts.
#
# Usage:
#   sudo /opt/bt2iap/scripts/product-id-loop.sh
#   sudo BT2IAP_INTERACTIVE=1 /opt/bt2iap/scripts/product-id-loop.sh
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

RESEARCH_DOC="/opt/bt2iap/docs/research-ipod-gadget.md"
LOAD_GADGET="/opt/bt2iap/scripts/load-gadget.sh"
DEEP_DIVE_DOC="/opt/bt2iap/docs/iap-auth-deep-dive.md"

FALLBACK_IDS=(
  "0x1297"
  "0x1267"
  "0x129a"
  "0x129c"
  "0x1261"
  "0x126a"
  "0x1260"
)

INTERACTIVE="${BT2IAP_INTERACTIVE:-0}"

## === Candidate parsing ===

# Parse hex product_ids from the research markdown (first column of each
# table row). Fall back to the hard-coded list if the file is absent or
# yields nothing.
parse_candidates() {
  local ids=()
  if [[ -f "${RESEARCH_DOC}" ]]; then
    # Match table rows: leading '|', then whitespace, then 0xXXXX in col 1.
    while IFS= read -r line; do
      ids+=("${line}")
    done < <(
      grep -Eo '^[[:space:]]*\|[[:space:]]*0x[0-9A-Fa-f]{4}' "${RESEARCH_DOC}" 2>/dev/null \
        | sed -E 's/^[[:space:]]*\|[[:space:]]*//' \
        | awk '{print $1}'
    )
  fi

  if [[ ${#ids[@]} -eq 0 ]]; then
    ids=("${FALLBACK_IDS[@]}")
  fi

  printf '%s\n' "${ids[@]}"
}

## === Entry ===

require_root

if [[ ! -x "${LOAD_GADGET}" ]]; then
  log "ERROR: ${LOAD_GADGET} not found or not executable"
  exit 1
fi

mapfile -t CANDIDATES < <(parse_candidates)

log "Will try ${#CANDIDATES[@]} candidate product_id(s):"
for id in "${CANDIDATES[@]}"; do
  log "  ${id}"
done

winner=""

for id in "${CANDIDATES[@]}"; do
  log "----- trying product_id=${id} -----"

  if ! "${LOAD_GADGET}" "--product-id=${id}"; then
    log "load-gadget failed for ${id}, moving to next candidate"
    continue
  fi

  sleep 5

  if [[ -e /dev/iap0 ]]; then
    log "/dev/iap0 present for ${id}"
  else
    log "/dev/iap0 missing for ${id}"
  fi

  if [[ "${INTERACTIVE}" == "1" ]]; then
    # Read from the controlling terminal so this works under pipes too.
    printf 'Did MMCS recognize the device? (y/n/quit): ' > /dev/tty
    answer=""
    read -r answer < /dev/tty || answer=""
    case "${answer}" in
      y|Y|yes|YES)
        winner="${id}"
        break
        ;;
      q|Q|quit|QUIT)
        log "user aborted"
        exit 130
        ;;
      *)
        log "user said no, continuing"
        ;;
    esac
  else
    printf '[DRY-RUN] Tried %s — manual inspection required\n' "${id}"
  fi
done

## === Result ===

if [[ -n "${winner}" ]]; then
  log "SUCCESS: MMCS accepted product_id=${winner}"
  log "Persist this id: sudo ${LOAD_GADGET} --product-id=${winner}"
  exit 0
fi

log "----------------------------------------"
log "All ${#CANDIDATES[@]} candidates exhausted."
if [[ "${INTERACTIVE}" == "1" ]]; then
  log "No user-confirmed hit among the candidate list."
else
  log "Dry-run mode: re-run with BT2IAP_INTERACTIVE=1 for prompted triage."
fi
log "Next step: consult ${DEEP_DIVE_DOC} (T3 iAP auth deep-dive runbook)."
exit 1
