SHELL := /bin/bash

# Self-documenting help: targets with ## comments are listed.
.PHONY: help check check-t1 check-t2 clean


# Default target
help: ## Show this help message
	@echo "bt2iap — Bluetooth-to-iAP bridge for Mitsubishi Outlander MMCS"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'

check: check-t1 check-t2 ## Run all Mac-side quality gates (check-t1 then check-t2)

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
	@echo "==> [check-t1] systemd unit header check"
	@unit=systemd/ipod-gadget.service; \
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
	@echo "    PASS: systemd unit headers ([Unit] [Service] [Install])"
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
	@echo "==> [check-t2] systemd unit header check"
	@unit=systemd/audio-bridge.service; \
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
	@echo "    PASS: systemd/audio-bridge.service headers ([Unit] [Service] [Install])"
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

clean: ## No-op at T1
	@echo "Nothing to clean at T1."
