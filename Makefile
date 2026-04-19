SHELL := /bin/bash

# Self-documenting help: targets with ## comments are listed.
.PHONY: help check check-t1 check-t2 check-t3 check-t4 clean


# Default target
help: ## Show this help message
	@echo "bt2iap — Bluetooth-to-iAP bridge for Mitsubishi Outlander MMCS"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

check: check-t1 check-t2 check-t3 check-t4 ## Run all Mac-side quality gates (check-t1 then check-t2 then check-t3 then check-t4)

check-t1: ## T1 quality gates: shellcheck, systemd headers, boot patches, doc presence
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not found."; \
		echo "Install:  brew install shellcheck   (macOS)"; \
		echo "          apt install shellcheck     (Linux/Debian)"; \
		exit 1; \
	fi
	@echo "==> [check-t1] shellcheck on scripts/"
	@if [ ! -d scripts ]; then \
		echo "ERROR: scripts/ directory not found. Run Workers 2 first."; \
		exit 1; \
	fi
	@fail=0; \
	for f in scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		shellcheck -x "$$f" || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "ERROR: shellcheck found issues in scripts/*.sh"; \
		exit 1; \
	fi
	@echo "    PASS: shellcheck"
	@echo ""
	@echo "==> [check-t1] systemd unit header check (ipod-gadget + ipod-session)"
	@fail=0; \
	for unit in systemd/ipod-gadget.service systemd/ipod-session.service; do \
		if [ ! -f "$$unit" ]; then \
			echo "ERROR: $$unit not found."; \
			fail=1; \
			continue; \
		fi; \
		for section in '\[Unit\]' '\[Service\]' '\[Install\]'; do \
			if ! grep -qE "$$section" "$$unit"; then \
				echo "ERROR: $$unit is missing section: $$section"; \
				fail=1; \
			fi; \
		done; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo "    PASS: systemd unit headers ([Unit] [Service] [Install])"
	@echo ""
	@echo "==> [check-t1] /etc/default/bt2iap.example presence"
	@if [ ! -f etc/default/bt2iap.example ]; then \
		echo "ERROR: etc/default/bt2iap.example not found (H5 PRODUCT_ID persistence artifact)"; \
		exit 1; \
	fi
	@echo "    PASS: etc/default/bt2iap.example exists"
	@echo ""
	@echo "==> [check-t1] boot patch content check"
	@cfg=boot/config.txt.patch; \
	if [ ! -f "$$cfg" ]; then \
		echo "ERROR: $$cfg not found."; \
		exit 1; \
	fi; \
	if ! grep -q 'dtoverlay=dwc2' "$$cfg"; then \
		echo "ERROR: $$cfg does not contain 'dtoverlay=dwc2'"; \
		exit 1; \
	fi
	@echo "    PASS: boot/config.txt.patch contains dtoverlay=dwc2"
	@cmd=boot/cmdline.txt.patch; \
	if [ ! -f "$$cmd" ]; then \
		echo "ERROR: $$cmd not found."; \
		exit 1; \
	fi; \
	if ! grep -q 'modules-load=dwc2' "$$cmd"; then \
		echo "ERROR: $$cmd does not contain 'modules-load=dwc2'"; \
		exit 1; \
	fi
	@echo "    PASS: boot/cmdline.txt.patch contains modules-load=dwc2"
	@echo ""
	@echo "==> [check-t1] docs presence check"
	@fail=0; \
	for doc in docs/research-ipod-gadget.md docs/verification-t1.md; do \
		if [ ! -f "$$doc" ]; then \
			echo "ERROR: $$doc not found."; \
			fail=1; \
		elif [ ! -s "$$doc" ]; then \
			echo "ERROR: $$doc exists but is empty."; \
			fail=1; \
		else \
			echo "    PASS: $$doc exists and is non-empty"; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo ""
	@echo "==> check-t1 PASSED"

check-t2: ## T2 quality gates: shellcheck (all scripts), systemd headers, ALSA config, docs, patch sentinel
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not found."; \
		echo "Install:  brew install shellcheck   (macOS)"; \
		echo "          apt install shellcheck     (Linux/Debian)"; \
		exit 1; \
	fi
	@echo "==> [check-t2] shellcheck on bluetooth/*.sh and scripts/*.sh"
	@fail=0; \
	for f in bluetooth/*.sh scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		shellcheck -x "$$f" || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "ERROR: shellcheck found issues in shell scripts"; \
		exit 1; \
	fi
	@echo "    PASS: shellcheck"
	@echo ""
	@echo "==> [check-t2] systemd unit header check (audio-bridge + audio-loopback)"
	@fail=0; \
	for unit in systemd/audio-bridge.service systemd/audio-loopback.service; do \
		if [ ! -f "$$unit" ]; then \
			echo "ERROR: $$unit not found."; \
			fail=1; \
			continue; \
		fi; \
		for section in '\[Unit\]' '\[Service\]' '\[Install\]'; do \
			if ! grep -qE "$$section" "$$unit"; then \
				echo "ERROR: $$unit is missing section: $$section"; \
				fail=1; \
			fi; \
		done; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo "    PASS: systemd/{audio-bridge,audio-loopback}.service headers ([Unit] [Service] [Install])"
	@echo ""
	@echo "==> [check-t2] modules-load.d/bt2iap.conf presence"
	@if [ ! -f modules-load.d/bt2iap.conf ]; then \
		echo "ERROR: modules-load.d/bt2iap.conf not found (H6 snd-aloop boot-time preload)"; \
		exit 1; \
	fi; \
	if ! grep -q 'snd-aloop' modules-load.d/bt2iap.conf; then \
		echo "ERROR: modules-load.d/bt2iap.conf does not list snd-aloop"; \
		exit 1; \
	fi
	@echo "    PASS: modules-load.d/bt2iap.conf exists and contains snd-aloop"
	@override=systemd/bluealsa.service.d/override.conf; \
	if [ ! -f "$$override" ]; then \
		echo "ERROR: $$override not found."; \
		exit 1; \
	fi; \
	if ! grep -qE '\[Service\]' "$$override"; then \
		echo "ERROR: $$override is missing [Service] section header"; \
		exit 1; \
	fi
	@echo "    PASS: systemd/bluealsa.service.d/override.conf has [Service]"
	@echo ""
	@echo "==> [check-t2] ALSA config sanity check"
	@asound=alsa/asound.conf; \
	if [ ! -f "$$asound" ]; then \
		echo "ERROR: $$asound not found."; \
		exit 1; \
	fi; \
	if ! grep -qE 'pcm\.|type' "$$asound"; then \
		echo "ERROR: $$asound contains no pcm.* or type directives — file may be empty or malformed"; \
		exit 1; \
	fi
	@echo "    PASS: alsa/asound.conf contains pcm/type directives"
	@echo ""
	@echo "==> [check-t2] docs presence check"
	@doc=docs/audio-topology.md; \
	if [ ! -f "$$doc" ]; then \
		echo "ERROR: $$doc not found."; \
		exit 1; \
	elif [ ! -s "$$doc" ]; then \
		echo "ERROR: $$doc exists but is empty."; \
		exit 1; \
	fi
	@echo "    PASS: docs/audio-topology.md exists and is non-empty"
	@echo ""
	@echo "==> [check-t2] bluetooth patch payload + sentinel check"
	@block=bluetooth/main.conf.patch.block; \
	if [ ! -f "$$block" ]; then \
		echo "ERROR: $$block not found (pure-INI deployable payload missing)."; \
		exit 1; \
	fi; \
	if ! grep -qF '# --- begin bt2iap ---' "$$block"; then \
		echo "ERROR: $$block is missing idempotency sentinel '# --- begin bt2iap ---'"; \
		exit 1; \
	fi; \
	if ! grep -qE '^\[General\]' "$$block" || ! grep -qE '^\[Policy\]' "$$block"; then \
		echo "ERROR: $$block is missing required [General] or [Policy] section"; \
		exit 1; \
	fi
	@echo "    PASS: bluetooth/main.conf.patch.block contains sentinel + [General]/[Policy]"
	@echo "==> [check-t2] pair-agent systemd unit header check"
	@unit=systemd/pair-agent.service; \
	if [ ! -f "$$unit" ]; then \
		echo "ERROR: $$unit not found."; \
		exit 1; \
	fi; \
	fail=0; \
	for section in '\[Unit\]' '\[Service\]' '\[Install\]'; do \
		if ! grep -qE "$$section" "$$unit"; then \
			echo "ERROR: $$unit is missing section: $$section"; \
			fail=1; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo "    PASS: systemd/pair-agent.service headers ([Unit] [Service] [Install])"
	@echo ""
	@echo "==> check-t2 PASSED"

check-t3: ## T3 quality gates: shellcheck (scripts/), T3 docs presence, cross-reference sanity
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not found."; \
		echo "Install:  brew install shellcheck   (macOS)"; \
		echo "          apt install shellcheck     (Linux/Debian)"; \
		exit 1; \
	fi
	@echo "==> [check-t3] shellcheck on scripts/"
	@fail=0; \
	for f in scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		shellcheck -x "$$f" || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "ERROR: shellcheck found issues in scripts/*.sh"; \
		exit 1; \
	fi
	@echo "    PASS: shellcheck"
	@echo ""
	@echo "==> [check-t3] T3 docs presence check"
	@fail=0; \
	for doc in docs/triage.md docs/iap-auth-deep-dive.md; do \
		if [ ! -f "$$doc" ]; then \
			echo "ERROR: $$doc not found."; \
			fail=1; \
		elif [ ! -s "$$doc" ]; then \
			echo "ERROR: $$doc exists but is empty."; \
			fail=1; \
		else \
			echo "    PASS: $$doc exists and is non-empty"; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo ""
	@echo "==> [check-t3] cross-reference: triage.md must link to iap-auth-deep-dive.md"
	@if ! grep -q 'iap-auth-deep-dive.md' docs/triage.md; then \
		echo "ERROR: docs/triage.md does not reference iap-auth-deep-dive.md"; \
		exit 1; \
	fi
	@echo "    PASS: docs/triage.md references iap-auth-deep-dive.md"
	@echo ""
	@echo "==> [check-t3] cross-reference: FM transmitter must appear only in rejection context"
	@if grep -q 'FM transmitter' docs/triage.md; then \
		if ! grep -A 3 -B 3 'FM transmitter' docs/triage.md \
			| grep -qiE 'reject|거부|명시적|policy|금지'; then \
			echo "ERROR: docs/triage.md mentions 'FM transmitter' without a rejection context."; \
			echo "       Add 'rejected', '거부', '명시적', 'policy', or '금지' within 3 lines."; \
			exit 1; \
		fi; \
		echo "    PASS: FM transmitter appears only in rejection context"; \
	else \
		echo "    PASS: FM transmitter not mentioned (no advocacy to check)"; \
	fi
	@echo ""
	@echo "==> [check-t3] collect-diagnostics.sh presence and executable"
	@if [ ! -f scripts/collect-diagnostics.sh ]; then \
		echo "ERROR: scripts/collect-diagnostics.sh not found."; \
		exit 1; \
	fi; \
	if [ ! -x scripts/collect-diagnostics.sh ]; then \
		echo "ERROR: scripts/collect-diagnostics.sh is not executable."; \
		exit 1; \
	fi
	@echo "    PASS: scripts/collect-diagnostics.sh exists and is executable"
	@echo ""
	@echo "==> check-t3 PASSED"

check-t4: ## T4 quality gates: shellcheck (scripts/), T4 docs presence, content sanity
	@if ! command -v shellcheck >/dev/null 2>&1; then \
		echo "ERROR: shellcheck not found."; \
		echo "Install:  brew install shellcheck   (macOS)"; \
		echo "          apt install shellcheck     (Linux/Debian)"; \
		exit 1; \
	fi
	@echo "==> [check-t4] shellcheck on scripts/"
	@fail=0; \
	for f in scripts/*.sh; do \
		[ -f "$$f" ] || continue; \
		shellcheck -x "$$f" || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then \
		echo "ERROR: shellcheck found issues in scripts/*.sh"; \
		exit 1; \
	fi
	@echo "    PASS: shellcheck"
	@echo ""
	@echo "==> [check-t4] T4 docs presence check"
	@fail=0; \
	for doc in docs/iap-messages.md docs/advanced-iap-tools.md; do \
		if [ ! -f "$$doc" ]; then \
			echo "ERROR: $$doc not found."; \
			fail=1; \
		elif [ ! -s "$$doc" ]; then \
			echo "ERROR: $$doc exists but is empty."; \
			fail=1; \
		else \
			echo "    PASS: $$doc exists and is non-empty"; \
		fi; \
	done; \
	if [ $$fail -ne 0 ]; then exit 1; fi
	@echo ""
	@echo "==> [check-t4] content sanity: iap-messages.md must mention 'iAP' and 'lingo'"
	@if ! grep -q 'iAP' docs/iap-messages.md; then \
		echo "ERROR: docs/iap-messages.md does not mention 'iAP'"; \
		exit 1; \
	fi; \
	if ! grep -qi 'lingo' docs/iap-messages.md; then \
		echo "ERROR: docs/iap-messages.md does not mention 'lingo'"; \
		exit 1; \
	fi
	@echo "    PASS: docs/iap-messages.md contains 'iAP' and 'lingo'"
	@echo ""
	@echo "==> [check-t4] content sanity: advanced-iap-tools.md must mention 'usbmon' or 'Saleae'"
	@if ! grep -qE 'usbmon|Saleae' docs/advanced-iap-tools.md; then \
		echo "ERROR: docs/advanced-iap-tools.md does not mention 'usbmon' or 'Saleae'"; \
		exit 1; \
	fi
	@echo "    PASS: docs/advanced-iap-tools.md contains at least one capture tool reference"
	@echo ""
	@echo "==> check-t4 PASSED"

clean: ## No-op at T1
	@echo "Nothing to clean at T1."
