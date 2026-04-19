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
#   1. /opt/bt2iap/docs/research-ipod-gadget.md — parse every markdown
#      backticked token of the form `0xHHHH` (Tier A first-occurrence order
#      is preserved via awk dedupe).
#   2. Fallback hard-coded list (Tier A order from research doc §2.2):
#      0x1261 0x1260 0x1262 0x1263 0x1265 0x1266 0x1267
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
  "0x1261"
  "0x1260"
  "0x1262"
  "0x1263"
  "0x1265"
  "0x1266"
  "0x1267"
)

INTERACTIVE="${BT2IAP_INTERACTIVE:-0}"

## === Candidate parsing ===

# Parse hex product_ids from the research markdown (first column of each
# table row). Fall back to the hard-coded list if the file is absent or
# yields nothing.
parse_candidates() {
  local ids=()
  if [[ -f "${RESEARCH_DOC}" ]]; then
    # Prefer §2.2 Tier-ordered list (lines starting with "1. **Tier" ...
    # "4. **Tier"). Tier lines list candidates in priority order (A->B->C->D),
    # which is exactly what we want the loop to try.
    # Fall back to §2.1 table (hex-ordered) if Tier lines yield nothing.
    while IFS= read -r line; do
      ids+=("${line}")
    done < <(
      {
        # Tier lines first (explicit priority order).
        # shellcheck disable=SC2016  # backticks are literal markdown delimiters
        grep -E '^[0-9]+\. \*\*Tier' "${RESEARCH_DOC}" 2>/dev/null \
          | grep -oE '`0x[0-9a-fA-F]+`' \
          || true
        # Then §2.1 table rows (any remaining IDs in doc order).
        # shellcheck disable=SC2016  # backticks are literal markdown delimiters
        grep -oE '`0x[0-9a-fA-F]+`' "${RESEARCH_DOC}" 2>/dev/null \
          || true
      } \
        | tr -d '`' \
        | grep -viE '^0x05ac$' \
        | awk '!seen[$0]++'
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
  log "One-shot reload: sudo ${LOAD_GADGET} --product-id=${winner}"
  echo "To persist: sudo sed -i 's/^#\\?PRODUCT_ID=.*/PRODUCT_ID=${winner}/' /etc/default/bt2iap && sudo systemctl restart ipod-gadget.service"
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
